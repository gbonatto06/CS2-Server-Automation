#!/bin/bash
# This script acts as the entry point for the provisioner.
# It sets up the global environment, exports variables,
# and executes the installation modules in sequence.

# Global Log Configuration
LOG_FILE="/var/log/user-data.log"

touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# Append output to log file and also show on console
exec > >(tee -a "$LOG_FILE") 2>&1


echo "Starting CS2 Server Automation"
date

# Directory Detection
# Determines the absolute path of where this script is located
INSTALL_SOURCE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export INSTALL_SOURCE_DIR
echo "Detected Source Directory: $INSTALL_SOURCE_DIR"

# Force navigation to the script directory to ensure relative module paths work
cd "$INSTALL_SOURCE_DIR" || { echo "Critical Error: Failed to change directory to $INSTALL_SOURCE_DIR"; exit 1; }

# Import Secrets from Environment
echo "Importing Secrets"
# These env vars are injected by Terraform user_data before calling this script.
# Defaulting to empty strings prevents unbound variable errors during assignment.
export SERVER_PASS="${server_password:-}"
export DB_PASS="${db_password:-}"
export GSLT_TOKEN="${gslt_token:-}"
export S3_BUCKET="${s3_bucket_name:-}"

# Global Paths Definition
echo "Exporting Global Paths"
export USER_HOME="/home/steam"
export CS2_DIR="$USER_HOME/cs2_server"
export CSGO_DIR="$CS2_DIR/game/csgo"
export CSS_DIR="$CSGO_DIR/addons/counterstrikesharp"
export MON_DIR="$USER_HOME/monitoring"

# Pre-Flight Validation
echo "Validating Secrets"
MISSING_VARS=0

if [ -z "$SERVER_PASS" ]; then echo "Error: server_password env var is missing"; MISSING_VARS=1; fi
if [ -z "$DB_PASS" ]; then echo "Error: db_password env var is missing"; MISSING_VARS=1; fi
if [ -z "$GSLT_TOKEN" ]; then echo "Error: gslt_token env var is missing"; MISSING_VARS=1; fi
if [ -z "$S3_BUCKET" ]; then echo "Error: s3_bucket_name env var is missing"; MISSING_VARS=1; fi

if [ "$MISSING_VARS" -eq 1 ]; then
    echo "Critical Error: One or more required secrets are missing. Aborting."
    exit 1
fi

# Module Execution Strategy
MODULES_DIR="$INSTALL_SOURCE_DIR/modules"

# Ensure all modules are executable
chmod +x "$MODULES_DIR"/*.sh

run_module() {
    local script_name=$1
    local script_path="$MODULES_DIR/$script_name"
    
    echo "Running Module: $script_name"
    
    
    if [ -f "$script_path" ]; then
        # 'source' runs the script in the current shell context, sharing variables.
        # shellcheck source=/dev/null
        source "$script_path"
        
        # Capture the exit code of the last command in the sourced script
        if [ $? -eq 0 ]; then
            echo "Module $script_name completed"
        else
            echo "Critical Error: Module $script_name Failed. Aborting Setup."
            exit 1
        fi
    else
        echo "Critical Error: Module $script_name not found at $script_path"
        exit 1
    fi
}

# Execution Sequence

# System Dependencies
run_module "sys_deps.sh"

# Observability
run_module "observability.sh"

# Game Setup
run_module "steam_setup.sh"

# Plugins
run_module "plugins.sh"

# Databases & Lifecycle
run_module "database.sh"

echo ""
echo "Provisioning Finished"
echo "Server IP: $(curl -s https://ipv4.icanhazip.com)"
date