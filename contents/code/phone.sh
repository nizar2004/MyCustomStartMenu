#!/bin/sh
# phone.sh — KDE Connect bridge for the Custom Start Menu's phone panel.
# The widget's executable engine runs command strings without a shell, so
# every operation is one plain script invocation:  sh phone.sh <cmd> [args]
#
# commands:
#   poll <id>                   panel payload: devices --- battery ---
#                               connectivity
#   ring <id>                   find my phone (ring the device)
#   ping <id> [msg]             send a ping notification
#   refresh                     re-scan for devices on the network
#   share <id> <path-or-url>    send a file or open a link on the phone
#   sharefile <id>              file picker (kdialog) + share the selection
#   sharetext <id> <text>       share text to the phone
#   clipboard <id>              send the desktop clipboard to the phone
#   browse <id>                 mount the phone filesystem (SFTP) and open it
#   type <id> <text>            type text into the phone (remote keyboard)
#   notif <id>                  list the phone's notifications (raw lines)
#   notifaction <id> <k> <a>    trigger an action on a notification
#   sms <id> <number> <msg>     send an SMS from the phone
#   messages <id>               open the KDE Connect SMS app for the device
#   pair <id> / unpair <id>     pairing management
#   encryption <id>             show the connection's encryption info

SEP=$(printf '\037')

# ------------------------------------------------------------- devices ----
# emits:  id <US> name <US> reachable(0|1)   for every PAIRED device
device_list() {
    kdeconnect-cli --list-devices 2>/dev/null | grep -E '^- .+\(paired' | \
    while IFS= read -r line; do
        rest=${line#- }
        name=${rest%%: *}
        [ -n "$name" ] || continue
        tail=${rest#*: }
        # kdeconnect-cli prints the id followed by a variable status suffix:
        #   "<id>"                                    (unpaired/edge cases)
        #   "<id> (paired)"                           (paired, offline)
        #   "<id> on 192.168.1.2 via LAN (paired and reachable)"
        # The id is always the FIRST whitespace-delimited token, so cut
        # everything from the first space. The old "${tail%% on*}" only
        # handled the reachable form — the offline form kept its " (paired)"
        # suffix, making every DBus path built from it invalid (battery and
        # connectivity read -1, and every action failed silently).
        id=${tail%% *}
        st=$(printf '%s' "$tail" | sed -n 's/^.*(\(.*\))$/\1/p')
        r=0
        case "$st" in
            *reachable*) r=1 ;;
        esac
        printf '%s%s%s%s%d\n' "$id" "$SEP" "$name" "$SEP" "$r"
    done
}

battery_line() {
    id="$1"
    P=/modules/kdeconnect/devices/$id/battery
    C=$(busctl --user get-property org.kde.kdeconnect "$P" \
        org.kde.kdeconnect.device.battery charge 2>/dev/null | awk '{print $2}')
    G=$(busctl --user get-property org.kde.kdeconnect "$P" \
        org.kde.kdeconnect.device.battery isCharging 2>/dev/null | awk '{print $2}')
    case "$C" in ''|*[!0-9]*) C=-1 ;; esac
    printf '%s%s%s\n' "$C" "$SEP" "${G:-false}"
}

connectivity_line() {
    id="$1"
    P=/modules/kdeconnect/devices/$id/connectivity_report
    S=$(busctl --user get-property org.kde.kdeconnect "$P" \
        org.kde.kdeconnect.device.connectivity_report cellularNetworkStrength 2>/dev/null | awk '{print $2}')
    T=$(busctl --user get-property org.kde.kdeconnect "$P" \
        org.kde.kdeconnect.device.connectivity_report cellularNetworkType 2>/dev/null | \
        sed 's/^s //; s/^"//; s/"$//')
    case "$S" in ''|*[!0-9]*) S=-1 ;; esac
    printf '%s%s%s\n' "$S" "$SEP" "$T"
}

case "$1" in
    poll)
        device_list
        printf -- '---\n'
        battery_line "$2"
        printf -- '---\n'
        connectivity_line "$2"
        ;;
    ring)
        [ -n "$2" ] && kdeconnect-cli --ring -d "$2" >/dev/null 2>&1
        ;;
    ping)
        if [ -n "$3" ]; then
            kdeconnect-cli --ping-msg "$3" -d "$2" >/dev/null 2>&1
        else
            [ -n "$2" ] && kdeconnect-cli --ping -d "$2" >/dev/null 2>&1
        fi
        ;;
    share)
        # NOTE: the device flag must come BEFORE --share: the option consumes
        # the next token as its value, so "kdeconnect-cli --share -d <id> <url>"
        # fails with "No device specified".
        [ -n "$2" ] && [ -n "$3" ] && kdeconnect-cli -d "$2" --share "$3" >/dev/null 2>&1
        ;;
    sharefile)
        id="$2"
        [ -n "$id" ] || exit 0
        F=$(kdialog --getopenfilename "$HOME" 2>/dev/null)
        [ -n "$F" ] && kdeconnect-cli -d "$id" --share "$F" >/dev/null 2>&1
        ;;
    sharetext)
        [ -n "$2" ] && [ -n "$3" ] && qdbus6 org.kde.kdeconnect \
            "/modules/kdeconnect/devices/$2/share" \
            org.kde.kdeconnect.device.share.shareText "$3" >/dev/null 2>&1
        ;;
    clipboard)
        # Send the desktop clipboard through the daemon's clipboard plugin —
        # the same call the KDE Connect applet makes. kdeconnect-cli is only a
        # fallback: on Wayland it often cannot read the clipboard, which is
        # why this button appeared to do nothing.
        id="$2"
        [ -n "$id" ] || exit 0
        if busctl --user call org.kde.kdeconnect \
              "/modules/kdeconnect/devices/$id/clipboard" \
              org.kde.kdeconnect.device.clipboard sendClipboard >/dev/null 2>&1; then
            exit 0
        fi
        kdeconnect-cli --send-clipboard -d "$id" >/dev/null 2>&1
        ;;
    browse)
        id="$2"
        [ -n "$id" ] || exit 0
        P=/modules/kdeconnect/devices/$id/sftp
        M=$(busctl --user call org.kde.kdeconnect "$P" \
            org.kde.kdeconnect.device.sftp mountAndWait 2>/dev/null | awk '{print $2}')
        if [ "$M" != "true" ]; then
            ERR=$(busctl --user call org.kde.kdeconnect "$P" \
                org.kde.kdeconnect.device.sftp getMountError 2>/dev/null | \
                sed 's/^s //; s/^"//; s/"$//')
            command -v notify-send >/dev/null 2>&1 && \
                notify-send -a "Custom Start Menu" -i "smartphone" \
                    "Could not open phone files" \
                    "${ERR:-the device did not respond}" &
            exit 0
        fi
        MP=$(busctl --user call org.kde.kdeconnect "$P" \
            org.kde.kdeconnect.device.sftp mountPoint 2>/dev/null | \
            sed 's/^s //; s/^"//; s/"$//')
        [ -n "$MP" ] && ( setsid xdg-open "$MP" >/dev/null 2>&1 </dev/null & )
        ;;
    type)
        [ -n "$2" ] && [ -n "$3" ] && qdbus6 org.kde.kdeconnect \
            "/modules/kdeconnect/devices/$2/remotekeyboard" \
            org.kde.kdeconnect.device.remotekeyboard.sendKeyPress "$3" >/dev/null 2>&1
        ;;
    notif)
        # two-step listing, exactly like kdeconnect-cli: fetch the active
        # notification ids, then read each notification object's properties.
        # Properties are read with qdbus6 (NOT busctl): busctl escapes non-ASCII
        # as \NNN octal, which garbles Arabic/Chinese titles.
        id="$2"
        [ -n "$id" ] || exit 0
        BASE=/modules/kdeconnect/devices/$id/notifications
        IDS=$(busctl --user call org.kde.kdeconnect "$BASE" \
            org.kde.kdeconnect.device.notifications activeNotifications 2>/dev/null)
        printf '%s' "$IDS" | tr ' ' '\n' | grep -oE '"[^"]+"' | tr -d '"' | \
        while IFS= read -r nid; do
            [ -n "$nid" ] || continue
            NP="$BASE/$nid"
            NIF=org.kde.kdeconnect.device.notifications.notification
            APP=$(qdbus6 org.kde.kdeconnect "$NP" org.freedesktop.DBus.Properties.Get \
                "$NIF" appName 2>/dev/null)
            TITLE=$(qdbus6 org.kde.kdeconnect "$NP" org.freedesktop.DBus.Properties.Get \
                "$NIF" title 2>/dev/null)
            DISM=$(qdbus6 org.kde.kdeconnect "$NP" org.freedesktop.DBus.Properties.Get \
                "$NIF" dismissable 2>/dev/null)
            [ -n "$TITLE" ] || TITLE=$(qdbus6 org.kde.kdeconnect "$NP" \
                org.freedesktop.DBus.Properties.Get "$NIF" ticker 2>/dev/null)
            [ "$DISM" = "true" ] && D=1 || D=0
            printf '%s%s%s%s%s%s%s\n' "$nid" "$SEP" "$APP" "$SEP" "$TITLE" "$SEP" "$D"
        done
        ;;
    notifdismiss)
        [ -n "$2" ] && [ -n "$3" ] && qdbus6 org.kde.kdeconnect \
            "/modules/kdeconnect/devices/$2/notifications/$3" \
            org.kde.kdeconnect.device.notifications.notification.dismiss >/dev/null 2>&1
        ;;
    notifaction)
        [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ] && qdbus6 org.kde.kdeconnect \
            "/modules/kdeconnect/devices/$2/notifications" \
            org.kde.kdeconnect.device.notifications.sendAction "$3" "$4" >/dev/null 2>&1
        ;;
    sms)
        [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ] && \
            kdeconnect-cli --send-sms "$4" --destination "$3" -d "$2" >/dev/null 2>&1
        ;;
    messages)
        # Open the official KDE Connect SMS app for this device — it shows the
        # phone's SMS conversations and lets you reply.
        id="$2"
        [ -n "$id" ] || exit 0
        ( setsid kdeconnect-sms --device "$id" >/dev/null 2>&1 </dev/null & )
        ;;
    pair|unpair)
        [ -n "$2" ] && kdeconnect-cli --"$1" -d "$2" >/dev/null 2>&1
        ;;
    encryption)
        [ -n "$2" ] && kdeconnect-cli --encryption-info -d "$2" 2>/dev/null
        ;;
esac
