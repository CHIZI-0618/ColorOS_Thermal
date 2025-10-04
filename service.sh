#!/system/bin/sh
MODDIR="${0%/*}"

# ===================================
THERMAL_DIR="/data/adb/Thermal_ColorOs"
LOG_FILE="$THERMAL_DIR/Thermal_ColorOs.log"
BATT_PATH="/sys/class/power_supply/battery/status"
TEMP_NODE="/proc/shell-temp"
GAME_CONFIG="$THERMAL_DIR/game"
CPUFREQ_NODE="/proc/game_opt/disable_cpufreq_limit"
THERMAL_PROP="init.svc.thermal-engine"
SLEEP_INTERVAL=1

# ===================================
mkdir -p "$THERMAL_DIR" 2>/dev/null
[ -f "$LOG_FILE" ] || touch "$LOG_FILE"

[ -f "$GAME_CONFIG" ] || {
    touch "$GAME_CONFIG"
    echo "# 每行添加一个游戏包名" > "$GAME_CONFIG"
    echo "# 示例: com.tencent.tmgp.sgame" >> "$GAME_CONFIG"
}

[ -r "$BATT_PATH" ] && [ -w "$TEMP_NODE" ] || exit 1

# ===================================
last_status=""
game_active=0
current_game=""

# ===================================

check_game_foreground() {
    local current_app=$(dumpsys SurfaceFlinger 2>/dev/null | 
        awk '/^[0-9]+:.*ACTIVE/ {print $2}' | cut -d'/' -f1)
    
    [ -z "$current_app" ] && {
        current_app=$(dumpsys activity activities 2>/dev/null |
            grep -Em1 'mResumedActivity|mTopFullscreen' | grep -Eo 'com[^ /]+' | head -1)
    }
    
    [ -z "$current_app" ] && {
        current_app=$(dumpsys window windows 2>/dev/null |
            grep -Em1 'mCurrentFocus|mFocusedApp' | grep -Eo 'com[^ /]+' | head -1)
    }
    
    [ -z "$current_app" ] && return 0
    
    grep -q "^[^#]*$current_app" "$GAME_CONFIG" 2>/dev/null && {
        echo "$current_app"
        return 1
    }
    return 0
}

# ===================================
control_thermal() {
    local action="$1"
    [ "$(getprop $THERMAL_PROP)" = "running" ] && {
        [ "$action" = "stop" ] && setprop ctl.stop thermal-engine
    } || {
        [ "$action" = "start" ] && setprop ctl.start thermal-engine
    }
}

# ===================================
control_temp_node() {
    local v=0
    [ "$1" = "Charging" ] && v=40000
    
    echo "0 $v" > "$TEMP_NODE"
    echo "1 $v" >> "$TEMP_NODE"
    echo "2 $v" >> "$TEMP_NODE"
    echo "3 $v" >> "$TEMP_NODE"
    echo "4 $v" >> "$TEMP_NODE"
    echo "5 $v" >> "$TEMP_NODE"
    echo "6 $v" >> "$TEMP_NODE"
    echo "7 $v" >> "$TEMP_NODE" 2>/dev/null
}

# ===================================

enter_game_mode() {
    local game_pkg="$1"
    
    [ -w "$CPUFREQ_NODE" ] && echo 1 > "$CPUFREQ_NODE"
    control_temp_node "Charging"
    control_thermal "stop"
    
    game_active=1
    current_game="$game_pkg"
    echo "[$(date '+%m-%d %H:%M:%S')] 进入游戏: $game_pkg" >> "$LOG_FILE"
    echo "[$(date '+%m-%d %H:%M:%S')] 高性能游戏场景: 禁用温控，解除CPU频率限制" >> "$LOG_FILE"
}

# ===================================
exit_game_mode() {
    local batt_stat=$(tr -d '\n' < "$BATT_PATH" 2>/dev/null)
    
    [ -w "$CPUFREQ_NODE" ] && echo 0 > "$CPUFREQ_NODE"
    
    if [ "$batt_stat" = "Discharging" ]; then
        control_temp_node "Discharging"
        control_thermal "start"
    fi
    
    echo "[$(date '+%m-%d %H:%M:%S')] 退出游戏: $current_game" >> "$LOG_FILE"
    echo "[$(date '+%m-%d %H:%M:%S')] 退出高性能游戏场景: 全部恢复系统默认状态" >> "$LOG_FILE"
    game_active=0
    current_game=""
}

# ===================================

manage_thermal_state() {
    [ $game_active -eq 1 ] && return
    
    local current_stat=$(tr -d '\n' < "$BATT_PATH" 2>/dev/null)
    [ "$current_stat" = "$last_status" ] && return
    
    case "$current_stat" in
        "Charging")
            control_temp_node "Charging"
            control_thermal "stop"
            echo "[$(date '+%m-%d %H:%M:%S')] 充电中:强制快充模式" >> "$LOG_FILE"
            ;;
        "Discharging")
            control_temp_node "Discharging"
            control_thermal "start"
            echo "[$(date '+%m-%d %H:%M:%S')] 放电中:恢复默认温控配置" >> "$LOG_FILE"
            ;;
    esac
    
    last_status="$current_stat"
}

# ===================================
while :; do
    game_pkg=$(check_game_foreground)
    game_state=$?
    
    if [ $game_state -eq 1 ] && [ $game_active -eq 0 ]; then
        enter_game_mode "$game_pkg"
    elif [ $game_state -eq 0 ] && [ $game_active -eq 1 ]; then
        exit_game_mode
    fi
    
    manage_thermal_state
    
    sleep $SLEEP_INTERVAL || {
        [ $game_active -eq 1 ] && {
            [ -w "$CPUFREQ_NODE" ] && echo 0 > "$CPUFREQ_NODE"
            exit_game_mode
        }
        exit 0
    }
done