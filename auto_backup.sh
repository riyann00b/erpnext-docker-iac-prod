#!/bin/bash
cd "$(dirname "$0")" # Ensure we run in frappe_docker directory

HOST_BACKUP_DIR="./backups"
CONTAINER="erpnext-backend-1"
SITE="frontend"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
TARGET_DIR="$HOST_BACKUP_DIR/$TIMESTAMP"
LOG_FILE="./backup.log"

echo "[$TIMESTAMP] Starting backup..." >> $LOG_FILE
docker exec $CONTAINER bench --site $SITE backup --with-files >> $LOG_FILE 2>&1 || exit 1

mkdir -p "$TARGET_DIR"
docker cp $CONTAINER:/home/frappe/frappe-bench/sites/$SITE/private/backups/. "$TARGET_DIR/" >> $LOG_FILE 2>&1

# Retain only last 7 days of backups
find "$HOST_BACKUP_DIR" -maxdepth 1 -type d -mtime +7 -exec rm -rf {} + >> $LOG_FILE 2>&1
echo "[$TIMESTAMP] Done." >> $LOG_FILE
