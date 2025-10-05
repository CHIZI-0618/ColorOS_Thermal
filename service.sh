#!/system/bin/sh
# Thermal control daemon for ColorOS
# 仅监控充电与放电状态，自动控制 thermal-engine 与温度节点
# 使用轻量轮询方式，放弃 inotifyd，避免 sysfs 高频事件
# 增强：防止系统自动恢复温控或重置温度节点

THERMAL_DIR="${0%/*}"
LOG_FILE="$THERMAL_DIR/Thermal.log"
LOCK_FILE="$THERMAL_DIR/.lock"
BATT_PATH="/sys/class/power_supply/battery/status"
TEMP_NODE="/proc/shell-temp"
THERMAL_PROP="init.svc.thermal-engine"
MODULE_PROP="$THERMAL_DIR/module.prop"
FAKE_TEMP_DIR="$THERMAL_DIR/thermal_fake_temp"
INTERVAL=2

mkdir -p "$THERMAL_DIR" "$FAKE_TEMP_DIR" 2>/dev/null
[ -f "$LOG_FILE" ] || touch "$LOG_FILE"

# 初始化伪温度文件（38°C）
for zone in /sys/class/thermal/thermal_zone*; do
    [ -e "$zone/temp" ] || continue
    fake_temp="$FAKE_TEMP_DIR/${zone##*/}_temp"
    [ -f "$fake_temp" ] || echo "38000" > "$fake_temp"
done

control_thermal() {
    local action="$1"
    [ "$(getprop $THERMAL_PROP)" = "running" ] && {
        [ "$action" = "stop" ] && setprop ctl.stop thermal-engine
    } || {
        [ "$action" = "start" ] && setprop ctl.start thermal-engine
    }
}

control_temp_node() {
    local v=0
    [ "$1" = "Charging" ] && v=38000
    for i in $(seq 0 7); do
        echo "$i $v" > "$TEMP_NODE" 2>/dev/null
    done
}

manage_temp_mounts() {
    local action="$1"
    case "$action" in
        "mount")
            for zone in /sys/class/thermal/thermal_zone*; do
                [ -e "$zone/temp" ] || continue
                fake_temp="$FAKE_TEMP_DIR/${zone##*/}_temp"
                mount -o bind "$fake_temp" "$zone/temp" 2>/dev/null
            done
            ;;
        "umount")
            umount /sys/class/thermal/thermal_zone*/temp 2>/dev/null
            ;;
    esac
}

update_module_prop() {
    local desc="$1"
    [ -f "$MODULE_PROP" ] && sed -i "s|^description=.*|description=${desc}|" "$MODULE_PROP"
}

handle_status_change() {
    local status="$1"

    case "$status" in
        "Charging")
            control_temp_node "Charging"
            control_thermal "stop"
            manage_temp_mounts "mount"
            echo "[$(date '+%m-%d %H:%M:%S')] ⚡ 充电中: 禁用温控 + 伪装38°C" >> "$LOG_FILE"
            update_module_prop "⚡ 充电中: 禁用温控 + 伪装38°C"
            ;;
        "Discharging"|"Full")
            control_temp_node "Discharging"
            control_thermal "start"
            manage_temp_mounts "umount"
            echo "[$(date '+%m-%d %H:%M:%S')] 🔋 放电中: 恢复温控 + 实时温度" >> "$LOG_FILE"
            update_module_prop "🔋 放电中: 恢复温控 + 实时温度"
            ;;
    esac
}

while [ ! -r "$BATT_PATH" ]; do
    sleep 2
done

echo "[$(date '+%m-%d %H:%M:%S')] 🔧 启动电池状态监控..." >> "$LOG_FILE"

last_status="Discharging"
while true; do
    current_status=$(tr -d '\n' < "$BATT_PATH" 2>/dev/null)

    # 若系统尝试恢复温控服务，则强制关闭
    if [ "$current_status" = "Charging" ] && [ "$(getprop $THERMAL_PROP)" = "running" ]; then
        setprop ctl.stop thermal-engine
    fi

    # 周期性强制写入温度节点防止系统覆盖
    [ "$current_status" = "Charging" ] && control_temp_node "Charging"

    if [ "$current_status" != "$last_status" ] && [ -n "$current_status" ]; then
        handle_status_change "$current_status"
        last_status="$current_status"
    fi

    sleep "$INTERVAL"
done
