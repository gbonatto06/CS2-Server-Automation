#!/bin/bash
# Redirecionar saida para log para debug e liberar leitura para o Promtail
exec > /var/log/user-data.log 2>&1
sudo chmod 644 /var/log/user-data.log

# Garante que a senha venha do Terraform para uma variavel global do shell
SERVER_PASS_VAR="${server_password}"

echo "Provisionamento e configuracao do servidor de cs2"

# Dependencias do Sistema
sudo apt-get update
sudo apt-get install -y lib32gcc-s1 lib32stdc++6 curl tar unzip wget jq dotnet-runtime-8.0 docker.io docker-compose-v2 awscli python3-pip python3-venv

# Configuracao do Usuario steam e Variaveis de Caminho
sudo useradd -m steam || true
sudo usermod -aG docker steam
USER_HOME="/home/steam"
CS2_DIR="$USER_HOME/cs2_server"
CSGO_DIR="$CS2_DIR/game/csgo"
CSS_DIR="$CSGO_DIR/addons/counterstrikesharp"
MON_DIR="$USER_HOME/monitoring"
sudo -u steam mkdir -p $MON_DIR/prometheus $MON_DIR/promtail $MON_DIR/loki $MON_DIR/grafana
sudo -u steam mkdir -p $CSGO_DIR/logs
# Cria um arquivo vazio para garantir que o Promtail tenha o que ler e não reclame de wildcard vazio
sudo -u steam touch $CSGO_DIR/console.log

echo "Iniciando Stack de Observabilidade"

sudo -u steam mkdir -p $MON_DIR/prometheus $MON_DIR/promtail $MON_DIR/loki $MON_DIR/grafana

# Instalação das dependências do exportador de métricas do servidor
echo "Criando ambiente virtual Python..."
sudo -u steam python3 -m venv $MON_DIR/venv
sudo -u steam $MON_DIR/venv/bin/pip install python-valve prometheus_client

# Exporter de métricas
cat <<'PYTHON_EXP' | sudo -u steam tee $MON_DIR/cs2_exporter.py
import time, collections, collections.abc
from prometheus_client import start_http_server, Gauge, Info

if not hasattr(collections, 'Mapping'):
    collections.Mapping = collections.abc.Mapping
import valve.source.a2s

SERVER_ADDRESS = ("127.0.0.1", 27015)
EXPORTER_PORT = 9137

cs2_up = Gauge('cs2_server_up', 'Status do servidor')
cs2_players = Gauge('cs2_player_count', 'Contagem de jogadores')
cs2_map = Info('cs2_current_map', 'Informacoes do mapa')

def fetch_metrics():
    try:
        with valve.source.a2s.ServerQuerier(SERVER_ADDRESS, timeout=5) as server:
            info = server.info()
            cs2_up.set(1)
            cs2_players.set(info["player_count"])
            # Garante compatibilidade com diferentes versoes da lib valve
            map_name = info.get("map_name", info.get("map", "Unknown"))
            cs2_map.info({'map_name': map_name})
    except Exception as e:
        cs2_up.set(0)
        cs2_players.set(0)

if __name__ == '__main__':
    start_http_server(EXPORTER_PORT)
    while True:
        fetch_metrics()
        time.sleep(15)
PYTHON_EXP

# Servico Systemd para o Exportador Python
cat <<SYSTEMD_EXP | sudo tee /etc/systemd/system/cs2-exporter.service
[Unit]
Description=Exportador de métricas do CS2
After=network.target

[Service]
ExecStart=/home/steam/monitoring/venv/bin/python /home/steam/monitoring/cs2_exporter.py
Restart=always
User=steam

[Install]
WantedBy=multi-user.target
SYSTEMD_EXP

sudo systemctl daemon-reload
sudo systemctl enable cs2-exporter
sudo systemctl start cs2-exporter

# monitoramento do servidor para enviar pro grafana
cat <<PROMETHEUS | sudo -u steam tee $MON_DIR/prometheus/prometheus.yml
global:
  scrape_interval: 10s
  scrape_timeout: 9s

scrape_configs:
  - job_name: 'sistema'
    static_configs:
      - targets: ['127.0.0.1:9100']

  - job_name: 'cs2_game'
    static_configs:
      - targets: ['127.0.0.1:9137']

  - job_name: 'network_integrity'
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

# Configuração do Blackbox Exporter
cat <<BLACKBOX | sudo -u steam tee $MON_DIR/blackbox.yml
modules:
  icmp:
    prober: icmp
    timeout: 5s
    icmp:
      preferred_ip_protocol: "ip4"
BLACKBOX

cat <<LOKICONFIG | sudo -u steam tee $MON_DIR/loki/loki-config.yml
auth_enabled: false
server:
  http_listen_port: 3100

# Desabilita exigencia de schema v13 do Loki 3.0+
limits_config:
  allow_structured_metadata: false

common:
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory
  replication_factor: 1
  path_prefix: /tmp/loki

# Configuração do Compactor para evitar erro de mkdir e conflitos de retenção
compactor:
  working_directory: /tmp/loki/boltdb-shipper-compactor
  shared_store: filesystem

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  filesystem:
    directory: /tmp/loki/chunks
LOKICONFIG

# Config Promtail para ler o log de instalacao e do jogo
cat <<PROMTAIL | sudo -u steam tee $MON_DIR/promtail/config.yml
server:
  http_listen_port: 9080
  grpc_listen_port: 0
positions:
  filename: /tmp/positions.yaml
clients:
  - url: http://localhost:3100/loki/api/v1/push

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
        __path__: /home/steam/cs2_server/game/csgo/console.log
PROMTAIL

# Configurar Loki e Prometheus como Data Sources
sudo -u steam mkdir -p $MON_DIR/grafana/provisioning/datasources

cat <<DATASOURCES | sudo -u steam tee $MON_DIR/grafana/provisioning/datasources/ds.yaml
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    uid: Loki # UIDs explícitos para garantir link com o Dashboard
    access: proxy
    url: http://localhost:3100
    isDefault: false
  - name: Prometheus
    type: prometheus
    uid: Prometheus # UIDs explícitos para garantir link com o Dashboard
    access: proxy
    url: http://localhost:9090
    isDefault: true
DATASOURCES

# Configurar Dashboards
sudo -u steam mkdir -p $MON_DIR/grafana/provisioning/dashboards/definitions
cat <<DASHPROV | sudo -u steam tee $MON_DIR/grafana/provisioning/dashboards/provider.yaml
apiVersion: 1
providers:
  - name: 'CS2 Dashboards'
    orgId: 1
    folder: ''
    type: file
    options:
      path: /etc/grafana/provisioning/dashboards/definitions
DASHPROV

# JSON do Dashboard
cat <<'DASHJSON' | sudo -u steam tee $MON_DIR/grafana/provisioning/dashboards/definitions/cs2_server.json
{
  "editable": true,
  "refresh": "5s",
  "fiscalYearStartMonth": 0,
  "graphTooltip": 1,
  "links": [],
  "panels": [
    {
      "title": "Status do Servidor",
      "type": "stat",
      "gridPos": { "h": 4, "w": 6, "x": 0, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "Prometheus" },
      "targets": [ { "expr": "cs2_server_up", "format": "table", "refId": "A" } ],
      "fieldConfig": {
        "defaults": {
          "mappings": [
            { "type": "value", "options": { "0": { "text": "Offline", "color": "red" }, "1": { "text": "Online", "color": "green" } } },
            { "type": "special", "options": { "match": "null", "result": { "text": "Instalando", "color": "#FF9900" } } }
          ]
        }
      },
      "options": { "colorMode": "background", "graphMode": "none", "justifyMode": "center", "noDataText": "Instalando", "textMode": "value", "reduceOptions": { "calcs": ["last"], "values": false } }
    },
    {
      "title": "Conexão Rápida",
      "type": "text",
      "gridPos": { "h": 4, "w": 18, "x": 6, "y": 0 },
      "options": {
        "mode": "html",
        "content": "<div style='display:flex;align-items:center;justify-content:center;height:100%;gap:20px;'><div style='font-size:1.2em;'>IP do Servidor: <strong id='serverIp'>SERVER_IP_PLACE_PLACEHOLDER</strong></div><button id='copyBtn' onclick='window.copyConnectCommand()' style='background:#3274d9;color:white;border:none;padding:10px 20px;border-radius:5px;cursor:pointer;font-weight:bold;'>Copiar Connect</button></div><script>window.copyConnectCommand = function() { var ip = document.getElementById('serverIp').innerText; var pass = 'SERVER_PASSWORD_PLACEHOLDER'; var cmd = pass ? ('connect ' + ip + ':27015; password ' + pass) : ('connect ' + ip + ':27015'); var textArea = document.createElement('textarea'); textArea.value = cmd; document.body.appendChild(textArea); textArea.select(); try { document.execCommand('copy'); var btn = document.getElementById('copyBtn'); btn.innerText = 'Copiado!'; setTimeout(function() { btn.innerText = 'Copiar Connect'; }, 2000); } catch (err) { console.error('Erro ao copiar', err); } document.body.removeChild(textArea); }</script>"
      }
    },
    {
      "title": "Mapa & Players",
      "type": "stat",
      "gridPos": { "h": 6, "w": 6, "x": 0, "y": 4 },
      "datasource": { "type": "prometheus", "uid": "Prometheus" },
      "targets": [
        { "expr": "cs2_player_count", "legendFormat": "Jogadores", "refId": "A" },
        { "expr": "cs2_current_map_info", "legendFormat": "{{map_name}}", "refId": "B" }
      ],
      "options": { "textMode": "value_and_name", "reduceOptions": { "values": false, "calcs": ["last"], "fields": "/^Jogadores$|^map_name$/" } }
    },
    {
      "title": "Ping & Loss",
      "type": "stat",
      "gridPos": { "h": 6, "w": 6, "x": 6, "y": 4 },
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
      "gridPos": { "h": 6, "w": 12, "x": 12, "y": 4 },
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
      "gridPos": { "h": 14, "w": 12, "x": 0, "y": 10 },
      "datasource": { "type": "loki", "uid": "Loki" },
      "targets": [ { "expr": "{job=\"installation_logs\"}" } ],
      "options": { "sortOrder": "Descending", "showTime": true, "wrapLogMessage": true }
    },
    {
      "title": "Terminal do Servidor",
      "type": "logs",
      "gridPos": { "h": 14, "w": 12, "x": 12, "y": 10 },
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

# Injeta IP Público e Senha no Dashboard
PUBLIC_IP=$(curl -s https://ipv4.icanhazip.com | tr -d '\r\n')
sed -i "s|SERVER_IP_PLACE_PLACEHOLDER|$PUBLIC_IP|g" "$MON_DIR/grafana/provisioning/dashboards/definitions/cs2_server.json"
sed -i "s|SERVER_PASSWORD_PLACEHOLDER|$SERVER_PASS_VAR|g" "$MON_DIR/grafana/provisioning/dashboards/definitions/cs2_server.json"

# Docker Compose com Network Host e Promtail Root
cat <<DOCKERCOMPOSE | sudo -u steam tee $MON_DIR/docker-compose.yml
services:
  loki:
    image: grafana/loki:2.9.2
    network_mode: "host"
    user: "0:0"
    volumes: 
      - "./loki/loki-config.yml:/etc/loki/local-config.yaml"
      - "loki-data:/tmp/loki"
    command: -config.file=/etc/loki/local-config.yaml
    restart: always
    # Healthcheck para garantir que o Loki está pronto para receber logs
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:3100/ready || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5

  promtail:
    image: grafana/promtail:2.9.2
    network_mode: "host"
    user: "0:0"
    volumes:
      - /var/log:/var/log
      - ./promtail/config.yml:/etc/promtail/config.yml
      - /home/steam/cs2_server/game/csgo:/home/steam/cs2_server/game/csgo
      - promtail-positions:/tmp
    restart: always
    # Promtail só inicia DEPOIS que o Loki estiver "healthy"
    depends_on:
      loki:
        condition: service_healthy

  prometheus:
    image: prom/prometheus:latest
    network_mode: "host"
    volumes: ["./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml"]
    restart: always
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:9090/-/healthy || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 3

  grafana:
    image: grafana/grafana:latest
    network_mode: "host"
    volumes: ["./grafana/provisioning:/etc/grafana/provisioning"]
    environment:
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
      - GF_PANELS_DISABLE_SANITIZE_HTML=true
      - GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/etc/grafana/provisioning/dashboards/definitions/cs2_server.json
    restart: always
    # Grafana sobe depois que Prometheus e Loki estiverem rodando
    depends_on:
      prometheus:
        condition: service_healthy
      loki:
        condition: service_healthy
    
  node-exporter:
    image: prom/node-exporter:latest
    network_mode: "host"
    pid: "host"
    restart: always
    
  blackbox-exporter:
    image: prom/blackbox-exporter:latest
    network_mode: "host"
    volumes: ["./blackbox.yml:/config/blackbox.yml"]
    command: --config.file=/config/blackbox.yml
    restart: always

volumes:
  loki-data:
  promtail-positions:
DOCKERCOMPOSE

# Cria os diretórios e dá permissão antes de subir o Docker
sudo chown -R steam:steam $USER_HOME
sudo chmod -R 777 $MON_DIR
# Permissão na pasta de logs do jogo que criamos antecipadamente
sudo chmod -R 777 $CSGO_DIR

cd $MON_DIR && sudo docker compose up -d

# Aguarda serviços de monitoramento estabilizarem
until curl -s --fail http://127.0.0.1:9090/-/healthy > /dev/null; do sleep 5; done
echo "Stack de Monitoramento UP! Iniciando o download do jogo."

cd $USER_HOME
# Instalacao do SteamCMD e CS2
echo "Baixando CS2 via SteamCMD"
sudo -u steam mkdir -p $USER_HOME/steamcmd
cd $USER_HOME/steamcmd
sudo -u steam curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | sudo -u steam tar zxvf -
sudo -u steam ./steamcmd.sh +force_install_dir $CS2_DIR +login anonymous +app_update 730 validate +quit


echo "Criando link simbólico para steamclient.so..."
sudo -u steam mkdir -p /home/steam/.steam/sdk64
sudo -u steam ln -s /home/steam/cs2_server/linux64/steamclient.so /home/steam/.steam/sdk64/steamclient.so

# Ajuste de Permissoes Recursivas
sudo chown -R steam:steam $USER_HOME/
# Garante que o console.log seja legivel, após a atualização
sudo chmod -R 755 $CSGO_DIR

# Aguardar a criação real do gameinfo.gi
echo "Aguardando a criação do arquivo gameinfo.gi pelo SteamCMD..."
until [ -f "$CSGO_DIR/gameinfo.gi" ]; do
    echo "Aguardando arquivos base do jogo..."
    sleep 10
done

# Instalacao do Metamod
LATEST_METAMOD_FILE=$(curl -s https://mms.alliedmods.net/mmsdrop/2.0/mmsource-latest-linux)
sudo -u steam wget "https://mms.alliedmods.net/mmsdrop/2.0/$LATEST_METAMOD_FILE" -O /tmp/metamod.tar.gz
sudo -u steam tar -xzvf /tmp/metamod.tar.gz -C $CSGO_DIR

# Alteracao do gameinfo.gi
if ! grep -q "csgo/addons/metamod" $CSGO_DIR/gameinfo.gi; then
    sudo -u steam sed -i '/Game_LowViolence/a \            Game    csgo/addons/metamod' $CSGO_DIR/gameinfo.gi
fi

# Instalacao do CSSharp e Plugins Base
CSS_URL=$(curl -s https://api.github.com/repos/roflmuffin/CounterStrikeSharp/releases/latest | jq -r '.assets[] | select(.name | contains("with-runtime") and contains("linux")) | .browser_download_url')
sudo -u steam wget $CSS_URL -O /tmp/css.zip && sudo -u steam unzip -o /tmp/css.zip -d $CSGO_DIR

for plugin in AnyBaseLib PlayerSettings MenuManager; do
    URL=$(curl -s "https://api.github.com/repos/NickFox007/""$plugin""CS2/releases/latest" | jq -r ".assets[] | select(.name == \"$plugin.zip\") | .browser_download_url")
    sudo -u steam wget $URL -O /tmp/$plugin.zip && sudo -u steam unzip -o /tmp/$plugin.zip -d $CSGO_DIR
done

# MatchZy e WeaponPaints
MATCHZY_URL=$(curl -s https://api.github.com/repos/shobhit-pathak/MatchZy/releases/latest | jq -r '.assets[] | select(.name | startswith("MatchZy-") and endswith(".zip") and (contains("with-cssharp") | not)) | .browser_download_url')
sudo -u steam wget $MATCHZY_URL -O /tmp/matchzy.zip && sudo -u steam unzip -o /tmp/matchzy.zip -d $CSGO_DIR

WEAPONPAINTS_URL=$(curl -s https://api.github.com/repos/Nereziel/cs2-WeaponPaints/releases/latest | jq -r '.assets[] | select(.name == "WeaponPaints.zip") | .browser_download_url')
sudo -u steam wget $WEAPONPAINTS_URL -O /tmp/weaponpaints.zip
sudo -u steam mkdir -p /tmp/wp_temp && sudo -u steam unzip -o /tmp/weaponpaints.zip -d /tmp/wp_temp
sudo -u steam cp -rf /tmp/wp_temp/WeaponPaints $CSS_DIR/plugins/
sudo -u steam cp -rf /tmp/wp_temp/gamedata/* $CSS_DIR/gamedata/

# Configuracao DB e Restore
sudo docker run -d --name cs2-mysql --restart always -e MYSQL_ROOT_PASSWORD=root_password_123 -e MYSQL_DATABASE=cs2_server -e MYSQL_USER=cs2_admin -e MYSQL_PASSWORD=cs2_password_safe -p 3306:3306 -v /home/steam/mysql_data:/var/lib/mysql mysql:8.0
until sudo docker exec cs2-mysql mysqladmin ping -h 127.0.0.1 -u"cs2_admin" -p"cs2_password_safe" --silent; do sleep 5; done

LATEST_BACKUP=$(aws s3 ls s3://${s3_bucket_name}/ | sort | tail -n 1 | awk '{print $4}')
if [ -n "$LATEST_BACKUP" ]; then
    aws s3 cp s3://${s3_bucket_name}/$LATEST_BACKUP /tmp/restore_db.sql
    docker exec -i cs2-mysql mysql -h 127.0.0.1 -u cs2_admin -pcs2_password_safe cs2_server < /tmp/restore_db.sql
fi

# Scripts de Inicializacao
cat <<'EOF' | sudo tee $USER_HOME/start_server.sh
#!/bin/bash
set -euo pipefail

# Terraform injeta os valores aqui
GSLT_TOKEN="${gslt_token}"
SERVER_PASS="${server_password}"

cd /home/steam/cs2_server/game/bin/linuxsteamrt64

export LD_LIBRARY_PATH=".:$${LD_LIBRARY_PATH:-}"

# Usamos as variáveis definidas no início deste arquivo
./cs2 -dedicated -condebug -usercon -ip 0.0.0.0 -port 27015 +map de_mirage +sv_setsteamaccount "$GSLT_TOKEN" +sv_password "$SERVER_PASS" +log on +sv_logflush 1 +sv_logsdir logs
EOF

cat <<'EOF' | sudo tee $USER_HOME/backup_db.sh
#!/bin/bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
docker exec cs2-mysql mysqldump -h 127.0.0.1 -u cs2_admin -pcs2_password_safe cs2_server > "/home/steam/backup_$TIMESTAMP.sql"
aws s3 cp "/home/steam/backup_$TIMESTAMP.sql" "s3://${s3_bucket_name}/"
EOF

sudo chmod +x $USER_HOME/*.sh && sudo chown steam:steam $USER_HOME/*.sh
sudo -u steam mkdir -p $CSGO_DIR/logs

# Servico CS2
cat <<EOF | sudo tee /etc/systemd/system/cs2.service
[Unit]
Description=Counter-Strike 2 Dedicated Server
After=network-online.target docker.service
[Service]
Type=simple
User=steam
Group=steam
Environment="HOME=/home/steam"
WorkingDirectory=/home/steam/cs2_server/game/bin/linuxsteamrt64
ExecStart=/bin/bash /home/steam/start_server.sh
ExecStop=/bash /home/steam/backup_db.sh
Restart=always
RestartSec=15
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload && sudo systemctl enable cs2 && sudo systemctl start cs2
echo "Setup Finalizado com sucesso."