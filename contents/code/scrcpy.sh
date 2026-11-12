#!/bin/sh
# scrcpy.sh — mirror the phone on the desktop (scrcpy over Wi-Fi), driven by
# the Custom Start Menu widget. The executable engine runs command strings
# without a shell, so everything goes through this one script:
#
#   scrcpy.sh start [serial]   connect over Wi-Fi if needed, launch scrcpy
#   scrcpy.sh stop             close a mirror started this way
#   scrcpy.sh status           print "running" or "stopped"
#   scrcpy.sh serial [serial]  get/set the remembered device serial
#
# The device serial is remembered in
#   $XDG_STATE_HOME/custom-start-menu/scrcpy-serial
# When none is set we ask adb's mDNS discovery for the phone's
# "_adb-tls-connect._tcp" endpoint — that avoids chasing the random
# wireless-debugging port after every phone reboot.

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/custom-start-menu"
SERIAL_FILE="$STATE_DIR/scrcpy-serial"
mkdir -p "$STATE_DIR" 2>/dev/null

notify() {
    command -v notify-send >/dev/null 2>&1 && \
        notify-send -a "Custom Start Menu" -i "phone" "$1" "${2:-}" &
}

# the phone's current wireless-debugging endpoint (ip:port or mDNS name).
# mDNS can take a moment to answer on a weak link, so retry a few times and
# finally fall back to a device that adb already has connected.
discover_serial() {
    command -v adb >/dev/null 2>&1 || return 0
    i=0
    while [ "$i" -lt 4 ]; do
        s=$(adb mdns services 2>/dev/null | \
            awk '/_adb-tls-connect\._tcp/ {print $3; exit}')
        [ -n "$s" ] && { printf '%s' "$s"; return; }
        i=$((i + 1))
        sleep 1
    done
    adb devices 2>/dev/null | awk 'NR > 1 && $2 == "device" {print $1; exit}'
}

resolve_serial() {
    if [ -n "$1" ]; then printf '%s' "$1"; return; fi
    if [ -f "$SERIAL_FILE" ]; then
        s=$(head -n1 "$SERIAL_FILE")
        [ -n "$s" ] && { printf '%s' "$s"; return; }
    fi
    discover_serial
}

is_alive() {
    [ -n "$1" ] && adb -s "$1" get-state >/dev/null 2>&1
}

case "$1" in
    start)
        if ! command -v adb >/dev/null 2>&1; then
            notify "Phone mirroring unavailable" \
                   "adb is missing — install: sudo pacman -S android-tools"
            exit 1
        fi
        if ! command -v scrcpy >/dev/null 2>&1; then
            notify "Phone mirroring unavailable" \
                   "scrcpy is missing — install: sudo pacman -S scrcpy"
            exit 1
        fi

        SER=$(resolve_serial "$2")

        # saved/discovered serial may be stale → reconnect, then re-discover
        case "$SER" in
            *:*) adb connect "$SER" >/dev/null 2>&1 ;;
        esac
        if ! is_alive "$SER"; then
            D=$(discover_serial)
            if [ -n "$D" ] && [ "$D" != "$SER" ]; then
                SER="$D"
                adb connect "$SER" >/dev/null 2>&1
            fi
        fi

        if ! is_alive "$SER"; then
            notify "No phone found" \
                   "Enable Wireless debugging and keep the phone on the same Wi-Fi."
            exit 1
        fi

        printf '%s\n' "$SER" > "$SERIAL_FILE"

        # detached: the widget must never wait on scrcpy
        ( setsid scrcpy -s "$SER" --stay-awake \
              --window-title="$( [ -n "$SER" ] && echo "Phone" )" \
              >/dev/null 2>&1 </dev/null & )
        ;;
    stop)
        pkill -x scrcpy >/dev/null 2>&1
        ;;
    status)
        if pgrep -x scrcpy >/dev/null 2>&1; then
            printf 'running\n'
        else
            printf 'stopped\n'
        fi
        ;;
    serial)
        if [ -n "$2" ]; then printf '%s\n' "$2" > "$SERIAL_FILE"; fi
        [ -f "$SERIAL_FILE" ] && cat "$SERIAL_FILE"
        ;;
esac
