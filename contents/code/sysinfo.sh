#!/bin/sh
# One-shot static system info; parsed by the Dashboard widget.
U=$(whoami 2>/dev/null)
echo "USER:$U"
echo "FULLNAME:$(getent passwd "$U" 2>/dev/null | cut -d: -f5 | cut -d, -f1)"
echo "HOST:$(cat /proc/sys/kernel/hostname 2>/dev/null)"
. /etc/os-release 2>/dev/null
echo "OS:$PRETTY_NAME"
echo "KERNEL:$(uname -r)"
echo "ARCH:$(uname -m)"
echo "CORES:$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo)"
echo "CPU:$(grep -m1 'model name' /proc/cpuinfo | sed 's/.*: //')"
echo "PLASMA:$(plasmashell --version 2>/dev/null | awk '{print $2}')"
[ -f "$HOME/.face" ] && echo "FACE:$HOME/.face"

# graphics adapters (name per line, multiple possible)
if command -v lspci >/dev/null 2>&1; then
    lspci -nn 2>/dev/null | grep -Ei 'vga|3d|display' | while IFS= read -r line; do
        gpu=${line#*]: }
        gpu=${gpu%% (rev*}
        gpu=${gpu% \[*}
        echo "GPU:$gpu"
    done
else
    for h in /sys/class/hwmon/hwmon*; do
        n=$(cat "$h/name" 2>/dev/null)
        case "$n" in
            amdgpu|radeon|nvidia|i915|xe|nouveau) echo "GPU:$n" ;;
        esac
    done | sort -u
fi
exit 0
