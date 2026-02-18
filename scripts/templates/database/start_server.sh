#!/bin/bash
set -euo pipefail

# Variables injected by the provisioner
GSLT_TOKEN="GSLT_TOKEN_PLACEHOLDER"
SERVER_PASS="SERVER_PASSWORD_PLACEHOLDER"

cd /home/steam/cs2_server/game/bin/linuxsteamrt64

# Ensure libraries are found
export LD_LIBRARY_PATH=".:${LD_LIBRARY_PATH:-}"

# Start the server
# +sv_setsteamaccount: Links the server to a GSLT
# +sv_logflush 1: Ensures logs are written to disk immediately
./cs2 -dedicated \
  -usercon \
  -ip 0.0.0.0 \
  -port 27015 \
  +map de_mirage \
  +sv_setsteamaccount "$GSLT_TOKEN" \
  +sv_password "$SERVER_PASS" \
  +log on \
  +sv_logflush 1 \
  +sv_logsdir logs \
  > /home/steam/cs2_server/game/csgo/console.log 2>&1