# Link direto para o Monitoramento
output "grafana_url" {
  description = "URL para acompanhar o build e a saúde do servidor"
  value       = "http://${aws_instance.cs2_server.public_ip}:3000"
}

# Comando para conexão direta no game com suporte a senha
output "cs2_connect_command" {
  description = "Comando para conectar no server"
  value       = var.cs2_server_password != "" ? "connect ${aws_instance.cs2_server.public_ip}:27015; password ${var.cs2_server_password}" : "connect ${aws_instance.cs2_server.public_ip}:27015"
}

# Mensagem Informativa Consolidada
output "instrucoes_finais" {
  description = "Instruções de acompanhamento"
  value       = <<EOT

SERVIDOR DE CS2 EM PROVISIONAMENTO

A infraestrutura foi criada com sucesso. Agora o servidor está instalando 
as dependências e baixando os arquivos do jogo.

ACOMPANHE EM TEMPO REAL:
  Acesse o Grafana: http://${aws_instance.cs2_server.public_ip}:3000
  Vá em 'Explore' e selecione o log 'installation_logs' para ver o build

Comando de conexão do server:
  ${var.cs2_server_password != "" ? "connect ${aws_instance.cs2_server.public_ip}:27015; password ${var.cs2_server_password}" : "connect ${aws_instance.cs2_server.public_ip}:27015"}

Backups das configurações de skins é armazenado em:
   https://s3.console.aws.amazon.com/s3/buckets/${local.bucket_name}?region=${var.aws_region}

Caso precise acessar a máquina via SSH, utilize:
  Comando: ssh -i cs2-server-key.pem ubuntu@${aws_instance.cs2_server.public_ip}
   Logs: ssh -i cs2-server-key.pem ubuntu@${aws_instance.cs2_server.public_ip} "tail -f /var/log/user-data.log"

O tempo de download depende da rede da AWS.
EOT
}