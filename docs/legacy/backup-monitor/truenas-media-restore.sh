#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# TrueNAS Media Restore — ext. HDD → NFS Share
# Quelle:  /mnt/backup-restore/media-backup/media/
# Ziel:    /mnt/data/mediastack/mediastack-data/
#
# - TV wird zuerst gestartet (Priorität)
# - Pro Verzeichnis ein Job, läuft im Hintergrund
# - Auto-Restart bei Abbruch (max. MAX_RETRIES Versuche)
# - Gotify Notifications: Start, Fortschritt (alle 30min), Fehler, Fertig
# =============================================================================

SOURCE="/mnt/backup-restore/media-backup/media"
DEST="/mnt/data/mediastack/mediastack-data"
LOG_DIR="/root/rsync-restore-logs"

GOTIFY_URL="https://GOTIFY_HOST/message"
GOTIFY_TOKEN="GOTIFY_TOKEN"

TOTAL_GB=4500
MAX_RETRIES=10
RETRY_DELAY=30

mkdir -p "$LOG_DIR"

# =============================================================================
# Gotify Helper
# =============================================================================

send_gotify() {
    local TITLE="$1"
    local MESSAGE="$2"
    local PRIORITY="${3:-5}"

    curl -s -X POST "${GOTIFY_URL}?token=${GOTIFY_TOKEN}" \
        -F "title=${TITLE}" \
        -F "message=${MESSAGE}" \
        -F "priority=${PRIORITY}" >/dev/null || true
}

# =============================================================================
# Einzelner rsync Job mit Auto-Restart
# Wird als Hintergrundprozess pro Verzeichnis gestartet
# =============================================================================

run_rsync_with_retry() {
    local NAME="$1"
    local SRC="$2"
    local DST="$3"
    local LOGFILE="$LOG_DIR/$NAME.log"
    local ATTEMPT=0

    while [ "$ATTEMPT" -lt "$MAX_RETRIES" ]; do

        ATTEMPT=$((ATTEMPT + 1))

        if [ "$ATTEMPT" -gt 1 ]; then
            echo "[$(date '+%F %T')] [$NAME] Neustart Versuch $ATTEMPT/$MAX_RETRIES nach ${RETRY_DELAY}s..." >> "$LOGFILE"
            send_gotify "Restore: Neustart $NAME" \
"Versuch $ATTEMPT/$MAX_RETRIES

rsync wurde neu gestartet, macht weiter wo er aufgehört hat." 6
            sleep "$RETRY_DELAY"
        fi

        echo "[$(date '+%F %T')] [$NAME] Starte rsync (Versuch $ATTEMPT)..." >> "$LOGFILE"

        rsync -a \
            --whole-file \
            --inplace \
            --info=progress2 \
            --no-group \
            "$SRC" "$DST" \
            >> "$LOGFILE" 2>&1 && {
                echo "[$(date '+%F %T')] [$NAME] Fertig." >> "$LOGFILE"
                send_gotify "Restore: $NAME fertig" \
"$NAME wurde vollständig kopiert." 7
                return 0
            }

        EXIT_CODE=$?
        echo "[$(date '+%F %T')] [$NAME] rsync beendet mit Exit-Code $EXIT_CODE." >> "$LOGFILE"

    done

    echo "[$(date '+%F %T')] [$NAME] FEHLER: Max. Versuche ($MAX_RETRIES) erreicht." >> "$LOGFILE"
    send_gotify "Restore: $NAME FEHLGESCHLAGEN" \
"$NAME konnte nach $MAX_RETRIES Versuchen nicht abgeschlossen werden.

Manuelle Intervention nötig." 9
    return 1
}

# =============================================================================
# Monitor Loop — läuft im Hintergrund, sendet alle 30min Gotify Update
# =============================================================================

monitor_loop() {
    local TOTAL_MB=$((TOTAL_GB * 1024))
    local STATE_FILE="/tmp/restore_progress_state"
    local SPEED_FILE="/tmp/restore_last_speed"

    while pgrep -f "rsync.*mediastack" > /dev/null 2>&1; do

        sleep 1800  # 30 Minuten

        CURRENT_MB=$(du -s --block-size=1M "$DEST" 2>/dev/null | awk '{print $1}' || echo 0)
        CURRENT_GB=$(awk "BEGIN {printf \"%.1f\", $CURRENT_MB/1024}")
        PERCENT=$(awk "BEGIN {printf \"%.1f\", ($CURRENT_MB/$TOTAL_MB)*100}")
        NOW=$(date +%s)

        SPEED_GB_H="unbekannt"
        ETA_H="unbekannt"

        if [ -f "$STATE_FILE" ]; then
            read -r LAST_MB LAST_TIME < "$STATE_FILE"
            DIFF_MB=$((CURRENT_MB - LAST_MB))
            DIFF_T=$((NOW - LAST_TIME))

            if [ "$DIFF_T" -gt 0 ] && [ "$DIFF_MB" -gt 0 ]; then
                SPEED_MB_H=$(awk "BEGIN {printf \"%.0f\", ($DIFF_MB/$DIFF_T)*3600}")
                SPEED_GB_H=$(awk "BEGIN {printf \"%.2f\", $SPEED_MB_H/1024}")
                echo "$SPEED_MB_H" > "$SPEED_FILE"
                REMAINING_MB=$((TOTAL_MB - CURRENT_MB))
                ETA_H=$(awk "BEGIN {printf \"%.1f\", $REMAINING_MB/$SPEED_MB_H}")
            elif [ -f "$SPEED_FILE" ]; then
                SPEED_MB_H=$(cat "$SPEED_FILE")
                SPEED_GB_H=$(awk "BEGIN {printf \"%.2f\", $SPEED_MB_H/1024}")
                REMAINING_MB=$((TOTAL_MB - CURRENT_MB))
                ETA_H=$(awk "BEGIN {printf \"%.1f\", $REMAINING_MB/$SPEED_MB_H}")
            fi
        fi

        echo "$CURRENT_MB $NOW" > "$STATE_FILE"

        # Aktive Jobs auflisten
        ACTIVE=$(pgrep -a rsync 2>/dev/null | grep mediastack | awk '{print $NF}' | xargs -I{} basename {} | tr '\n' ', ' || echo "–")

        send_gotify "Restore Fortschritt" \
"Übertragen: ${CURRENT_GB} GB / ${TOTAL_GB} GB
Fortschritt: ${PERCENT}%
Geschwindigkeit: ${SPEED_GB_H} GB/h
ETA: ${ETA_H} h

Aktive Jobs: ${ACTIVE}" 4

    done

    # Alle rsync Jobs fertig
    FINAL_MB=$(du -s --block-size=1M "$DEST" 2>/dev/null | awk '{print $1}' || echo 0)
    FINAL_GB=$(awk "BEGIN {printf \"%.1f\", $FINAL_MB/1024}")

    send_gotify "Restore abgeschlossen" \
"Alle Verzeichnisse kopiert.

Kopiert: ${FINAL_GB} GB" 8
}

# =============================================================================
# Main
# =============================================================================

echo "===== TrueNAS Media Restore ====="
echo "Quelle: $SOURCE"
echo "Ziel:   $DEST"
echo

# Verzeichnisse ermitteln, nach Grösse sortiert (gross → klein)
mapfile -t ALL_DIRS < <(du -s "$SOURCE"/* 2>/dev/null | sort -rn | awk '{print $2}')

echo "Verzeichnisse:"
for DIR in "${ALL_DIRS[@]}"; do
    NAME=$(basename "$DIR")
    SIZE_GB=$(du -s "$DIR" | awk '{printf "%.1f", $1/1024/1024}')
    printf "  %-20s %s GB\n" "$NAME" "$SIZE_GB"
done
echo

read -r -p "Starten? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "Abgebrochen."
    exit 1
fi

send_gotify "Restore gestartet" \
"Media Restore von ext. HDD → TrueNAS gestartet.

Quelle: $SOURCE
Ziel:   $DEST
Gesamt: ~${TOTAL_GB} GB" 6

# TV zuerst starten (Priorität)
if [ -d "$SOURCE/tv" ]; then
    echo "Starte TV (Priorität)..."
    run_rsync_with_retry "tv" "$SOURCE/tv/" "$DEST/tv/" &
    sleep 2
fi

# Restliche Verzeichnisse starten
for DIR in "${ALL_DIRS[@]}"; do
    NAME=$(basename "$DIR")
    [ "$NAME" = "tv" ] && continue  # bereits gestartet

    SRC="$DIR/"
    DST="$DEST/$NAME/"

    echo "Starte $NAME..."
    run_rsync_with_retry "$NAME" "$SRC" "$DST" &
    sleep 1
done

echo
echo "Alle Jobs gestartet. Logs: $LOG_DIR"
echo

# Monitor im Hintergrund starten
monitor_loop &

# Auf alle Jobs warten
wait

echo "Restore abgeschlossen."
