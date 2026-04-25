#!/bin/bash
# /root/truenas-monitor.sh — TrueNAS monitoring → Gotify
# Runs every 5 minutes via cron (managed by Ansible).
# State directory: /root/truenas-monitor-state/
#
# What is monitored:
#   Via TrueNAS native alerts (alert.list):
#     - Pool health (DEGRADED, FAULTED, REMOVED)
#     - SMART test failures
#     - ZFS scrub errors
#     - Periodic snapshot task failures
#     - Pool capacity warnings (~80% threshold)
#     - TLS certificate expiry
#     - Service failures (NFS, SMB, ...)
#   Custom checks (not in native alerts):
#     - Cloud Sync task failures (cloudsync.query)
#     - VM state: autostart VMs not RUNNING (vm.query)
#     - SMART UDMA_CRC error delta per disk
#     - Kernel ATA hard resets (journalctl -k)

GOTIFY_URL="https://notifications.cantone.net"
GOTIFY_TOKEN=""  # Injected by Ansible

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Minimum TrueNAS alert level to forward: INFO NOTICE WARNING CRITICAL
MIN_ALERT_LEVEL="WARNING"

# TrueNAS alert classes to suppress (space-separated).
# HasUpdate: low priority for homelab.
# To list all current classes: midclt call alert.list | python3 -c "import json,sys; [print(a['klass']) for a in json.load(sys.stdin)]"
IGNORED_ALERT_CLASSES="HasUpdate"

# ---------------------------------------------------------------------------

STATE_DIR="/root/truenas-monitor-state"
HOST="truenas"

mkdir -p "${STATE_DIR}/alerts" "${STATE_DIR}/cloudsync" "${STATE_DIR}/disk"

# ---------------------------------------------------------------------------

send_gotify() {
    local title="$1"
    local message="$2"
    local priority="${3:-5}"
    curl -sk -X POST "${GOTIFY_URL}/message" \
        -H "X-Gotify-Key: ${GOTIFY_TOKEN}" \
        -F "title=${title}" \
        -F "message=${message}" \
        -F "priority=${priority}" > /dev/null
}

# ---------------------------------------------------------------------------
# 1. TrueNAS native alerts
# ---------------------------------------------------------------------------
check_truenas_alerts() {
    local alerts_json
    alerts_json=$(midclt call alert.list 2>/dev/null) || return

    echo "$alerts_json" | python3 -c "
import json, sys, os

alerts = json.load(sys.stdin)
state_dir = '${STATE_DIR}/alerts'
ignored = set('${IGNORED_ALERT_CLASSES}'.split())
level_order = {'INFO': 0, 'NOTICE': 1, 'WARNING': 2, 'CRITICAL': 3}
min_level = level_order.get('${MIN_ALERT_LEVEL}', 2)

current_uuids = set()

for alert in alerts:
    uuid = alert.get('uuid', '')
    if not uuid or alert.get('dismissed', False):
        continue

    klass = alert.get('klass', '')
    level = alert.get('level', 'WARNING')
    text = (alert.get('formatted') or alert.get('text') or '').strip()

    current_uuids.add(uuid)

    if klass in ignored:
        continue
    if level_order.get(level, 0) < min_level:
        continue

    state_file = os.path.join(state_dir, uuid)
    if not os.path.exists(state_file):
        priority = 8 if level == 'CRITICAL' else (5 if level == 'WARNING' else 3)
        icon = '🔴' if level == 'CRITICAL' else ('🟡' if level == 'WARNING' else 'ℹ️')
        print(f'NOTIFY|{priority}|{icon} TrueNAS {level}: {klass}|{text[:300]}')
        open(state_file, 'w').write(uuid)

for fname in os.listdir(state_dir):
    if fname not in current_uuids:
        os.remove(os.path.join(state_dir, fname))
" | while IFS='|' read -r action priority title message; do
        [ "$action" = "NOTIFY" ] && send_gotify "$title" "$message" "$priority"
    done
}

# ---------------------------------------------------------------------------
# 2. Cloud Sync task failures
# ---------------------------------------------------------------------------
check_cloudsync() {
    local tasks_json
    tasks_json=$(midclt call cloudsync.query 2>/dev/null) || return

    echo "$tasks_json" | python3 -c "
import json, sys, os

tasks = json.load(sys.stdin)
state_dir = '${STATE_DIR}/cloudsync'

for task in tasks:
    if not task.get('enabled', False):
        continue

    task_id = str(task['id'])
    description = task.get('description', f'Task {task_id}')
    job = task.get('job') or {}
    state = job.get('state', '')
    job_id = str(job.get('id', ''))
    error = (job.get('error') or '').strip()

    state_file = os.path.join(state_dir, task_id)

    if state in ('FAILED', 'ERROR'):
        last_notified = open(state_file).read().strip() if os.path.exists(state_file) else ''
        if job_id != last_notified:
            msg = error[:200] if error else 'No error details available'
            print(f'NOTIFY|8|🔴 Cloud Sync Failed: {description}|{msg}')
            open(state_file, 'w').write(job_id)
    elif state == 'SUCCESS' and os.path.exists(state_file):
        os.remove(state_file)
" | while IFS='|' read -r action priority title message; do
        [ "$action" = "NOTIFY" ] && send_gotify "$title" "$message" "$priority"
    done
}

# ---------------------------------------------------------------------------
# 3. VM state
#    Alerts if any autostart VM is not RUNNING. Clears when VM is running again.
# ---------------------------------------------------------------------------
check_vm_state() {
    local vms_json
    vms_json=$(midclt call vm.query 2>/dev/null) || return

    echo "$vms_json" | python3 -c "
import json, sys, os

vms = json.load(sys.stdin)
state_dir = '${STATE_DIR}/vms'
os.makedirs(state_dir, exist_ok=True)

for vm in vms:
    if not vm.get('autostart', False):
        continue

    vm_id = str(vm['id'])
    name = vm.get('name', f'VM {vm_id}')
    state = (vm.get('status') or {}).get('state', '')

    state_file = os.path.join(state_dir, vm_id)

    if state != 'RUNNING':
        if not os.path.exists(state_file):
            print(f'NOTIFY|8|🔴 VM stopped: {name}|Expected state: RUNNING, current state: {state}')
            open(state_file, 'w').write(state)
    elif os.path.exists(state_file):
        os.remove(state_file)
" | while IFS='|' read -r action priority title message; do
        [ "$action" = "NOTIFY" ] && send_gotify "$title" "$message" "$priority"
    done
}

# ---------------------------------------------------------------------------
# 5. SMART UDMA_CRC Delta
# ---------------------------------------------------------------------------
check_smart_crc() {
    local alerts=""
    local baseline="${STATE_DIR}/disk/crc_baseline.txt"
    declare -A current

    for dev in /dev/sd?; do
        [ -b "$dev" ] || continue
        local serial crc
        serial=$(smartctl -i "$dev" 2>/dev/null | awk '/Serial Number/ {print $3}')
        crc=$(smartctl -A "$dev" 2>/dev/null | awk '/UDMA_CRC_Error_Count/ {print $10}')
        [ -n "$serial" ] && [ -n "$crc" ] && current["$serial"]="$crc"
    done

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

    printf '' > "$baseline"
    for serial in "${!current[@]}"; do
        echo "${serial}=${current[$serial]}" >> "$baseline"
    done

    [ -n "$alerts" ] && send_gotify "⚠️ UDMA_CRC errors on ${HOST}" "$(printf '%b' "$alerts")" 8
}

# ---------------------------------------------------------------------------
# 6. Kernel ATA hard resets
# ---------------------------------------------------------------------------
check_hard_resets() {
    local ts_file="${STATE_DIR}/disk/last_check_ts.txt"
    local since="1 hour ago"

    [ -f "$ts_file" ] && since=$(cat "$ts_file")

    local resets
    resets=$(journalctl -k --since "$since" 2>/dev/null \
        | grep -iE "hard resetting link|exception Emask|failed command|ata[0-9]+.*error" \
        | grep -v "^$")

    date '+%Y-%m-%d %H:%M:%S' > "$ts_file"

    if [ -n "$resets" ]; then
        local count
        count=$(echo "$resets" | wc -l)
        local msg="${count} ATA errors since last check:\n$(echo "$resets" | tail -5)"
        send_gotify "⚠️ ATA errors on ${HOST}" "$(printf '%b' "$msg")" 8
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [ -z "$GOTIFY_TOKEN" ]; then
    echo "GOTIFY_TOKEN not set" >&2
    exit 1
fi

check_truenas_alerts
check_cloudsync
check_vm_state
check_smart_crc
check_hard_resets
