#!/bin/bash
# Sets up the MySQL container, restores data from S3, configures startup/backup scripts and registers the systemd service.

echo "Starting Database and Service Setup"

# Validation of Required Variables
: "${DB_PASS:?Variable DB_PASS not set}"
: "${S3_BUCKET:?Variable S3_BUCKET not set}"
: "${GSLT_TOKEN:?Variable GSLT_TOKEN not set}"
: "${SERVER_PASS:?Variable SERVER_PASS not set}"
: "${USER_HOME:?Variable USER_HOME not set}"
: "${INSTALL_SOURCE_DIR:?Variable INSTALL_SOURCE_DIR not set}"

TEMPLATE_DIR="$INSTALL_SOURCE_DIR/templates/database"

# MySQL Container Setup
echo "Starting MySQL Container"
sudo docker run -d \
  --name cs2-mysql \
  --restart always \
  -e MYSQL_ROOT_PASSWORD="$DB_PASS" \
  -e MYSQL_DATABASE=cs2_server \
  -e MYSQL_USER=cs2_admin \
  -e MYSQL_PASSWORD="$DB_PASS" \
  -p 3306:3306 \
  -v /home/steam/mysql_data:/var/lib/mysql \
  mysql:8.0

# Wait for Database Readiness
echo "Waiting for MySQL to accept connections"
until sudo docker exec cs2-mysql mysqladmin ping -h 127.0.0.1 -u"cs2_admin" -p"$DB_PASS" --silent; do
    echo "Waiting for Database"
    sleep 5
done

# Data Restoration
echo "Checking S3 for existing backups"
LATEST_BACKUP=$(aws s3 ls "s3://${S3_BUCKET}/" | grep ".sql" | sort | tail -n 1 | awk '{print $4}')

if [ -n "$LATEST_BACKUP" ]; then
    echo "Backup found: $LATEST_BACKUP. Restoring"
    
    # Download dump to tmp
    aws s3 cp "s3://${S3_BUCKET}/$LATEST_BACKUP" /tmp/restore_db.sql
    
    # Pipe dump into docker container
    docker exec -i cs2-mysql mysql -h 127.0.0.1 -u cs2_admin -p"$DB_PASS" cs2_server < /tmp/restore_db.sql
    
    echo "Restore complete"
else
    echo "No backup found in S3. Starting with a fresh database"
fi

# Deploy Lifecycle Scripts (Start & Backup)
echo "configuring lifecycle scripts"

# Deploy start_server.sh
sudo cp "$TEMPLATE_DIR/start_server.sh" "$USER_HOME/start_server.sh"
sudo sed -i "s|GSLT_TOKEN_PLACEHOLDER|$GSLT_TOKEN|g" "$USER_HOME/start_server.sh"
sudo sed -i "s|SERVER_PASSWORD_PLACEHOLDER|$SERVER_PASS|g" "$USER_HOME/start_server.sh"

# Deploy backup_db.sh
sudo cp "$TEMPLATE_DIR/backup_db.sh" "$USER_HOME/backup_db.sh"
sudo sed -i "s|S3_BUCKET_PLACEHOLDER|$S3_BUCKET|g" "$USER_HOME/backup_db.sh"
sudo sed -i "s|DB_PASSWORD_PLACEHOLDER|$DB_PASS|g" "$USER_HOME/backup_db.sh"

# Set permissions
sudo chmod +x "$USER_HOME/start_server.sh" "$USER_HOME/backup_db.sh"
sudo chown steam:steam "$USER_HOME/start_server.sh" "$USER_HOME/backup_db.sh"

# Ensure logs directory exists for the start script
sudo -u steam mkdir -p "$CSGO_DIR/logs"

# Systemd Service Registration
echo "Registering CS2 Systemd Service"
sudo cp "$TEMPLATE_DIR/cs2.service" /etc/systemd/system/

# Enable and Start
sudo systemctl daemon-reload
sudo systemctl enable cs2
sudo systemctl start cs2

echo "Database and Service Setup Complete"
echo "Setup Complete"