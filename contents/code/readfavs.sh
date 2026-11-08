#!/bin/sh
# readfavs.sh — emit the user's favorites for the Custom Start Menu.
# Kept as a script (instead of a piped one-liner) because the widget's
# executable engine runs command strings without a shell.
#
# output format (parsed by DashState.parseFavs):
#   line 1: kickoff FavoritesURLs (comma-separated applications:*.desktop)
#   ---
#   following lines: taskbar launchers= entries (first 5, for first-run migration)

kreadconfig6 --file klauncherrc --group Favorites --key FavoritesURLs 2>/dev/null
printf -- '---\n'
grep -h '^launchers=' "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null | head -5
