#!/usr/bin/env bash
set -euo pipefail

SOURCE="/data/media"
DEST="/mnt/ext-hdd/media-backup"
LOG_DIR="/root/rsync-migration-logs"

PARALLEL_JOBS=3

mkdir -p "$LOG_DIR"

echo
echo "===== RSYNC MIGRATION PLAN ====="
echo

mapfile -t DIRS < <(du -s "$SOURCE"/* | sort -rn | awk '{print $2}')

VALID_DIRS=()

for DIR in "${DIRS[@]}"; do

    NAME=$(basename "$DIR")
    SIZE=$(du -s "$DIR" | awk '{print $1}')

    if [[ "$SIZE" -eq 0 ]]; then
        echo "SKIP (leer): $DIR"
        continue
    fi

    SRC="$DIR/"
    DST="$DEST/$NAME/"

    SIZE_GB=$(awk "BEGIN {printf \"%.1f\", $SIZE/1024/1024}")

    echo "SIZE:        ${SIZE_GB} GB"
    echo "SOURCE:      $SRC"
    echo "DESTINATION: $DST"
    echo

    VALID_DIRS+=("$DIR")

done

echo
read -r -p "Sind diese Pfade korrekt? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "Abgebrochen."
    exit 1
fi

echo
echo "===== STARTE RSYNC JOBS (nohup) ====="
echo

for DIR in "${VALID_DIRS[@]}"; do

    NAME=$(basename "$DIR")

    SRC="$DIR/"
    DST="$DEST/$NAME/"
    LOGFILE="$LOG_DIR/$NAME.log"

    mkdir -p "$DST"

    echo "Starte rsync Job: $NAME"

    nohup rsync -a \
        --whole-file \
        --inplace \
        --info=progress2 \
        "$SRC" "$DST" \
        > "$LOGFILE" 2>&1 &

    sleep 1

done

echo
echo "Alle Jobs gestartet."
echo "Logs unter:"
echo "$LOG_DIR"
