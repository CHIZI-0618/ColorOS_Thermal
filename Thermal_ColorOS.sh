#!/system/bin/sh
# Thermal control daemon for ColorOS
# 仅监控充电与放电状态，自动控制 thermal-engine 与温度节点

THERMAL_DIR="/data/adb/Thermal_ColorOS"
LOG_FILE="$THERMAL_DIR/Thermal.log"
LOCK_FILE="$THERMAL_DIR/.lock"
BATT_PATH="/sys/class/power_supply/battery/status"
TEMP_NODE="/proc/shell-temp"
THERMAL_PROP="init.svc.thermal-engine"

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

handle_event() {
    local event="$1"
    local file="$2"

    exec 9>"$LOCK_FILE"
    flock -n 9 || exit 0

    trap 'flock -u 9; rm -f "$LOCK_FILE"' EXIT INT TERM HUP

    local status=$(tr -d '\n' < "$file" 2>/dev/null)

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

if [ "$1" = "w" ] || [ "$1" = "m" ]; then
    handle_event "$@"
    exit 0
fi

while [ ! -r "$BATT_PATH" ]; do
    sleep 2
done

echo "[$(date '+%m-%d %H:%M:%S')] 🔧 启动电池状态监控..." >> "$LOG_FILE"
handle_event "startup" "$BATT_PATH"

inotifyd "$0" "$BATT_PATH":w 2>>"$LOG_FILE"
