#!/bin/bash
# Installs the modding framework and gameplay plugins.
# Handles Metamod:Source, CounterStrikeSharp, MatchZy,
# Retakes, WeaponPaints, and CustomCommands.

echo "Starting Plugin Installation"

# Local path for plugins
TEMPLATE_DIR="$INSTALL_SOURCE_DIR/templates/plugins"

# Validation of Required Variables
: "${CSGO_DIR:?Variable CSGO_DIR not set}"
: "${CSS_DIR:?Variable CSS_DIR not set}"
: "${DB_PASS:?Variable DB_PASS not set}"

# Helper Functions

# Function to fetch the browser_download_url from the latest GitHub release
# Usage: get_github_url "User/Repo" "JQ_Filter"
get_github_url() {
    local repo=$1
    local filter=$2
    local url
    
    url=$(curl -s "https://api.github.com/repos/$repo/releases/latest" | \
          jq -r ".assets[] | select($filter) | .browser_download_url" | head -n 1)
    
    if [[ -z "$url" || "$url" == "null" ]]; then
        echo "Error: Could not find release for $repo" >&2
        return 1
    fi
    echo "$url"
}

# Function to download and unzip a file
# Usage: install_zip "URL" "Destination_Dir" "Temp_Name"
install_zip() {
    local url=$1
    local dest=$2
    local temp_name=$3
    
    echo "Downloading $temp_name"
    sudo -u steam wget -q "$url" -O "/tmp/$temp_name"
    
    echo "Extracting to $dest"
    sudo -u steam unzip -o -q "/tmp/$temp_name" -d "$dest"
    rm "/tmp/$temp_name"
}

# Metamod:Source Installation

echo "Installing Metamod:Source"

LATEST_MM=$(curl -s https://mms.alliedmods.net/mmsdrop/2.0/mmsource-latest-linux)
sudo -u steam wget -q "https://mms.alliedmods.net/mmsdrop/2.0/$LATEST_MM" -O /tmp/metamod.tar.gz
sudo -u steam tar -xzf /tmp/metamod.tar.gz -C "$CSGO_DIR"
rm /tmp/metamod.tar.gz

# Configure gameinfo.gi to load Metamod
echo "Updating gameinfo.gi"
GAMEINFO="$CSGO_DIR/gameinfo.gi"
if ! grep -q "csgo/addons/metamod" "$GAMEINFO"; then
    sudo -u steam sed -i '/Game_LowViolence/a \            Game    csgo/addons/metamod' "$GAMEINFO"
fi

# CounterStrikeSharp Installation

echo "Installing CounterStrikeSharp"
CSS_FILTER='.name | contains("with-runtime") and contains("linux")'
CSS_URL=$(get_github_url "roflmuffin/CounterStrikeSharp" "$CSS_FILTER")

install_zip "$CSS_URL" "$CSGO_DIR" "css.zip"

# Disable "FollowCS2ServerGuidelines" to allow skins
echo "Configuring CSS core.json"
CORE_CONFIG="$CSS_DIR/configs/core.json"
EXAMPLE_CONFIG="$CSS_DIR/configs/core.example.json"

# Create config from example if it doesn't exist
if [ ! -f "$CORE_CONFIG" ] && [ -f "$EXAMPLE_CONFIG" ]; then
    sudo -u steam cp "$EXAMPLE_CONFIG" "$CORE_CONFIG"
fi

# Disable guidelines
sudo -u steam sed -i 's/"FollowCS2ServerGuidelines": true/"FollowCS2ServerGuidelines": false/g' "$CORE_CONFIG"

# Standard Plugins Installation

echo "Installing BaseLib, PlayerSettings, MenuManager Plugins"

# They follow a standard zip structure
PLUGINS=("AnyBaseLib" "PlayerSettings" "MenuManager")

for plugin in "${PLUGINS[@]}"; do
    FILTER=".name == \"$plugin.zip\""
    URL=$(get_github_url "NickFox007/${plugin}CS2" "$FILTER")
    install_zip "$URL" "$CSGO_DIR" "$plugin.zip"
done

# MatchZy Installation

echo "Installing MatchZy"
# Starts with MatchZy, ends with .zip, does NOT contain "with-cssharp"
MZ_FILTER='.name | startswith("MatchZy-") and endswith(".zip") and (contains("with-cssharp") | not)'
MZ_URL=$(get_github_url "shobhit-pathak/MatchZy" "$MZ_FILTER")

install_zip "$MZ_URL" "$CSGO_DIR" "matchzy.zip"

# Set everyone as admin for 4Fun convenience
echo "Configuring MatchZy"
sudo -u steam sed -i 's/matchzy_everyone_is_admin false/matchzy_everyone_is_admin true/' "$CSGO_DIR/cfg/MatchZy/config.cfg"

# WeaponPaints Installation
echo "Installing WeaponPaints"
# This plugin has a non-standard zip structure, so we extract to a temp folder first
WP_URL=$(get_github_url "Nereziel/cs2-WeaponPaints" '.name == "WeaponPaints.zip"')

sudo -u steam wget -q "$WP_URL" -O /tmp/weaponpaints.zip
sudo -u steam mkdir -p /tmp/wp_temp
sudo -u steam unzip -o -q /tmp/weaponpaints.zip -d /tmp/wp_temp

# Move files to correct locations
echo "Moving WeaponPaints files"
sudo -u steam cp -rf /tmp/wp_temp/WeaponPaints "$CSS_DIR/plugins/"
sudo -u steam cp -rf /tmp/wp_temp/gamedata/* "$CSS_DIR/gamedata/"
rm -rf /tmp/wp_temp /tmp/weaponpaints.zip

# Configure WeaponPaints
echo "Configuring WeaponPaints.json"
WP_CONFIG_DIR="$CSS_DIR/configs/plugins/WeaponPaints"
sudo -u steam mkdir -p "$WP_CONFIG_DIR"

# Copy template and inject Database Password
sudo -u steam cp "$TEMPLATE_DIR/WeaponPaints.json" "$WP_CONFIG_DIR/WeaponPaints.json"
sudo -u steam sed -i "s|DB_PASSWORD_PLACEHOLDER|$DB_PASS|g" "$WP_CONFIG_DIR/WeaponPaints.json"

# Retakes Installation

echo "Installing CS2-Retakes"
RET_FILTER='.name | startswith("RetakesPlugin-") and (contains("no-map-configs") | not)'
RET_URL=$(get_github_url "B3none/cs2-retakes" "$RET_FILTER")

install_zip "$RET_URL" "$CSGO_DIR" "retakes.zip"

# CustomCommands Installation
echo "Installing CustomCommands"
CC_URL=$(get_github_url "HerrMagiic/CSS-CreateCustomCommands" '.name == "CustomCommands.zip"')

# Extract to specific plugin folder
sudo -u steam mkdir -p "$CSS_DIR/plugins/CustomCommands"
install_zip "$CC_URL" "$CSS_DIR/plugins/CustomCommands/" "customcommands.zip"

# Configure Public Modes
echo "Configuring CustomCommands"
CC_CMD_DIR="$CSS_DIR/plugins/CustomCommands/Commands"
sudo -u steam mkdir -p "$CC_CMD_DIR"

sudo -u steam cp "$TEMPLATE_DIR/PublicModes.json" "$CC_CMD_DIR/PublicModes.json"

# Load Order
echo "Configuring Autoexec"
sudo -u steam cp "$TEMPLATE_DIR/autoexec.cfg" "$CSGO_DIR/cfg/autoexec.cfg"

# Ensure final permissions are correct for the steam user
echo "pplying final permissions to addons"
sudo chown -R steam:steam "$CSGO_DIR/addons"

echo "Plugin Installation Complete"