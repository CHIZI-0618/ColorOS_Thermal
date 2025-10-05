#!/system/bin/sh
# Thermal control daemon for ColorOS
# 仅监控充电与放电状态，自动控制 thermal-engine 与温度节点
# 使用轻量轮询方式，放弃 inotifyd，避免 sysfs 高频事件

THERMAL_DIR="/data/adb/Thermal_ColorOS"
LOG_FILE="$THERMAL_DIR/Thermal.log"
LOCK_FILE="$THERMAL_DIR/.lock"
BATT_PATH="/sys/class/power_supply/battery/status"
TEMP_NODE="/proc/shell-temp"
THERMAL_PROP="init.svc.thermal-engine"
INTERVAL=5

mkdir -p "$THERMAL_DIR" 2>/dev/null
[ -f "$LOG_FILE" ] || touch "$LOG_FILE"

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
    [ "$1" = "Charging" ] && v=40000
    for i in $(seq 0 7); do
        echo "$i $v" > "$TEMP_NODE" 2>/dev/null
    done
}

handle_status_change() {
    local status="$1"

    exec 9>"$LOCK_FILE"
    flock -n 9 || exit 0
    trap 'flock -u 9; rm -f "$LOCK_FILE"' EXIT INT TERM HUP

    case "$status" in
        "Charging")
            control_temp_node "Charging"
            control_thermal "stop"
            echo "[$(date '+%m-%d %H:%M:%S')] ⚡ 充电中: 禁用温控, 启用快充模式" >> "$LOG_FILE"
            ;;
        "Discharging")
            control_temp_node "Discharging"
            control_thermal "start"
            echo "[$(date '+%m-%d %H:%M:%S')] 🔋 放电中: 恢复默认温控" >> "$LOG_FILE"
            ;;
        *)
            echo "[$(date '+%m-%d %H:%M:%S')] ❓ 未识别状态: $status" >> "$LOG_FILE"
            ;;
    esac
}

while [ ! -r "$BATT_PATH" ]; do
    sleep 2
done

echo "[$(date '+%m-%d %H:%M:%S')] 🔧 启动电池状态监控..." >> "$LOG_FILE"

last_status=""
while true; do
    current_status=$(tr -d '\n' < "$BATT_PATH" 2>/dev/null)

    if [ "$current_status" != "$last_status" ] && [ -n "$current_status" ]; then
        handle_status_change "$current_status"
        last_status="$current_status"
    fi

    sleep "$INTERVAL"
done
