# CS2 Server Automation

![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)
![Grafana](https://img.shields.io/badge/grafana-%23F46800.svg?style=for-the-badge&logo=grafana&logoColor=white)
![CS2](https://img.shields.io/badge/Counter--Strike_2-FFA500?style=for-the-badge&logo=counter-strike&logoColor=white)

<div align="center">
  <h3>
    <a href="#-english">🇺🇸 English</a> | 
    <a href="#-português">🇧🇷 Português</a>
  </h3>
</div>

---

<div id="-english"></div>

## 🇺🇸 English

**CS2 server automated via Terraform and AWS CLI.**

This project implements a complete and **secure** infrastructure for hosting a Counter-Strike 2 server on AWS. Using **Infrastructure as Code (IaC)**, the project provisions not only the game server but also a full monitoring stack featuring a stateless architecture with data persistence.



### Overview

#### Security
This project uses Terraform to **detect your current public IP** at deployment time.
* **Closed Ports:** SSH (22), RCON, and Monitoring Dashboards are allowed **only** for your IP.
* **Public Ports:** Only the game port (27015/UDP) is open to the world.

#### Data Persistence
Infrastructure is ephemeral, but data is not.
* **S3 Bucket:** The Backup Bucket is created via AWS CLI (`local-exec`), ensuring it is **not destroyed** by `terraform destroy`.
* **Auto-Restore:** When a new instance launches, the script checks S3 and automatically restores the latest MySQL database dump containing player skins configurations.
* **Auto-Backup:** When shutting down the machine or restarting the service, a new backup is generated and sent to S3.

#### Observability
The server launches with a pre-configured Docker monitoring stack:
* **Grafana:** Visual dashboards accessible via browser.
* **Prometheus:** Real-time CPU, RAM, Network, and *Players Online* metrics.
* **Loki & Promtail:** Log ingestion. You can read the server console and installation logs directly in Grafana, without needing SSH.

#### Plugin Configuration
The provisioned server automatically downloads the latest versions of commonly used plugins. Furthermore, it resolves the classic conflict between plugins that interfere with CVARs and server variables through custom boot logic:
* **Competitive Mode (Default):** Managed by **MatchZy**.
* **Retake Mode:** Managed by **CS2-Retakes**.
* **Switching:** Players can type `!retake` or `!match` in chat. The server unloads conflicting plugins, modifies CVARs, and restarts the map automatically for a clean transition.

---

### Usage

#### Prerequisites
1.  [Terraform](https://www.terraform.io/) installed.
2.  [AWS CLI](https://aws.amazon.com/cli/) installed and configured (`aws configure`).
3.  Steam GSLT Token (AppID 730). ([Get it here](https://steamcommunity.com/dev/managegameservers))

#### Installation

1.  **Clone the repository:**
    ```bash
    git clone [https://github.com/YOUR_USER/CS2-Server-Automation.git](https://github.com/YOUR_USER/CS2-Server-Automation.git)
    cd CS2-Server-Automation
    ```

2.  **Configure Secret Variables:**
    Create a `terraform.tfvars` file in the project root.
    ```hcl
    aws_region          = "sa-east-1"      # Recommended for lower latency (e.g., in Brazil)
    instance_type       = "t3.medium"      # A larger instance may be required for better performance
    cs2_gslt_token      = "YOUR_STEAM_TOKEN_HERE"
    cs2_server_password = "server_password"
    db_password         = "secure_mysql_password"
    ```

3.  **Provision Infrastructure:**
    ```bash
    terraform init
    terraform apply
    ```

4.  **Wait for Installation:**
    The script will provision everything; game download time depends on AWS network speed. You can monitor the provisioning state via Grafana. Once finished, the server will indicate its status, and the connection IP will be available on the dashboard.

#### Accessing Monitoring
After the `terraform apply` command, the server IP will be displayed in the terminal.
The entire monitoring stack may take 1 to 3 minutes to come up; do not worry if the connection is initially rejected.
Access it in your browser using the command provided by Terraform (Login restricted to your IP).

---

### Custom Commands

Any connected player can use the following custom commands in the chat:

| Command | Function |
| :--- | :--- |
| `!retake` | Activates Retake mode. Restarts the map. |
| `!match` | Activates Competitive mode (MatchZy). Restarts the map. |

Other usable commands belong to their respective plugins (MatchZy, WeaponPaints).

---

### Project Structure

```text
.
├── main.tf                # Main infrastructure file: Defines EC2, Security Groups, IAM, and S3
├── variables.tf           # Variable definitions (Region, Instance Type, Passwords)
├── providers.tf           # AWS Provider configuration
├── outputs.tf             # Terraform Outputs (Displays Server IP at the end)
├── terraform.tfvars       # (GitIgnored) File where you insert your actual passwords and tokens
└── scripts/
    └── install_cs2.sh     # Automation script: Installs Monitoring, SteamCMD, CS2, Plugins, etc.
```

<br>
<div align="center">
  <a href="#-english">Back to Top</a>
</div>
<br>
<hr>

<div id="-português"></div>

## 🇧🇷 Português

**Servidor de CS2 automatizado via Terraform e AWS CLI.**

Este projeto implementa uma infraestrutura completa e **segura** para hospedar um servidor de Counter-Strike 2 na AWS. Utilizando **Infrastructure as Code (IaC)**, o projeto provisiona não apenas o servidor de jogo, mas uma stack completa de monitoramento com arquitetura stateless com persistência de dados.

### Overview

#### Segurança
Este projeto utiliza o Terraform para **detectar seu IP público atual** no momento do deploy.
* **Portas Fechadas:** SSH (22), RCON e Painéis de Monitoramento são liberados **apenas** para o seu IP.
* **Portas Públicas:** Apenas a porta do jogo (27015/UDP) é aberta para o mundo.

#### Persistência de dados
A infraestrutura é efêmera, mas os dados não.
* **Bucket S3:** O Bucket de backups é criado via AWS CLI (`local-exec`), garantindo que ele **não seja destruído** pelo `terraform destroy`.
* **Auto-Restore:** Ao subir uma nova máquina, o script verifica o S3 e restaura automaticamente o último dump do banco de dados MySQL que contém a configuração de skins de cada jogador.
* **Auto-Backup:** Ao desligar a máquina ou reiniciar o serviço, um backup novo é gerado e enviado para o S3.

#### Observabilidade
O servidor sobe com uma stack Docker de monitoramento pré-configurada:
* **Grafana:** Dashboards visuais acessíveis via navegador.
* **Prometheus:** Métricas de CPU, RAM, Rede e *Players Online* em tempo real.
* **Loki & Promtail:** Ingestão de logs. Você pode ler o console do servidor e logs de instalação direto no Grafana, sem precisar de SSH.

#### Configuração dos plugins
O servidor provisionado realiza automaticamente o download mais recente dos plugins comumente utilizados, além disso o servidor resolve o conflito clássico entre plugins que interferem com cvars e alteração de variáveis do servidor através de uma lógica customizada de boot:
* **Modo Competitivo (Padrão):** Gerenciado pelo **MatchZy**.
* **Modo Retake:** Gerenciado pelo **CS2-Retakes**.
* **Troca:** Jogadores podem digitar `!retake` ou `!match` no chat. O servidor descarrega os plugins conflitantes, altera as CVARs e reinicia o mapa automaticamente para uma transição limpa.

---

### Como Usar

#### Pré-requisitos
1.  [Terraform](https://www.terraform.io/) instalado.
2.  [AWS CLI](https://aws.amazon.com/cli/) instalado e configurado (`aws configure`).
3.  Token GSLT da Steam (AppID 730). (https://steamcommunity.com/dev/managegameservers)

#### Instalação

1.  **Clone o repositório:**
    ```bash
    git clone [https://github.com/SEU_USUARIO/CS2-Server-Automation.git](https://github.com/SEU_USUARIO/CS2-Server-Automation.git)
    cd CS2-Server-Automation
    ```

2.  **Configure as Variáveis Secretas:**
    Crie um arquivo chamado `terraform.tfvars` na raiz do projeto.
    ```hcl
    aws_region          = "sa-east-1"      # Recomendado para menor latência no BR
    instance_type       = "t3.medium"       # Pode ser necessário uma instância mais parruda, para melhor desempenho
    cs2_gslt_token      = "SEU_TOKEN_STEAM_AQUI"
    cs2_server_password = "senha_do_servidor"
    db_password         = "senha_segura_mysql"
    ```

3.  **Provisione a Infraestrutura:**
    ```bash
    terraform init
    terraform apply
    ```

4.  **Aguarde a Instalação:**
    O script provisionará tudo, o download do jogo depende da rede da AWS. É possível monitorar o estado do provisionamento através do Grafana, ao final o servidor indicará seu status e o IP de conexão estará disponivel no dashboard.

#### Acessando o Monitoramento
Após o comando `terraform apply`, o IP do servidor será exibido no terminal.
Toda a stack de monitoramento pode demorar de 1 a 3 minutos para subir, não se preocupe com a conexão rejeitada.
Acesse no seu navegador com o comando fornecido pelo terraform (Login restrito ao seu IP).

---

### Comandos Customizados

Qualquer jogador conectado pode utilizar os comandos customizados abaixo no chat:

| Comando | Função |
| :--- | :--- |
| `!retake` | Ativa o modo Retake. Reinicia o mapa. |
| `!match` | Ativa o modo Competitivo (MatchZy). Reinicia o mapa. |

Os demais comandos utilizáveis pertencem aos respectivos plugins (MatchZy, WeaponPaints).

---

## Estrutura do Projeto

```text
.
├── main.tf                # Arquivo da infraestrutura principal: Define EC2, Security Groups, IAM e S3
├── variables.tf           # Definição das variáveis (Região, Tipo de Instância, Senhas)
├── providers.tf           # Configuração do provedor AWS
├── outputs.tf             # Outputs do Terraform (Exibe o IP do servidor ao final)
├── terraform.tfvars       # (Ignorado pelo Git) Arquivo onde você insere suas senhas e tokens reais
└── scripts/
    └── install_cs2.sh     # O script da automação: Instala Monitoramento, SteamCMD, CS2, Plugins, etc.

### Licença / License

This project is Open Source under the MIT license.