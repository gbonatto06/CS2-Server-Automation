#!/bin/bash
# Installs required apt packages, sets up steam user and creates the initial directory structure.

echo "Starting System Dependencies Setup"

# Update and Install Dependencies
# - lib32gcc/stdc++: Required for SteamCMD
# - dotnet-runtime-8.0: Required for CounterStrikeSharp
# - docker: Required for Database and Monitoring Stack
# - libpulse/audio libs: Prevents CS2 engine memory leaks/crashes due to missing audio drivers

echo "Updating repositories and installing packages"
sudo apt-get update
sudo apt-get install -y \
    lib32gcc-s1 lib32stdc++6 \
    curl tar unzip wget jq \
    dotnet-runtime-8.0 \
    docker.io docker-compose-v2 \
    awscli \
    python3-pip python3-venv \
    libpulse0 libpulse-dev libnss3 libnspr4 libtinfo6 libsdl2-2.0-0

# User Configuration
echo "Configuring 'steam' user"
if ! id "steam" &>/dev/null; then
    sudo useradd -m steam
    echo "User 'steam' created."
else
    echo "User 'steam' already exists"
fi

# Add steam user to docker group to allow running containers
sudo usermod -aG docker steam

# Directory Structure Setup
echo "Creating directory structure"

# Ensure base directories exist with correct permissions
sudo -u steam mkdir -p "$USER_HOME"
sudo -u steam mkdir -p "$CS2_DIR"
sudo -u steam mkdir -p "$CSGO_DIR/logs"
sudo -u steam mkdir -p "$CSS_DIR"

# Monitoring directories
sudo -u steam mkdir -p "$MON_DIR/prometheus" \
                       "$MON_DIR/promtail" \
                       "$MON_DIR/loki" \
                       "$MON_DIR/grafana"

# File Initialization
# Create an empty console.log to prevent Promtail from failing on startup
echo "Initializing log files"
sudo -u steam touch "$CSGO_DIR/console.log"

echo "System Dependencies Setup Complete"