#!/usr/bin/env bash
#
# Installs the Custom Start Menu Plasma widget for the current user.
#
# One-line install on a fresh machine:
#
#   curl -fsSL https://raw.githubusercontent.com/nizar2004/MyCustomStartMenu/main/install.sh | bash
#
# From a local clone:
#
#   ./install.sh              install and restart plasmashell
#   ./install.sh --no-restart install without restarting the shell
#
set -euo pipefail

PLUGIN_ID="com.nizar.dashboard"
REPO_URL="https://github.com/nizar2004/MyCustomStartMenu"
TARBALL_URL="$REPO_URL/archive/refs/heads/main.tar.gz"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
DEST="$DATA_DIR/plasma/plasmoids/$PLUGIN_ID"
BACKUP_ROOT="$DATA_DIR/plasma/plasmoids-backup"
RESTART=1

usage() {
    cat <<EOF
Installs the Custom Start Menu Plasma widget for the current user.

  curl -fsSL ${REPO_URL#https://}/...      (see README)  install from GitHub
  ./install.sh              install and restart plasmashell
  ./install.sh --no-restart install without restarting the shell

Phone mirroring (scrcpy + adb) is installed automatically when missing; the
script asks for your sudo password up front for those system packages, then
installs the widget itself per-user (no root).
EOF
}

for arg in "$@"; do
    case "$arg" in
        --no-restart) RESTART=0 ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "install.sh: unknown option: $arg" >&2; exit 2 ;;
    esac
done

# --- optional dependencies: phone mirroring (scrcpy over Wi-Fi) ----------------
# scrcpy mirrors the phone on the desktop; adb + udev rules let it talk to the
# device. These are system packages, so the sudo password is asked for once,
# up front — and only when something is actually missing. Everything here is
# best-effort: if it fails, the widget still installs (mirroring just stays
# unavailable until the packages are present).
install_phone_deps() {
    local missing=()
    command -v adb    >/dev/null 2>&1 || missing+=(adb)
    command -v scrcpy >/dev/null 2>&1 || missing+=(scrcpy)

    if [ "${#missing[@]}" -eq 0 ]; then
        return 0
    fi

    echo
    echo "Phone mirroring needs: ${missing[*]} (plus Android udev rules)."
    echo "Installing them requires sudo — you may be asked for your password now."
    if ! sudo -v; then
        echo "install.sh: sudo was not granted — skipping ${missing[*]}." >&2
        echo "            The widget installs fine; 'mirror phone' stays disabled." >&2
        return 0
    fi

    local rc=0
    if command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm scrcpy android-tools android-udev || rc=1
    elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq || true
        sudo apt-get install -y scrcpy adb android-sdk-platform-tools-common || rc=1
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y scrcpy android-tools || rc=1
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper --non-interactive install scrcpy android-tools || rc=1
    else
        echo "install.sh: no known package manager — install 'scrcpy' and 'adb' yourself." >&2
        rc=1
    fi

    if [ "$rc" -ne 0 ]; then
        echo "install.sh: could not install the phone packages; continuing anyway." >&2
    fi
    return 0
}

install_phone_deps

# --- locate the widget sources ------------------------------------------------
# Local run: the script sits next to metadata.json + contents.
# Piped run (curl | bash): download a copy of the repo first.
SRC_DIR=""
SELF="${BASH_SOURCE[0]:-}"
if [ -n "$SELF" ] && [ -f "$SELF" ]; then
    SELF_DIR="$(cd "$(dirname "$SELF")" && pwd)"
    if [ -f "$SELF_DIR/metadata.json" ] && [ -d "$SELF_DIR/contents" ]; then
        SRC_DIR="$SELF_DIR"
    fi
fi

WORKDIR=""
cleanup() {
    if [ -n "$WORKDIR" ] && [ -d "$WORKDIR" ]; then
        rm -rf "$WORKDIR"
    fi
}
trap cleanup EXIT

if [ -z "$SRC_DIR" ]; then
    echo "No local copy found — downloading $REPO_URL ..."
    WORKDIR="$(mktemp -d)"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$TARBALL_URL" -o "$WORKDIR/repo.tar.gz"
        tar -xzf "$WORKDIR/repo.tar.gz" -C "$WORKDIR"
        SRC_DIR="$WORKDIR/MyCustomStartMenu-main"
    elif command -v git >/dev/null 2>&1; then
        git clone -q --depth 1 "$REPO_URL" "$WORKDIR/repo"
        SRC_DIR="$WORKDIR/repo"
    else
        echo "install.sh: need curl or git to download the widget." >&2
        echo "  Install one (sudo pacman -S curl) or clone $REPO_URL yourself," >&2
        echo "  then run ./install.sh from inside it." >&2
        exit 1
    fi
fi

if [ ! -f "$SRC_DIR/metadata.json" ] || [ ! -d "$SRC_DIR/contents" ]; then
    echo "install.sh: no widget found in $SRC_DIR (metadata.json / contents missing)" >&2
    exit 1
fi

echo "Widget : $PLUGIN_ID"
echo "Source : $SRC_DIR"
echo "Target : $DEST"

# --- install ------------------------------------------------------------------
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

# --- reload the shell ---------------------------------------------------------
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
        echo "Add it to your panel: right-click the panel → Add Widgets → Custom Start Menu."
    else
        echo "Warning: plasma-plasmashell.service is not active after the restart." >&2
        exit 1
    fi
else
    echo "Note: plasma-plasmashell.service not found; restart your shell to load the widget."
fi
