#!/bin/bash
# Redirecionar saida para log para debug
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Provisionamento e configuracao do servidor de cs2"

# Dependencias do Sistema
sudo apt-get update
sudo apt-get install -y lib32gcc-s1 lib32stdc++6 curl tar unzip wget jq dotnet-runtime-8.0 docker.io awscli

# Configuracao do Usuario steam e Variaveis de Caminho
sudo useradd -m steam || true
sudo usermod -aG docker steam
USER_HOME="/home/steam"
CS2_DIR="$USER_HOME/cs2_server"
CSGO_DIR="$CS2_DIR/game/csgo"
CSS_DIR="$CSGO_DIR/addons/counterstrikesharp"

# Instalacao do SteamCMD e CS2
echo "Baixando CS2 via SteamCMD"
sudo -u steam mkdir -p $USER_HOME/steamcmd
cd $USER_HOME/steamcmd
sudo -u steam curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | sudo -u steam tar zxvf -
sudo -u steam ./steamcmd.sh +force_install_dir $CS2_DIR +login anonymous +app_update 730 validate +quit

# Instalacao do Metamod
echo "Buscando versao mais recente do metamod"
LATEST_METAMOD_FILE=$(curl -s https://mms.alliedmods.net/mmsdrop/2.0/mmsource-latest-linux)
METAMOD_URL="https://mms.alliedmods.net/mmsdrop/2.0/$LATEST_METAMOD_FILE"
sudo -u steam wget $METAMOD_URL -O /tmp/metamod.tar.gz
sudo -u steam tar -xzvf /tmp/metamod.tar.gz -C $CSGO_DIR

# Alteracao do gameinfo.gi do metamod
if ! grep -q "csgo/addons/metamod" $CSGO_DIR/gameinfo.gi; then
    sudo -u steam sed -i '/Game_LowViolence/a \            Game    csgo/addons/metamod' $CSGO_DIR/gameinfo.gi
fi

# Instalacao do CSSharp
echo "Buscando versao mais recente do CSSharp"
CSS_URL=$(curl -s https://api.github.com/repos/roflmuffin/CounterStrikeSharp/releases/latest | jq -r '.assets[] | select(.name | contains("with-runtime") and contains("linux")) | .browser_download_url')
sudo -u steam wget $CSS_URL -O /tmp/css.zip
sudo -u steam unzip -o /tmp/css.zip -d $CSGO_DIR

# Instalacao de Plugins Base (AnyBaseLib, PlayerSettings, MenuManager)
for plugin in AnyBaseLib PlayerSettings MenuManager; do
    # Usamos $plugin sem chaves para evitar confusao no Terraform
    URL=$(curl -s "https://api.github.com/repos/NickFox007/""$plugin""CS2/releases/latest" | jq -r ".assets[] | select(.name == \"$plugin.zip\") | .browser_download_url")
    sudo -u steam wget $URL -O /tmp/$plugin.zip
    sudo -u steam unzip -o /tmp/$plugin.zip -d $CSGO_DIR
done

# Instalacao MatchZy
MATCHZY_URL=$(curl -s https://api.github.com/repos/shobhit-pathak/MatchZy/releases/latest | jq -r '.assets[] | select(.name | startswith("MatchZy-") and endswith(".zip") and (contains("with-cssharp") | not)) | .browser_download_url')
sudo -u steam wget $MATCHZY_URL -O /tmp/matchzy.zip
sudo -u steam unzip -o /tmp/matchzy.zip -d $CSGO_DIR
sudo -u steam sed -i 's/matchzy_everyone_is_admin false/matchzy_everyone_is_admin true/' $CSGO_DIR/cfg/MatchZy/config.cfg

# Instalacao WeaponPaints
WEAPONPAINTS_URL=$(curl -s https://api.github.com/repos/Nereziel/cs2-WeaponPaints/releases/latest | jq -r '.assets[] | select(.name == "WeaponPaints.zip") | .browser_download_url')
sudo -u steam wget $WEAPONPAINTS_URL -O /tmp/weaponpaints.zip
sudo -u steam mkdir -p /tmp/wp_temp
sudo -u steam unzip -o /tmp/weaponpaints.zip -d /tmp/wp_temp
sudo -u steam cp -rf /tmp/wp_temp/WeaponPaints $CSS_DIR/plugins/
sudo -u steam cp -rf /tmp/wp_temp/gamedata/* $CSS_DIR/gamedata/
rm -rf /tmp/wp_temp

# -----------------------------------------------------------------------#
# Configuracao do DB e Restore do DB
echo "Provisionando Banco de Dados"
sudo mkdir -p /home/steam/mysql_data
sudo chown -R 999:999 /home/steam/mysql_data
sudo systemctl enable --now docker
sudo docker rm -f cs2-mysql || true
sudo docker run -d --name cs2-mysql --restart always -e MYSQL_ROOT_PASSWORD=root_password_123 -e MYSQL_DATABASE=cs2_server -e MYSQL_USER=cs2_admin -e MYSQL_PASSWORD=cs2_password_safe -p 3306:3306 -v /home/steam/mysql_data:/var/lib/mysql mysql:8.0

# Verificacao de Restore do S3
until sudo docker exec cs2-mysql mysqladmin ping -h 127.0.0.1 -u"cs2_admin" -p"cs2_password_safe" --silent; do
    echo "Aguardando MySQL subir."
    sleep 5
done

# Aguardar acesso ao S3 (Variaveis do Terraform sem chaves extras)
until aws s3 ls "s3://${s3_bucket_name}" > /dev/null 2>&1; do
    echo "Aguardando permissao do S3..."
    sleep 5
done

LATEST_BACKUP=$(aws s3 ls s3://${s3_bucket_name}/ | sort | tail -n 1 | awk '{print $4}')
if [ -n "$LATEST_BACKUP" ]; then
    echo "Restaurando backup: $LATEST_BACKUP"
    aws s3 cp s3://${s3_bucket_name}/$LATEST_BACKUP /tmp/restore_db.sql
    docker exec -i cs2-mysql mysql -h 127.0.0.1 -u cs2_admin -pcs2_password_safe cs2_server < /tmp/restore_db.sql
    rm -f /tmp/restore_db.sql
fi

# -----------------------------------------------------------------------#
# Arquivos de Configuracao
echo '{"FollowCS2ServerGuidelines": false}' | sudo -u steam tee "$CSS_DIR/configs/core.json"
WP_CONFIG_DIR="$CSS_DIR/configs/plugins/WeaponPaints"
sudo -u steam mkdir -p $WP_CONFIG_DIR
cat <<PLUGINEOF | sudo -u steam tee $WP_CONFIG_DIR/WeaponPaints.json
{
    "Version": 4,
    "DatabaseHost": "127.0.0.1",
    "DatabasePort": 3306,
    "DatabaseUser": "cs2_admin",
    "DatabasePassword": "cs2_password_safe",
    "DatabaseName": "cs2_server",
    "Additional": { "KnifeEnabled": true, "SkinEnabled": true, "CommandSkin": ["ws"] }
}
PLUGINEOF

# Identidade Steam
sudo -u steam cp /home/steam/steamcmd/linux64/steamclient.so /home/steam/.steam/sdk64/steamclient.so
sudo -u steam cp /home/steam/steamcmd/linux64/steamclient.so $CS2_DIR/game/bin/linuxsteamrt64/steamclient.so
sudo -u steam echo "730" > $CS2_DIR/game/bin/linuxsteamrt64/steam_appid.txt
sudo chown -R steam:steam /home/steam/

# -----------------------------------------------------------------------#
# Script de inicializacao do servidor de cs
cat <<EOF | sudo tee $USER_HOME/start_server.sh
#!/bin/bash
set -euo pipefail
GSLT_TOKEN="${gslt_token}"
SERVER_PASS="${server_password}"
if [ -z "\$GSLT_TOKEN" ] || [ \$${#GSLT_TOKEN} -lt 20 ]; then
  echo "ERRO: Token GSLT invalido"
  exit 1
fi
export DOTNET_BUNDLE_EXTRACT_BASE_DIR=$USER_HOME/.net/extract
# Usamos o escape duplo do Terraform ($$) para variaveis complexas do Linux
export LD_LIBRARY_PATH="$CS2_DIR/game/bin/linuxsteamrt64:\$${LD_LIBRARY_PATH:-}"
cd $CS2_DIR/game/bin/linuxsteamrt64
./cs2 -dedicated -usercon -ip 0.0.0.0 -port 27015 +map de_dust2 +game_type 0 +game_mode 1 +sv_setsteamaccount "\$GSLT_TOKEN" +sv_password "\$SERVER_PASS"
EOF

# Script de backup do banco de dados das skins
cat <<EOF | sudo tee $USER_HOME/backup_db.sh
#!/bin/bash
set -euo pipefail
S3_BUCKET="${s3_bucket_name}"
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="/home/steam/backup_cs2_\$TIMESTAMP.sql"
docker exec cs2-mysql mysqldump --no-tablespaces --single-transaction --quick -h 127.0.0.1 -u cs2_admin -pcs2_password_safe cs2_server > "\$BACKUP_PATH"
if [ -s "\$BACKUP_PATH" ]; then
    aws s3 cp "\$BACKUP_PATH" "s3://\$S3_BUCKET/" --only-show-errors
    rm -f "\$BACKUP_PATH"
fi
EOF

sudo chmod +x $USER_HOME/*.sh
sudo chown steam:steam $USER_HOME/*.sh

# Servico Systemd
cat <<EOF | sudo tee /etc/systemd/system/cs2.service
[Unit]
Description=Counter-Strike 2 Dedicated Server
After=network-online.target docker.service
Requires=docker.service

[Service]
Type=simple
User=steam
Group=steam
TimeoutStopSec=120
Environment="HOME=/home/steam"
WorkingDirectory=/home/steam/cs2_server/game/bin/linuxsteamrt64
ExecStart=/bin/bash /home/steam/start_server.sh
ExecStop=/bin/bash /home/steam/backup_db.sh
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable cs2
sudo systemctl start cs2
echo "Setup Finalizado com sucesso."