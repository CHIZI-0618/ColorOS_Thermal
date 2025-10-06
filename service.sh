#!/system/bin/sh
# Thermal control daemon for ColorOS
# 仅监控充电与放电状态，自动控制 thermal-engine 与温度节点
# 使用轻量轮询方式，放弃 inotifyd，避免 sysfs 高频事件
# 增强：防止系统自动恢复温控或重置温度节点

THERMAL_DIR="${0%/*}"
LOG_FILE="$THERMAL_DIR/Thermal.log"
BATT_PATH="/sys/class/power_supply/battery/status"
TEMP_NODE="/proc/shell-temp"
THERMAL_PROP="init.svc.thermal-engine"
MODULE_PROP="$THERMAL_DIR/module.prop"
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
            echo "[$(date '+%m-%d %H:%M:%S')] ⚡ 充电中: 禁用温控" >> "$LOG_FILE"
            update_module_prop "⚡ 充电中: 禁用温控"
            ;;
        "Discharging")
            control_temp_node "Discharging"
            control_thermal "start"
            echo "[$(date '+%m-%d %H:%M:%S')] 🔋 放电中: 恢复温控" >> "$LOG_FILE"
            update_module_prop "🔋 放电中: 恢复温控"
            ;;
        *)
            echo "[$(date '+%m-%d %H:%M:%S')] ❓ 未识别状态: $status" >> "$LOG_FILE"
            update_module_prop "动态温控｜未知状态: ${status}"
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
