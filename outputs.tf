# IP Público do Servidor
output "server_public_ip" {
  description = "IP Público do servidor de CS2"
  value       = aws_instance.cs2_server.public_ip
}

# Comando para conexão no game
output "cs2_connect_command" {
  description = "Comando para conectar no server"
  value       = "connect ${aws_instance.cs2_server.public_ip}:27015"
}

# Comando de Acesso SSH
output "ssh_connection_command" {
  description = "Comando para acessar o servidor via terminal"
  value       = "ssh -i cs2-server-key.pem ubuntu@${aws_instance.cs2_server.public_ip}"
}

# Mensagem Informativa de Pós-Instalação
output "instrucoes_finais" {
  description = "Passos para verificar se o servidor está pronto"
  value       = <<EOT

SERVIDOR DE CS2 EM PROVISIONAMENTO

A infraestrutura foi criada, mas o download do jogo está ocorrendo.
Aguarde de 15 a 20 minutos para que o processo seja concluído.

Para acompanhar o progresso da instalação em tempo real, execute:
  ssh -i cs2-server-key.pem ubuntu@${aws_instance.cs2_server.public_ip} "tail -f /var/log/user-data.log"

Quando o log exibir "Processo finalizado", você poderá conectar com:
  Comando: connect ${aws_instance.cs2_server.public_ip}:27015

Backups das configurações de skin:
  Os backups do banco de dados serão salvos ao desligar o servidor em:
  https://s3.console.aws.amazon.com/s3/buckets/${local.bucket_name}?region=${var.aws_region}
EOT
}