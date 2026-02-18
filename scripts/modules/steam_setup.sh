#!/bin/bash
# Downloads SteamCMD, installs Counter-Strike 2 (AppID 730), sets up required symlinks and adjusts permissions.

echo "Starting SteamCMD and CS2 Setup"

# Validation of Required Variables
: "${USER_HOME:?Variable USER_HOME not set}"
: "${CS2_DIR:?Variable CS2_DIR not set}"
: "${CSGO_DIR:?Variable CSGO_DIR not set}"

# Download and Install SteamCMD
echo "Downloading CS2 via SteamCMD"
sudo -u steam mkdir -p "$USER_HOME/steamcmd"
cd "$USER_HOME/steamcmd"

# Download steamcmd and extract directly
sudo -u steam curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | sudo -u steam tar zxvf -

# Install Counter-Strike 2
# +force_install_dir: Sets the installation folder
# +login anonymous: CS2 server does not require a real steam account to download
# +app_update 730: Downloads the game
# +validate: Verifies file integrity
echo "Running SteamCMD update"
sudo -u steam ./steamcmd.sh +force_install_dir "$CS2_DIR" +login anonymous +app_update 730 validate +quit

# Configure Shared Libraries (Symlinks)
echo "Creating symbolic link for steamclient.so"
# Linux servers often look for steamclient.so in ~/.steam/sdk64, but SteamCMD installs it in the steamcmd folder.
sudo -u steam mkdir -p "/home/steam/.steam/sdk64"
sudo -u steam ln -sf "/home/steam/steamcmd/linux64/steamclient.so" "/home/steam/.steam/sdk64/steamclient.so"

# Permission Adjustment
echo "Adjusting Recursive Permissions"
# Ensure the steam user owns everything in the home directory
sudo chown -R steam:steam "$USER_HOME/"

# Ensure the game directory allows execution and reading of logs
# Specifically fixing console.log permissions which might be locked by root during cloud-init
sudo chmod -R 755 "$CSGO_DIR"

# Verification
echo "Waiting for gameinfo.gi creation by SteamCMD"
# This loop ensures the script doesn't proceed until the core game files are actually present
until [ -f "$CSGO_DIR/gameinfo.gi" ]; do
    echo "Waiting for base game files"
    sleep 10
done

echo "SteamCMD and CS2 Setup Complete"