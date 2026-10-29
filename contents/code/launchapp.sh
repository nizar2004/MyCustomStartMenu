#!/bin/sh
# launchapp.sh — exec the Exec= line of a .desktop file.
# Used by the Custom Start Menu so apps are spawned by the user systemd
# manager instead of living inside plasmashell's process tree.
# usage: launchapp.sh <desktop-file-path> [desktop-id]

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

exec $EXE
