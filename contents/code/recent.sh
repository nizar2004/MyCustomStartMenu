#!/bin/sh
# Recently used apps for the Custom Start Menu widget.
#
#   recent.sh list        print stored desktop ids, most recent first
#   recent.sh add <id>    move <id> to the top (deduplicated, max 12)
#   recent.sh clear       forget the history
#
# Kept in the XDG state dir, one id per line.

DIR="${XDG_STATE_HOME:-$HOME/.local/state}/custom-start-menu"
FILE="$DIR/recent"

case "$1" in
    list)
        [ -f "$FILE" ] && head -n 12 "$FILE"
        ;;
    add)
        id="$2"
        [ -n "$id" ] || exit 0
        mkdir -p "$DIR" 2>/dev/null
        tmp="$FILE.tmp.$$"
        {
            printf '%s\n' "$id"
            [ -f "$FILE" ] && grep -vxF -- "$id" "$FILE"
        } | head -n 12 > "$tmp" && mv "$tmp" "$FILE"
        ;;
    clear)
        rm -f "$FILE"
        ;;
esac
