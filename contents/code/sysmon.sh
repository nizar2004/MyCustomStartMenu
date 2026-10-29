#!/bin/sh
# Emits one tagged line per metric; parsed by the Dashboard widget.
# C: total:idle        raw CPU jiffies
# M: total:avail:swT:swF   memory in kB
# N: rx:tx             network bytes
# D: total:used        root filesystem kB
# U: seconds           uptime
# T: millidegrees      hottest thermal zone
# CT: millidegrees     CPU temperature
# GU: name:percent     GPU usage (per adapter)
# GT: name:millidegrees    GPU temperature (per adapter)
# B: percent           battery (-1 if none)

read -r _ u n s i w irq sq st gl gq < /proc/stat 2>/dev/null
echo "C:$((u+n+s+irq+sq+st+gl+gq)):$((i+w))"

awk -F':' '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}/^SwapTotal:/{s=$2}/^SwapFree:/{f=$2}END{printf "M:%d:%d:%d:%d\n",t,a,s,f}' /proc/meminfo

awk 'BEGIN{r=0;x=0}$1~/lo:$/{next}$1~/:$/{gsub(/:$/,"",$1);r+=$2;x+=$10}END{printf "N:%d:%d\n",r,x}' /proc/net/dev

df -kP / 2>/dev/null | awk 'NR==2{printf "D:%d:%d\n",$2,$3}'

awk '{printf "U:%d\n",$1}' /proc/uptime

t=0
for z in /sys/class/thermal/thermal_zone*; do
    [ -r "$z/temp" ] || continue
    v=$(cat "$z/temp" 2>/dev/null)
    if [ -n "$v" ] && [ "$v" -gt "$t" ] 2>/dev/null; then t=$v; fi
done
echo "T:$t"

# CPU temperature (k10temp / coretemp / zenpower preferred, else hottest zone)
ct=0
for h in /sys/class/hwmon/hwmon*; do
    n=$(cat "$h/name" 2>/dev/null)
    case "$n" in
        k10temp|coretemp|zenpower|cpu_thermal)
            for tf in "$h"/temp*_input; do
                [ -r "$tf" ] || continue
                v=$(cat "$tf" 2>/dev/null)
                if [ -n "$v" ] && [ "$v" -gt "$ct" ] 2>/dev/null; then ct=$v; fi
            done
            ;;
    esac
done
if [ -z "$ct" ] || [ "$ct" -eq 0 ] 2>/dev/null; then ct=$t; fi
echo "CT:$ct"

# per-GPU usage + temperature (sysfs)
for c in /sys/class/drm/card[0-9]*; do
    dev="$c/device"
    [ -d "$dev" ] || continue
    v=$(cat "$dev/vendor" 2>/dev/null)
    [ -n "$v" ] || continue
    case "$v" in
        0x10de) vn="NVIDIA" ;;
        0x1002) vn="AMD" ;;
        0x8086) vn="Intel" ;;
        *) vn="GPU" ;;
    esac
    busy=$(cat "$dev/gpu_busy_percent" 2>/dev/null)
    gt=0
    for h in /sys/class/hwmon/hwmon*; do
        hn=$(cat "$h/name" 2>/dev/null)
        case "$hn" in
            amdgpu|radeon|nvidia|nouveau|i915|xe)
                if [ "$(readlink -f "$h/device" 2>/dev/null)" = "$(readlink -f "$dev" 2>/dev/null)" ]; then
                    for tf in "$h"/temp*_input; do
                        [ -r "$tf" ] || continue
                        v=$(cat "$tf" 2>/dev/null)
                        if [ -n "$v" ] && [ "$v" -gt "$gt" ] 2>/dev/null; then gt=$v; fi
                    done
                fi
                ;;
        esac
    done
    echo "GU:$vn:$busy"
    echo "GT:$vn:$gt"
done

# NVIDIA usage via nvidia-smi (not exposed in sysfs)
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | while IFS=, read -r u tp; do
        u=$(echo "$u" | tr -d ' ')
        tp=$(echo "$tp" | tr -d ' ')
        echo "GU:NVIDIA:$u"
        echo "GT:NVIDIA:${tp}000"
    done
fi

b=-1
for p in /sys/class/power_supply/BAT*/capacity; do
    [ -r "$p" ] || continue
    v=$(cat "$p" 2>/dev/null)
    if [ -n "$v" ]; then b=$v; fi
done
echo "B:$b"
