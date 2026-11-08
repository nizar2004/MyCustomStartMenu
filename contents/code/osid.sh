#!/bin/sh
# Prints the running distro as:  <ID><TAB><PRETTY_NAME>
# e.g.  arch	Arch Linux   ·   cachyos	CachyOS   ·   ubuntu	Ubuntu 24.04.1 LTS
# Read straight from /etc/os-release, so it works everywhere and never
# needs to guess or search the device for icons — the widget bundles the
# matching logo and picks it by this id.
[ -r /etc/os-release ] || exit 0

ID=""
PRETTY=""
# shellcheck disable=SC1091
. /etc/os-release 2>/dev/null

# CachyOS and friends may only set ID_LIKE=arch — report the real ID first,
# falling back to the like-id so the widget can at least show a family logo.
[ -n "$ID" ] || ID="$ID_LIKE"
[ -n "$ID" ] || exit 0

printf '%s\t%s\n' "$ID" "$PRETTY_NAME"
