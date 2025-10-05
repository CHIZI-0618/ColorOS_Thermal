#!/system/bin/sh

THERMAL_DIR="${0%/*}"
TEMP_NODE="/proc/shell-temp"

# 1. 卸载所有挂载的伪温度节点
umount /sys/class/thermal/thermal_zone*/temp 2>/dev/null

# 2. 恢复 /proc/shell-temp 默认状态（写入 0）
if [ -w "$TEMP_NODE" ]; then
    for i in $(seq 0 7); do
        echo "$i 0" > "$TEMP_NODE" 2>/dev/null
    done
fi
