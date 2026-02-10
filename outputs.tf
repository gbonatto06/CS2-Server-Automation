# Link direto para o Monitoramento em modo
output "grafana_url" {
  description = "URL para acompanhar o build e a saúde do servidor (Kiosk Mode)"
  # Utilizamos o UID 'cs2_01' definido JSON do dashboard
  value       = "http://${aws_instance.cs2_server.public_ip}:3000/d/cs2_01/servidor-de-cs2?kiosk=1"
}

# Mensagem Informativa Consolidada
output "instrucoes_finais" {
  description = "Instruções de acompanhamento do provisionamento"
  value       = <<EOT

SERVIDOR DE CS2 EM PROVISIONAMENTO

A infraestrutura na AWS foi criada com sucesso! O servidor agora está configurando 
o ambiente virtual Python, instalando a stack de monitoramento e baixando o jogo.

ACOMPANHE TUDO PELO GRAFANA:
  Link Direto: http://${aws_instance.cs2_server.public_ip}:3000/d/cs2_01/servidor-de-cs2?kiosk=1

IMPORTANTE - DELAY DE INICIALIZAÇÃO:
  O Grafana pode levar de 1 a 2 minutos para carregar plugins e banco de dados interno.
  Caso o link acima retorne erro de conexão inicialmente, aguarde um instante e recarregue.

O QUE MONITORAR NO DASHBOARD:
  - Terminal da Infraestrutura: Acompanhe o progresso real do download do SteamCMD.
  - Terminal do Servidor: Veja o boot do jogo assim que o download terminar.
  - Botão de Conexão: O comando 'connect' estará disponível no painel superior assim 
    que o servidor estiver pronto.

SUPORTE E BACKUPS:
  - S3 (Skins/DB): https://s3.console.aws.amazon.com/s3/buckets/${local.bucket_name}?region=${var.aws_region}
  - Acesso SSH: ssh -i cs2-server-key.pem ubuntu@${aws_instance.cs2_server.public_ip}
  - Debug Manual: ssh -i cs2-server-key.pem ubuntu@${aws_instance.cs2_server.public_ip} "tail -f /var/log/user-data.log"

EOT
}