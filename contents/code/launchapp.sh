#!/bin/sh
# launchapp.sh — launch a .desktop entry the way KDE's native application
# launcher (Kickoff) does, via KIO's KProcessRunner mechanics:
#
#   1. Preferred: a transient service in the user systemd manager
#      (app-<id>@<uuid>.service, Type=simple, ExitType=cgroup,
#      Slice=app.slice, SourcePath=<desktop file>, AddRef=true) — the app is
#      spawned by systemd, fully detached from plasmashell, and survives
#      plasmashell restarts.
#   2. Fallback: a setsid-detached fork (KIO's ForkingProcessRunner), so the
#      app never lives inside plasmashell's process tree either way.
#
# In both cases the app's stdio ends on the journal or /dev/null — never on
# a plasmashell pipe or a GLib journald stream that can be closed underneath
# the app. That is what made Electron apps (Discord) crash with
# "write EPIPE" when launched through `gio launch`.
#
# usage: launchapp.sh <desktop-file-path> [desktop-id]
# The CSM_DIRECT=1 environment marker marks the inner invocation (the one
# actually exec'ing the app), preventing an infinite systemd-run loop.

# --------------------------------------------------------------- lookup ---
DF="$1"
ID="$2"

if [ ! -f "$DF" ]; then
    for d in "$HOME/.local/share/applications" /usr/share/applications \
             /usr/local/share/applications \
             "$HOME/.local/share/flatpak/exports/share/applications" \
             /var/lib/flatpak/exports/share/applications; do
        [ -n "$ID" ] && [ -f "$d/$ID" ] && { DF="$d/$ID"; break; }
    done
fi
[ -f "$DF" ] || exit 1

EXE=$(grep -m1 '^Exec=' "$DF" | cut -d= -f2-)
[ -n "$EXE" ] || exit 1

# strip desktop file field codes (no files are being handed over) and un-escape %%
EXE=$(printf '%s' "$EXE" | sed 's/ %[fFuUdDnNickvm]//g; s/%%/%/g')
[ -n "$EXE" ] || exit 1

# -------------------------------------------------------------- terminal --
# Terminal=true apps run inside the user's terminal emulator, resolved from
# the same kdeglobals keys the native launcher uses.
term_from_service() {
    for d in "$HOME/.local/share/applications" /usr/share/applications \
             /usr/local/share/applications; do
        [ -f "$d/$1" ] || continue
        grep -m1 '^Exec=' "$d/$1" | cut -d= -f2- | \
            sed 's/ %[fFuUdDnNickvm]//g; s/%%/%/g'
        return 0
    done
    return 1
}

TERM_EXE=""
if grep -q '^Terminal=true' "$DF"; then
    TERM_EXE=$(term_from_service "$(kreadconfig6 --file kdeglobals --group General --key TerminalService 2>/dev/null)")
    [ -z "$TERM_EXE" ] && TERM_EXE=$(kreadconfig6 --file kdeglobals --group General --key TerminalApplication 2>/dev/null)
    if [ -n "$TERM_EXE" ]; then
        command -v "$(printf '%s' "$TERM_EXE" | cut -d' ' -f1)" >/dev/null 2>&1 || \
            TERM_EXE=$(term_from_service "$TERM_EXE")
    fi
    if [ -z "$TERM_EXE" ]; then
        for t in ghostty kitty alacritty foot xterm konsole; do
            command -v "$t" >/dev/null 2>&1 && { TERM_EXE="$t"; break; }
        done
    fi
fi

TARGS=""
if [ -n "$TERM_EXE" ]; then
    case "$TERM_EXE" in
        *wezterm*)        TARGS="start --" ;;
        *gnome-terminal*) TARGS="--" ;;
        *-e)              TARGS="" ;;    # configured value already ends with -e
        *)                TARGS="-e" ;;
    esac
fi

# -------------------------------------------------- inner: run the app ----
if [ "${CSM_DIRECT:-}" = "1" ]; then
    if [ -n "$TERM_EXE" ]; then
        exec $TERM_EXE $TARGS $EXE </dev/null >/dev/null 2>&1
    fi
    exec $EXE </dev/null >/dev/null 2>&1
fi

# ------------------------------------------------ layer 1: systemd unit ---
# KIO SystemdProcessRunner equivalent (kickoff's method on systemd >= 250).
NAME=$(grep -m1 '^Name=' "$DF" | cut -d= -f2-)
[ -n "$NAME" ] || NAME="Custom Start Menu"
IDBASE=$(printf '%s' "${ID:-$(basename "$DF")}" | sed 's/\.desktop$//; s/[^a-zA-Z0-9_.]/-/g')
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null) || UUID=$(date +%s%N)

if command -v systemd-run >/dev/null 2>&1 && [ -n "$XDG_RUNTIME_DIR" ]; then
    if systemd-run --user --collect \
            --unit="app-${IDBASE}@${UUID}.service" \
            -p Type=simple -p ExitType=cgroup -p Slice=app.slice \
            -p Description="$NAME" -p SourcePath="$DF" \
            --setenv=CSM_DIRECT=1 \
            "$0" "$DF" "$ID" >/dev/null 2>&1; then
        exit 0
    fi
fi

# --------------------------------------------- layer 2: detached fork -----
# KIO ForkingProcessRunner equivalent: double-fork into a new session so the
# caller (the widget's engine) returns immediately and owns no fds of the app.
(
    setsid env CSM_DIRECT=1 "$0" "$DF" "$ID" </dev/null >/dev/null 2>&1
) &
exit 0
