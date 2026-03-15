#!/usr/bin/env bash
set -euo pipefail

GOTIFY_URL="https://GOTIFY_HOST/message"
TOKEN="GOTIFY_TOKEN"

BACKUP_DIR="/mnt/ext-hdd/media-backup"

TOTAL_GB=3500
TOTAL_MB=$((TOTAL_GB * 1024))

STATE_FILE="/tmp/backup_progress_state"
SPEED_FILE="/tmp/backup_last_speed"
HANG_FILE="/tmp/backup_hang_counter"

HANG_THRESHOLD=3

send_gotify() {
    local TITLE="$1"
    local MESSAGE="$2"
    local PRIORITY="${3:-5}"

    curl -s -X POST "$GOTIFY_URL?token=$TOKEN" \
        -F "title=$TITLE" \
        -F "message=$MESSAGE" \
        -F "priority=$PRIORITY" >/dev/null
}

error_handler() {
    local LINE="$1"
    local CMD="$2"

    send_gotify "Backup Fehler" \
"Script Fehler in Zeile $LINE

Befehl:
$CMD" 9
}

trap 'error_handler $LINENO "$BASH_COMMAND"' ERR

CURRENT_MB=$(du -s --block-size=1M "$BACKUP_DIR" | awk '{print $1}')
CURRENT_GB=$(awk "BEGIN {printf \"%.1f\", $CURRENT_MB/1024}")

NOW=$(date +%s)

SPEED_MB_H=0

if [ -f "$STATE_FILE" ]; then

    read LAST_MB LAST_TIME < "$STATE_FILE"

    SIZE_DIFF_MB=$((CURRENT_MB - LAST_MB))
    TIME_DIFF=$((NOW - LAST_TIME))

    if [ "$TIME_DIFF" -gt 0 ] && [ "$SIZE_DIFF_MB" -gt 0 ]; then
        SPEED_MB_H=$(awk "BEGIN {printf \"%.2f\", ($SIZE_DIFF_MB / $TIME_DIFF) * 3600}")
        echo "$SPEED_MB_H" > "$SPEED_FILE"
    elif [ -f "$SPEED_FILE" ]; then
        SPEED_MB_H=$(cat "$SPEED_FILE")
    fi

else

    LAST_MB=$CURRENT_MB

fi

echo "$CURRENT_MB $NOW" > "$STATE_FILE"

SPEED_GB_H=$(awk "BEGIN {printf \"%.2f\", $SPEED_MB_H/1024}")

PERCENT=$(awk "BEGIN {printf \"%.1f\", ($CURRENT_MB/$TOTAL_MB)*100}")

if awk "BEGIN {exit !($SPEED_MB_H > 0)}"; then
    REMAINING_MB=$((TOTAL_MB - CURRENT_MB))
    ETA_HOURS=$(awk "BEGIN {printf \"%.1f\", $REMAINING_MB / $SPEED_MB_H}")
else
    ETA_HOURS="unbekannt"
fi

if pgrep rsync > /dev/null; then

    if [ "$CURRENT_MB" -le "$LAST_MB" ]; then

        COUNT=0
        [ -f "$HANG_FILE" ] && COUNT=$(cat "$HANG_FILE")

        COUNT=$((COUNT + 1))
        echo "$COUNT" > "$HANG_FILE"

        if [ "$COUNT" -ge "$HANG_THRESHOLD" ]; then

            RSYNC_CMD=$(pgrep -a rsync | head -n 1)

            send_gotify "Backup hängt" \
"rsync läuft, aber keine Datenänderung erkannt.

Prozess:
$RSYNC_CMD

Stand:
${CURRENT_GB} GB / ${TOTAL_GB} GB" 9

        fi

    else

        echo "0" > "$HANG_FILE"

    fi

    MESSAGE="rsync aktiv

Übertragen: ${CURRENT_GB} GB / ${TOTAL_GB} GB
Fortschritt: ${PERCENT} %
Geschwindigkeit: ${SPEED_GB_H} GB/h
ETA: ${ETA_HOURS} h"

    send_gotify "Backup läuft" "$MESSAGE" 5

else

    if [ "$CURRENT_MB" -ge "$TOTAL_MB" ]; then

        send_gotify "Backup fertig" \
"Backup abgeschlossen

Übertragen: ${CURRENT_GB} GB" 8

    else

        send_gotify "Backup gestoppt" \
"rsync läuft nicht mehr.

Stand:
${CURRENT_GB} GB / ${TOTAL_GB} GB" 7

    fi

fi
