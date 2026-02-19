#!/bin/bash
# Dumps the MySQL database and uploads it to S3
# Triggered automatically by Systemd on service stop

BACKUP_NAME="cs2_server_dump.sql"
LOCAL_PATH="/home/steam/$BACKUP_NAME"
S3_PATH="s3://S3_BUCKET_PLACEHOLDER/$BACKUP_NAME"
DB_PASS="DB_PASSWORD_PLACEHOLDER"

echo "Creating database dump"
docker exec cs2-mysql mysqldump --no-tablespaces -h 127.0.0.1 -u cs2_admin -p"$DB_PASS" cs2_server > "$LOCAL_PATH"

echo "Uploading to S3"
aws s3 cp "$LOCAL_PATH" "$S3_PATH"