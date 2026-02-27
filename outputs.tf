# GLOBAL LINKS

output "grafana_url" {
  description = "Direct URL for Server Monitoring / Link Direto para Monitoramento"
  # We use the UID 'cs2_01' defined in the Dashboard JSON
  value = "http://${module.compute.public_ip}:3000/d/cs2_01/servidor-de-cs2?kiosk=1"
}

output "server_ip" {
  description = "Public IP of the CS2 Server / IP Público do Servidor"
  value       = module.compute.public_ip
}

# INSTRUCTIONS (ENGLISH)

output "final_instructions_en" {
  description = "Provisioning follow-up instructions"
  value       = <<EOT

CS2 SERVER PROVISIONING STARTED

Infrastructure on AWS created successfully! The server is now configuring
the Python environment, installing the monitoring stack, downloading the game and configurating the plugins.

MONITOR EVERYTHING VIA GRAFANA:
  Direct Link: http://${module.compute.public_ip}:3000/d/cs2_01/servidor-de-cs2?kiosk=1

INITIALIZATION DELAY:
  The monitoring stack (Grafana/Loki) takes 1 to 3 minutes to fully initialize.
  If the link above returns a connection error initially, please wait a moment and refresh.

WHAT TO WATCH ON THE DASHBOARD:
  - Server Status & Map: Real-time uptime, current player count, and active map info.
  - Resource Usage: CPU and RAM metrics to monitor server performance.
  - Infrastructure Terminal: Track the real-time progress of the SteamCMD download.
  - Server Terminal: See the game boot process and in-game logs once the download finishes.
  - Quick Connect: The 'connect' command will appear on the top panel once ready.

ACCESS & DEBUGGING:
  - S3 Bucket (Database): https://s3.console.aws.amazon.com/s3/buckets/${module.storage.bucket_name}?region=${var.aws_region}
  - SSH Access: ssh -i cs2-server-key.pem ubuntu@${module.compute.public_ip}
  - Manual Debug: ssh -i cs2-server-key.pem ubuntu@${module.compute.public_ip} "tail -f /var/log/user-data.log"

EOT
}

# INSTRUÇÕES (PORTUGUÊS)

output "instrucoes_finais_pt" {
  description = "Instruções de acompanhamento do provisionamento"
  value       = <<EOT

SERVIDOR DE CS2 EM PROVISIONAMENTO

A infraestrutura na AWS foi criada com sucesso! O servidor agora está configurando
o ambiente virtual Python, instalando a stack de monitoramento, baixando o jogo e configurando os plugins.

ACOMPANHE TUDO PELO GRAFANA:
  Link Direto: http://${module.compute.public_ip}:3000/d/cs2_01/servidor-de-cs2?kiosk=1

DELAY DE INICIALIZAÇÃO:
  A stack de monitoramento pode levar de 1 a 3 minutos para subir completamente.
  Caso o link acima retorne erro de conexão inicialmente, aguarde um instante e recarregue.

O QUE MONITORAR NO DASHBOARD:
  - Status e Mapa: Uptime em tempo real, contagem de jogadores e mapa atual.
  - Consumo de Recursos: Métricas de CPU e RAM para monitorar a performance da máquina.
  - Terminal da Infraestrutura: Acompanhe o progresso real do download do SteamCMD.
  - Terminal do Servidor: Veja o boot do jogo assim que o download terminar.
  - Conexão Rápida: O comando 'connect' estará disponível no painel superior assim
    que o servidor estiver pronto.

SUPORTE E BACKUPS:
  - S3 (Skins/DB): https://s3.console.aws.amazon.com/s3/buckets/${module.storage.bucket_name}?region=${var.aws_region}
  - Acesso SSH: ssh -i cs2-server-key.pem ubuntu@${module.compute.public_ip}
  - Debug Manual: ssh -i cs2-server-key.pem ubuntu@${module.compute.public_ip} "tail -f /var/log/user-data.log"

EOT
}
