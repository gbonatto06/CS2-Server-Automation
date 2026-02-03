#!/bin/bash
# Redirecionar saida para log para debug
exec > /var/log/user-data.log 2>&1
echo "Provisionamento e configuracao do servidor de cs2"

# Dependencias do Sistema
sudo apt-get update
sudo apt-get install -y lib32gcc-s1 lib32stdc++6 curl tar unzip wget jq dotnet-runtime-8.0 docker.io docker-compose-v2 awscli

# Configuracao do Usuario steam e Variaveis de Caminho
sudo useradd -m steam || true
sudo usermod -aG docker steam
USER_HOME="/home/steam"
CS2_DIR="$USER_HOME/cs2_server"
CSGO_DIR="$CS2_DIR/game/csgo"
CSS_DIR="$CSGO_DIR/addons/counterstrikesharp"

echo "Iniciando Stack de Observabilidade"
MON_DIR="$USER_HOME/monitoring"
sudo -u steam mkdir -p $MON_DIR/prometheus $MON_DIR/promtail

# monitoramento do servidor para enviar pro grafana
cat <<PROMETHEUS | sudo -u steam tee $MON_DIR/prometheus/prometheus.yml
global:
  scrape_interval: 10s  
  scrape_timeout: 10s

scrape_configs:
  - job_name: 'sistema' # monitoramento da infraestrutura
    static_configs:
      - targets: ['127.0.0.1:9100']

  - job_name: 'cs2_game'  # monitoramento do servidor
    static_configs:
      - targets: ['127.0.0.1:9137']

  - job_name: 'network_integrity' # Vamos monitorar a rede com o blackbox
    metrics_path: /probe
    params:
      module: [icmp]
    static_configs:
      - targets: ['127.0.0.1']
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - target_label: __address__
        replacement: 127.0.0.1:9115
PROMETHEUS

# Config Promtail para ler o log de instalacao
cat <<PROMTAIL | sudo -u steam tee $MON_DIR/promtail/config.yml
server:
  http_listen_port: 9080
clients:
  - url: http://loki:3100/loki/api/v1/push
scrape_configs:
  - job_name: infra_logs
    static_configs:
    - targets: [localhost]
      labels:
        job: installation_logs
        __path__: /var/log/user-data.log

  - job_name: game_logs
    static_configs:
    - targets: [localhost]
      labels:
        job: cs2_console_logs
        # Mapeia logs do console e do CounterStrikeSharp
        __path__: /home/steam/cs2_server/game/csgo/logs/*.log
PROMTAIL

# Criar diretorio de provisionamento do Grafana
sudo -u steam mkdir -p $MON_DIR/grafana/provisioning/datasources

# Configurar Loki e Prometheus como Data Sources automaticos
cat <<DATASOURCES | sudo -u steam tee $MON_DIR/grafana/provisioning/datasources/ds.yaml
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    isDefault: true
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://172.17.0.1:9090
DATASOURCES

# Criar pastas de provisionamento para Dashboards
sudo -u steam mkdir -p $MON_DIR/grafana/provisioning/dashboards/definitions

# Criar o Provider (Diz ao Grafana para ler arquivos JSON nesta pasta)
cat <<DASHPROV | sudo -u steam tee $MON_DIR/grafana/provisioning/dashboards/provider.yaml
apiVersion: 1
providers:
  - name: 'CS2 Dashboards'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /etc/grafana/provisioning/dashboards/definitions
DASHPROV


# Captura o IP privado interno da instância
INTERNAL_IP=$(hostname -I | awk '{print $1}')
# Configuração do SRCDS Exporter para exportar métricas do CS2
# Cria o config com o IP privado 
cat <<SRCDSCONF | sudo tee /home/steam/monitoring/prometheus/srcds.yaml
options:
  connectTimeout: 5s
servers:
  cs2_dedicated:
    address: "$${INTERNAL_IP}:27015" # Uso do IP privado pois o cs2 não estava aceitando ip interno
    rconPassword: "${server_password}"
SRCDSCONF

# Salvar o JSON Completo do Dashboard
cat <<'DASHJSON' | sudo -u steam tee $MON_DIR/grafana/provisioning/dashboards/definitions/cs2_server.json
{
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 1,
  "links": [],
  "panels": [
    {
      "title": "Status do Servidor",
      "type": "stat",
      "gridPos": { "h": 4, "w": 6, "x": 0, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "Prometheus" },
      "targets": [
        { "expr": "srcds_up{instance=\"cs2_dedicated\"}", "format": "table", "refId": "A" }
      ],
      "options": {
        "colorMode": "background",
        "graphMode": "none",
        "justifyMode": "center",
        "reduceOptions": { "calcs": ["last"], "fields": "", "values": false },
        "textMode": "value",
        "text": { "valueSize": 24 },
        "fieldConfig": {
          "defaults": {
            "mappings": [
              { "type": "special", "options": { "match": "null", "result": { "text": "OFFLINE", "color": "red" } } },
              { "type": "range", "options": { "from": 0, "to": 100000, "result": { "text": "ONLINE", "color": "green" } } }
            ]
          }
        }
      }
    },
    {
      "title": "Conexão Rápida",
      "type": "text",
      "gridPos": { "h": 4, "w": 18, "x": 6, "y": 0 },
      "options": {
        "mode": "html",
        "content": "<div style='display:flex;align-items:center;justify-content:center;height:100%;gap:20px;'><div style='font-size:1.2em;'>IP do Servidor: <strong id='serverIp'>SERVER_IP_PLACEHOLDER</strong></div><button id='copyBtn' onclick='copyConnectCommand()' style='background:#3274d9;color:white;border:none;padding:10px 20px;border-radius:5px;cursor:pointer;font-weight:bold;'>Copiar Comando</button></div><script>function copyConnectCommand(){const i=document.getElementById('serverIp').innerText,p='${server_password}',c=p?`connect $${i}:27015; password $${p}`:`connect $${i}:27015`;navigator.clipboard.writeText(c).then(()=>{const b=document.getElementById('copyBtn'),o=b.innerText;b.innerText='Copiado!';b.style.background='#56A64B';setTimeout(()=>{b.innerText=o;b.style.background='#3274d9'},2000)})}</script>"
      }
    },
    {
      "title": "Mapa / Players",
      "type": "stat",
      "gridPos": { "h": 6, "w": 6, "x": 0, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "Prometheus" },
      "targets": [
        { "expr": "srcds_playercount{instance=\"cs2_dedicated\"}", "refId": "A" },
        { "expr": "srcds_map{instance=\"cs2_dedicated\"}", "refId": "B" }
      ],
      "options": {
        "textMode": "value_and_name",
        "reduceOptions": { "values": false, "calcs": ["last"], "fields": "/^map$|^value$/" }
      }
    },
    {
      "title": "Ping & Loss",
      "type": "stat",
      "gridPos": { "h": 6, "w": 6, "x": 6, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "Prometheus" },
      "targets": [
        { "expr": "avg_over_time(probe_duration_seconds[5m]) * 1000", "legendFormat": "Ping (ms)" },
        { "expr": "(1 - avg_over_time(probe_success[5m])) * 100", "legendFormat": "Loss (%)" }
      ],
      "options": { "graphMode": "area", "justifyMode": "center" }
    },
    {
      "title": "Recursos da Infraestrutura",
      "type": "timeseries",
      "gridPos": { "h": 6, "w": 12, "x": 12, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "Prometheus" },
      "targets": [
        { "expr": "100 - (avg by (instance) (irate(node_cpu_seconds_total{mode='idle'}[5m])) * 100)", "legendFormat": "CPU %" },
        { "expr": "((node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes) * 100", "legendFormat": "RAM %" }
      ],
      "options": { "legend": { "displayMode": "table", "placement": "right" } }
    },
    {
      "title": "Terminal da Infraestrutura",
      "type": "logs",
      "gridPos": { "h": 14, "w": 12, "x": 0, "y": 6 },
      "datasource": { "type": "loki", "uid": "Loki" },
      "targets": [ { "expr": "{job=\"installation_logs\"}" } ],
      "options": { "sortOrder": "Descending", "showTime": true, "wrapLogMessage": true }
    },
    {
      "title": "Terminal do Servidor",
      "type": "logs",
      "gridPos": { "h": 14, "w": 12, "x": 12, "y": 6 },
      "datasource": { "type": "loki", "uid": "Loki" },
      "targets": [ { "expr": "{job=\"cs2_console_logs\"}" } ],
      "options": { "sortOrder": "Descending", "showTime": true, "wrapLogMessage": true }
    }
  ],
  "schemaVersion": 36,
  "title": "Servidor de CS2",
  "uid": "cs2_01",
  "version": 1
}
DASHJSON

# Capturamos o IP público da nossa máquina atual
PUBLIC_IP=$(curl -s https://ipv4.icanhazip.com | tr -d '\r\n') # remove possíveis quebras de linhas e retornos indesejados
# Define o caminho do arquivo JSON do Dashboard
DASH_FILE="$MON_DIR/grafana/provisioning/dashboards/definitions/cs2_server.json"
# Injetamos o IP do servidor para que ele seja mostrado lá no grafana
sudo sed -i "s|SERVER_IP_PLACEHOLDER|$PUBLIC_IP|g" "$DASH_FILE"

echo "IP $PUBLIC_IP injetado com sucesso no dashboard."

# Docker Compose
cat <<DOCKERCOMPOSE | sudo -u steam tee $MON_DIR/docker-compose.yml
services:
  grafana:
    image: grafana/grafana:latest
    ports: ["3000:3000"]
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning
    environment:
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
      - GF_SERVER_PUBLIC_IP=$(curl -s https://ipv4.icanhazip.com) # Captura o IP para o Grafana
      - GF_PANELS_DISABLE_SANITIZE_HTML=true # Habilita botões HTML
      - GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/etc/grafana/provisioning/dashboards/definitions/cs2_server.json # Pagina principal do grafana vai ser o dashboard
    restart: always
  prometheus:
    image: prom/prometheus:latest
    network_mode: "host"
    volumes: ["./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml"]
    restart: always
  loki:
    image: grafana/loki:latest
    ports: ["3100:3100"]
    restart: always
  promtail:
    image: grafana/promtail:latest
    volumes: ["/var/log:/var/log", "./promtail/config.yml:/etc/promtail/config.yml"]
    restart: always
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    network_mode: "host"
    pid: "host"
    restart: always
  cs2-exporter:
    image: ghcr.io/galexrt/srcds_exporter:v1.6.0 #Não temos versão latest aqui
    container_name: cs2-exporter
    volumes:
      - ./prometheus/srcds.yaml:/etc/srcds.yaml
    command:
      - --config.file=/etc/srcds.yaml
    network_mode: "host" # Comunicação com o CS2 em 127.0.0.1
    restart: always
  blackbox-exporter:
    image: prom/blackbox-exporter:latest # blackbox para monitoramento da rede
    container_name: blackbox-exporter
    network_mode: "host"
    restart: always
DOCKERCOMPOSE

cd $MON_DIR
sudo docker compose up -d

echo "Aguardando Grafana estabilizar na porta 3000."
# Usamos 127.0.0.1 para evitar problemas de DNS local e --fail para simplificar a logica
until curl -s --fail http://127.0.0.1:3000/api/health > /dev/null; do
  echo "Grafana ainda carregando plugins e banco de dados interno."
  sleep 5
done
echo "Grafana UP! Iniciando o download do jogo."


cd $USER_HOME
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
./cs2 -dedicated -usercon -condebug -ip 0.0.0.0 -port 27015 +map de_dust2 +game_type 0 +game_mode 1 +sv_setsteamaccount "\$GSLT_TOKEN" +sv_password "\$SERVER_PASS" +rcon_password "${server_password}" +log on +sv_logflush 1 +sv_logsdir logs
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

# permissões de arquivos
sudo chmod +x $USER_HOME/*.sh
sudo chown steam:steam $USER_HOME/*.sh
sudo chmod -R 755 $CSGO_DIR/logs

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