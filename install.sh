#!/usr/bin/env bash
#
# Installs the Custom Start Menu Plasma widget for the current user.
#
#   ./install.sh              install and restart plasmashell
#   ./install.sh --no-restart install without restarting the shell
#
set -euo pipefail

PLUGIN_ID="com.nizar.dashboard"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
DEST="$DATA_DIR/plasma/plasmoids/$PLUGIN_ID"
BACKUP_ROOT="$DATA_DIR/plasma/plasmoids-backup"
RESTART=1

usage() {
    sed -n '3,6p' "$0" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
    case "$arg" in
        --no-restart) RESTART=0 ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "install.sh: unknown option: $arg" >&2; exit 2 ;;
    esac
done

if [ ! -f "$SRC_DIR/metadata.json" ] || [ ! -d "$SRC_DIR/contents" ]; then
    echo "install.sh: no widget found in $SRC_DIR (metadata.json / contents missing)" >&2
    exit 1
fi

echo "Widget : $PLUGIN_ID"
echo "Source : $SRC_DIR"
echo "Target : $DEST"

if [ "$(realpath "$SRC_DIR")" = "$(realpath -m "$DEST")" ]; then
    echo "Already installed here — nothing to copy."
else
    if [ -e "$DEST" ]; then
        BACKUP="$BACKUP_ROOT/$PLUGIN_ID-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$BACKUP_ROOT"
        mv "$DEST" "$BACKUP"
        echo "Backed up the previous install to $BACKUP"
    fi

    mkdir -p "$DEST"
    cp -R "$SRC_DIR/contents" "$DEST/"
    cp "$SRC_DIR/metadata.json" "$DEST/"
    echo "Installed $(find "$DEST" -type f | wc -l) files."
fi

if [ "$RESTART" -eq 0 ]; then
    echo "Skipped the shell restart (--no-restart): restart plasmashell yourself to load it."
    exit 0
fi

if command -v systemctl >/dev/null 2>&1 \
        && systemctl --user is-active --quiet plasma-plasmashell.service 2>/dev/null; then
    echo "Restarting plasmashell..."
    systemctl --user restart plasma-plasmashell.service
    sleep 3
    if systemctl --user is-active --quiet plasma-plasmashell.service; then
        echo "Done — plasmashell is running with the new widget."
    else
        echo "Warning: plasma-plasmashell.service is not active after the restart." >&2
        exit 1
    fi
else
    echo "Note: plasma-plasmashell.service not found; restart your shell to load the widget."
fi
