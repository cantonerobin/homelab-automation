#!/bin/bash
# disk-monitor.sh — ZFS + SMART error monitoring with Gotify notifications
# Deployment: /usr/local/bin/disk-monitor.sh on truenas
# Cron: */15 * * * * (TrueNAS UI → System → Advanced → Cron Jobs)

GOTIFY_URL="https://notifications.cantone.net"
GOTIFY_TOKEN=""  # App token from Gotify UI → Apps → Create App
STATE_DIR="/root/disk-monitor-state"
HOST="truenas"

mkdir -p "$STATE_DIR"

# ---------------------------------------------------------------------------

send_gotify() {
    local title="$1"
    local message="$2"
    local priority="${3:-7}"
    curl -sk -X POST "${GOTIFY_URL}/message" \
        -H "X-Gotify-Key: ${GOTIFY_TOKEN}" \
        -F "title=${title}" \
        -F "message=${message}" \
        -F "priority=${priority}" > /dev/null
}

# ---------------------------------------------------------------------------
# 1. ZFS Pool Status — CKSUM/READ/WRITE errors + pool state
# ---------------------------------------------------------------------------
check_zpool() {
    local alerts=""

    for pool in data archive; do
        local status
        status=$(zpool status "$pool" 2>/dev/null) || continue

        # Pool state
        local state
        state=$(echo "$status" | awk '/^\s+state:/ {print $2}')
        if [ "$state" != "ONLINE" ]; then
            alerts+="Pool ${pool}: STATE=${state}\n"
        fi

        # Non-zero errors in the disk table
        local err_line
        err_line=$(echo "$status" | awk '
            /NAME/ {found=1; next}
            found && /[0-9]/ {
                if ($3+0 > 0 || $4+0 > 0 || $5+0 > 0)
                    print "  " $1 ": READ=" $3 " WRITE=" $4 " CKSUM=" $5
            }
        ')
        [ -n "$err_line" ] && alerts+="Pool ${pool} errors:\n${err_line}\n"

        # Scrub with errors — only alert on completed scrubs, not in-progress ones
        local scrub
        scrub=$(echo "$status" | grep "scan:" | grep -v "in progress" | grep -v "0 errors" | grep -v "none requested" | grep -v "canceled")
        [ -n "$scrub" ] && alerts+="Pool ${pool} scrub errors: ${scrub}\n"
    done

    [ -n "$alerts" ] && echo "$alerts"
}

# ---------------------------------------------------------------------------
# 2. SMART UDMA_CRC Delta — new CRC errors since last check
# ---------------------------------------------------------------------------
check_smart_crc() {
    local alerts=""
    local baseline="$STATE_DIR/crc_baseline.txt"
    declare -A current

    # Collect current values for all disks
    for dev in /dev/sd?; do
        [ -b "$dev" ] || continue
        local serial crc
        serial=$(smartctl -i "$dev" 2>/dev/null | awk '/Serial Number/ {print $3}')
        crc=$(smartctl -A "$dev" 2>/dev/null | awk '/UDMA_CRC_Error_Count/ {print $10}')
        [ -n "$serial" ] && [ -n "$crc" ] && current["$serial"]="$crc"
    done

    # Compare with baseline
    if [ -f "$baseline" ]; then
        while IFS='=' read -r serial old_crc; do
            [ -z "${current[$serial]+x}" ] && continue
            local new_crc="${current[$serial]}"
            if [ "$new_crc" -gt "$old_crc" ] 2>/dev/null; then
                local diff=$((new_crc - old_crc))
                alerts+="UDMA_CRC increased: ${serial}  +${diff} (${old_crc} → ${new_crc})\n"
            fi
        done < "$baseline"
    fi

    # Update baseline
    printf '' > "$baseline"
    for serial in "${!current[@]}"; do
        echo "${serial}=${current[$serial]}" >> "$baseline"
    done

    [ -n "$alerts" ] && echo "$alerts"
}

# ---------------------------------------------------------------------------
# 3. Kernel Hard Resets — new ATA errors since last check
# ---------------------------------------------------------------------------
check_hard_resets() {
    local alerts=""
    local ts_file="$STATE_DIR/last_check_ts.txt"
    local since="1 hour ago"

    [ -f "$ts_file" ] && since=$(cat "$ts_file")

    local resets
    resets=$(journalctl -k --since "$since" 2>/dev/null \
        | grep -iE "hard resetting link|exception Emask|failed command|ata[0-9]+.*error" \
        | grep -v "^$")

    if [ -n "$resets" ]; then
        local count
        count=$(echo "$resets" | wc -l)
        alerts+="${count} ATA errors since last check:\n"
        alerts+=$(echo "$resets" | tail -5)
        alerts+="\n"
    fi

    date '+%Y-%m-%d %H:%M:%S' > "$ts_file"
    [ -n "$alerts" ] && echo "$alerts"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [ -z "$GOTIFY_TOKEN" ]; then
    echo "GOTIFY_TOKEN not set" >&2
    exit 1
fi

alerts=""
alerts+=$(check_zpool)
alerts+=$(check_smart_crc)
alerts+=$(check_hard_resets)

if [ -n "$alerts" ]; then
    send_gotify "⚠️ Disk errors on ${HOST}" "$alerts" 8
fi
