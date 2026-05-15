#!/bin/bash
# Installs the modding framework and gameplay plugins.
# Handles Metamod:Source, CounterStrikeSharp, MatchZy,
# Retakes, WeaponPaints, and CustomCommands.

set -euo pipefail
echo "Starting Plugin Installation"



# Validation of Required Variables
: "${INSTALL_SOURCE_DIR:?Variable INSTALL_SOURCE_DIR not set}"
: "${CSGO_DIR:?Variable CSGO_DIR not set}"
: "${CSS_DIR:?Variable CSS_DIR not set}"
: "${DB_PASS:?Variable DB_PASS not set}"

# Local path for plugins
TEMPLATE_DIR="$INSTALL_SOURCE_DIR/templates/plugins"

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
# IMPORTANT: We query /releases (NOT /releases/latest) and filter by
# tag_name starting with "2.0". This is because:
#   - All 2.0.x builds are flagged as "pre-release" on GitHub.
#   - The "Latest" release is the 1.12.x stable, which only supports
#     Source 1 games (CSGO, TF2, etc) and does NOT work with CS2.
#   - /releases/latest excludes pre-releases, so it would return 1.12.x.
# The alliedmods.net "mmsource-latest-linux" pointer is also unreliable
# (it returned 1390 while GitHub already had 1401), so it's a fallback only.

install_metamod() {
    echo ""
    echo "[Metamod] Installing Metamod:Source 2.0 (dev branch)"

    local url filename build

    echo "[Metamod] Resolving latest 2.0.x build from GitHub Releases..."
    url=$(curl -fsSL "https://api.github.com/repos/alliedmodders/metamod-source/releases" | \
          jq -r '[.[] | select(.tag_name | startswith("2.0"))][0].assets[] |
                 select(.name | contains("linux") and endswith(".tar.gz")) |
                 .browser_download_url' | head -n 1)

    if [[ -z "$url" || "$url" == "null" ]]; then
        echo "[Metamod] GitHub API failed, falling back to alliedmods endpoint"
        filename=$(curl -fsSL "https://mms.alliedmods.net/mmsdrop/2.0/mmsource-latest-linux" 2>/dev/null || true)
        if [[ -n "$filename" && "$filename" == *.tar.gz ]]; then
            url="https://mms.alliedmods.net/mmsdrop/2.0/${filename}"
        fi
    fi

    if [[ -z "$url" || "$url" == "null" ]]; then
        echo "[Metamod] ERROR: Could not resolve download URL from any source" >&2
        return 1
    fi

    # Extract build number for logging and version guard
    build=$(echo "$url" | grep -oP 'git\K\d+' || echo "unknown")
    echo "[Metamod] Resolved build: $build"
    echo "[Metamod] URL: $url"

    # Refuse old builds with known path resolution bug on CS2
    if [[ "$build" =~ ^[0-9]+$ ]] && (( build < 1401 )); then
        echo "[Metamod] ERROR: Build $build has known path resolution bug on CS2." >&2
        echo "[Metamod]        Need >= 1401. Aborting." >&2
        return 1
    fi

    sudo -u steam wget -q "$url" -O /tmp/metamod.tar.gz
    sudo -u steam tar -xzf /tmp/metamod.tar.gz -C "$CSGO_DIR"
    rm /tmp/metamod.tar.gz

    # Validate post-extract
    local mm_so="$CSGO_DIR/addons/metamod/bin/linuxsteamrt64/libserver.so"
    if [[ ! -f "$mm_so" ]]; then
        echo "[Metamod] ERROR: libserver.so missing at $mm_so" >&2
        return 1
    fi

    # Inject gameinfo.gi entry (idempotent)
    local gameinfo="$CSGO_DIR/gameinfo.gi"
    if ! grep -q "csgo/addons/metamod" "$gameinfo"; then
        echo "[Metamod] Injecting entry into gameinfo.gi"
        sudo -u steam sed -i '/Game_LowViolence/a \            Game    csgo/addons/metamod' "$gameinfo"
        if ! grep -q "csgo/addons/metamod" "$gameinfo"; then
            echo "[Metamod] ERROR: Failed to inject entry into gameinfo.gi" >&2
            return 1
        fi
    else
        echo "[Metamod] gameinfo.gi already contains entry, skipping"
    fi

    echo "[Metamod] Installed build $build successfully"
}


# CounterStrikeSharp Installation
install_counterstrikesharp() {
    echo ""
    echo "[CSSharp] Installing CounterStrikeSharp (with-runtime)"

    # CSSharp publishes regular releases (not pre-releases), so /releases/latest works
    local filter='.name | contains("with-runtime") and contains("linux")'
    local url
    url=$(get_github_url "roflmuffin/CounterStrikeSharp" "$filter") || return 1

    echo "[CSSharp] Resolved URL: $url"
    install_zip "$url" "$CSGO_DIR" "css.zip"

    # Validate post-extract
    local css_so="$CSS_DIR/bin/linuxsteamrt64/counterstrikesharp.so"
    if [[ ! -f "$css_so" ]]; then
        echo "[CSSharp] ERROR: counterstrikesharp.so missing at $css_so" >&2
        return 1
    fi

    # clear executable stack flag
    # Ubuntu 24+ kernel blocks dlopen of .so files with RWE stack flag.
    # Without this, the cs2 process segfaults when Metamod tries to load CSSharp.
    # Applies recursively because the bundled .NET runtime also has tainted .so files.
    echo "[CSSharp] Clearing executable stack flag on .so files"
    if ! command -v execstack &>/dev/null; then
        apt-get install -y execstack
    fi
    find "$CSS_DIR" -name "*.so" \
        -exec execstack -c {} \; 2>&1 | grep -v "architecture is not supported" || true

    # Sanity check: any .so still with RWE flag?
    local rwe_files
    rwe_files=$(find "$CSS_DIR" -name "*.so" -exec sh -c '
        readelf -lW "$1" 2>/dev/null | grep -q "GNU_STACK.*RWE" && echo "$1"
    ' _ {} \;)
    if [[ -n "$rwe_files" ]]; then
        echo "[CSSharp] WARNING: .so files still with executable stack:" >&2
        echo "$rwe_files" >&2
    fi

    # Disable "FollowCS2ServerGuidelines" to allow custom skins
    local core_config="$CSS_DIR/configs/core.json"
    local example_config="$CSS_DIR/configs/core.example.json"

    if [[ ! -f "$core_config" && -f "$example_config" ]]; then
        sudo -u steam cp "$example_config" "$core_config"
    fi

    if [[ -f "$core_config" ]]; then
        echo "[CSSharp] Patching core.json: FollowCS2ServerGuidelines -> false"
        sudo -u steam sed -i \
            's/"FollowCS2ServerGuidelines": true/"FollowCS2ServerGuidelines": false/g' \
            "$core_config"
    fi

    echo "[CSSharp] Installed successfully"
}

install_metamod
install_counterstrikesharp

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