#!/bin/bash
# Configures Docker, Prometheus, Grafana, Loki, Promtail and the custom Python CS2 Exporter.


echo "Starting Observability Stack Setup"

# Validation of Required Variables
# The syntax :? checks if the variable is set and not null; otherwise, it exits with error.
: "${MON_DIR:?Variable MON_DIR not set}"
: "${SERVER_PASS:?Variable SERVER_PASS not set}"
: "${INSTALL_SOURCE_DIR:?Variable INSTALL_SOURCE_DIR not set}" # Path where scripts.zip was extracted

# Define local paths for templates
TEMPLATE_DIR="$INSTALL_SOURCE_DIR/templates/observability"
DASHBOARD_DIR="$INSTALL_SOURCE_DIR/dashboards"

# Function to copy files securely from root-owned source to steam-owned destination
install_file() {
    local source=$1
    local dest=$2
    
    echo "Installing $(basename "$dest")"
    
    if [ -f "$source" ]; then
        # bypasses read permission issues in /tmp
        cp "$source" "$dest"
        # Transfer ownership to steam
        chown steam:steam "$dest"
        # Ensure readability for Grafana user 472
        chmod 644 "$dest"
    else
        echo "Critical Error: Source file not found: $source"
        ls -la "$(dirname "$source")" # List dir to debug context
        exit 1
    fi
}


# Python Environment Setup
# Creates a virtual environment for the CS2 Exporter with Valve Python Library
echo "Setting up Python environment"
sudo -u steam python3 -m venv "$MON_DIR/venv"
sudo -u steam "$MON_DIR/venv/bin/pip" install python-valve prometheus_client

# Deploy Configuration Files
echo "Deploying configuration templates"

# Python Exporter Script
install_file "$TEMPLATE_DIR/cs2_exporter.py" "$MON_DIR/cs2_exporter.py"

# Docker Composition and Blackbox Config
install_file "$TEMPLATE_DIR/docker-compose.yml" "$MON_DIR/docker-compose.yaml"
install_file "$TEMPLATE_DIR/blackbox.yml" "$MON_DIR/blackbox.yaml"

# Prometheus
install_file "$TEMPLATE_DIR/prometheus.yml" "$MON_DIR/prometheus/prometheus.yaml"

# Alert Rules Configuration
# Copies the alert definitions to the Prometheus directory
install_file "$TEMPLATE_DIR/alert.rules.yaml" "$MON_DIR/prometheus/alert.rules.yaml"

# Loki
install_file "$TEMPLATE_DIR/loki-config.yml" "$MON_DIR/loki/loki-config.yaml"

# Promtail
install_file "$TEMPLATE_DIR/promtail-config.yml" "$MON_DIR/promtail/config.yaml"

# Grafana Datasources
# Ensures Grafana connects to Loki and Prometheus automatically
mkdir -p "$MON_DIR/grafana/provisioning/datasources"
chown -R steam:steam "$MON_DIR/grafana"
install_file "$TEMPLATE_DIR/grafana-datasources.yml" "$MON_DIR/grafana/provisioning/datasources/ds.yaml"

# Grafana Dashboard Providers
# Tells Grafana where to look for JSON dashboard files
mkdir -p "$MON_DIR/grafana/provisioning/dashboards/definitions"
chown -R steam:steam "$MON_DIR/grafana"
install_file "$TEMPLATE_DIR/grafana-dashboards-provider.yml" "$MON_DIR/grafana/provisioning/dashboards/provider.yaml"

# Deploy and Configure Dashboard JSON
echo "Configuring Grafana Dashboard"
TARGET_JSON="$MON_DIR/grafana/provisioning/dashboards/definitions/cs2_server.json"

# Copy the visual JSON definition
install_file "$DASHBOARD_DIR/cs2_server.json" "$TARGET_JSON"

# Fetch Public IP for the "Quick Connect" button in Grafana
PUBLIC_IP=$(curl -s https://ipv4.icanhazip.com | tr -d '\r\n')

# Inject Public IP and Server Password into the Dashboard HTML Panel
echo "Injecting runtime variables into Dashboard"
sudo -u steam sed -i "s|SERVER_IP_PLACE_PLACEHOLDER|$PUBLIC_IP|g" "$TARGET_JSON"
sudo -u steam sed -i "s|SERVER_PASSWORD_PLACEHOLDER|$SERVER_PASS|g" "$TARGET_JSON"

# Systemd Service for Exporter
# This runs the Python script in the background to fetch stats from the game server
echo "Configuring CS2 Exporter Service"
install_file "$TEMPLATE_DIR/cs2_exporter.service" "/etc/systemd/system/cs2-exporter.service"

sudo systemctl daemon-reload
sudo systemctl enable cs2-exporter
sudo systemctl start cs2-exporter

# Start Docker Stack
echo "Starting Docker Containers"

# Fix permissions before starting
# Ensure the 'steam' user and Docker containers can read/write to mapped volumes.
# Permissions are set to 777 to avoid mapping issues with container internal users.
sudo chmod -R 777 "$MON_DIR"

# Launch the stack
cd "$MON_DIR" && sudo docker compose up -d

# Health Check
# Blocks script execution until Prometheus is healthy to prevent race conditions
echo "Waiting for Monitoring Stack initialization..."
until curl -s --fail http://127.0.0.1:9090/-/healthy > /dev/null; do
    echo "Waiting for Prometheus"
    sleep 5
done

echo "Observability Stack Setup Complete"