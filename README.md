# deploy-service

Webhook server self-hosted que substitui GitHub Actions para deploys em VPS propria. Zero custo, sem limites de minutos, sem dependencia de servicos externos.

Um unico server atende multiplos projetos/repos.

## Como funciona

```
Push no GitHub → Webhook POST → deploy-service (VPS:9876) → deploy.sh do projeto
```

1. Voce faz push no `main`
2. GitHub envia um POST para `http://<VPS>:9876/deploy`
3. O deploy-service identifica o repo, valida a assinatura HMAC-SHA256, e executa o deploy script do projeto
4. O deploy script faz `git pull` + `docker build` + `docker compose up`

## Seguranca

- **HMAC-SHA256** — cada projeto tem seu secret. Requests sem assinatura valida sao rejeitados (403)
- **Secret por projeto** — comprometimento de um secret nao afeta outros projetos
- **Payload ignorado** — o deploy script faz `git pull` do repo hardcoded, nao executa nada do payload
- **Lock file** — evita deploys simultaneos do mesmo projeto

## Setup rapido

### 1. Instalar na VPS

```bash
git clone https://github.com/leogaldioli/deploy-service.git
cd deploy-service
chmod +x setup.sh add-project.sh
./setup.sh <VPS_IP>
```

### 2. Configurar git credentials (para repos privados)

Na VPS, configure um [Personal Access Token](https://github.com/settings/tokens) do GitHub:

```bash
ssh root@<VPS_IP>
git config --global credential.helper store
echo 'https://<GITHUB_USER>:<PAT>@github.com' > ~/.git-credentials
chmod 600 ~/.git-credentials
```

### 3. Adicionar um projeto

```bash
./add-project.sh <VPS_IP> <github-user/repo> <deploy-script-path>
```

Exemplo:

```bash
./add-project.sh 46.202.147.81 leogaldioli/clube-patinep /opt/clube-patinep/deploy.sh
```

O script gera o secret, adiciona ao `projects.json`, e mostra o comando `gh` para criar o webhook no GitHub.

### 4. Criar o deploy script do projeto

Copie e adapte o template:

```bash
cp templates/deploy.sh.template /opt/meu-projeto/deploy.sh
chmod +x /opt/meu-projeto/deploy.sh
# Edite as variaveis no topo do arquivo
```

## Estrutura na VPS

```
/opt/webhook/                    # deploy-service (centralizado)
  webhook-server.py              # servidor webhook
  projects.json                  # config de todos os projetos
  webhook.log                    # log geral do webhook
  deploy-service.service         # systemd unit

/opt/meu-projeto/                # cada projeto
  deploy.sh                      # script de deploy especifico
  deploy.log                     # log de deploy do projeto
  repo/                          # clone do repo (criado automaticamente)
  .env.production                # env vars de runtime
  docker-compose.prod.yml        # compose file
```

## projects.json

```json
{
  "leogaldioli/clube-patinep": {
    "secret": "abc123...",
    "deploy_script": "/opt/clube-patinep/deploy.sh",
    "branch": "main",
    "log_file": "/opt/clube-patinep/deploy.log"
  },
  "leogaldioli/outro-app": {
    "secret": "def456...",
    "deploy_script": "/opt/outro-app/deploy.sh",
    "branch": "main",
    "log_file": "/opt/outro-app/deploy.log"
  }
}
```

## Deploy manual (sem webhook)

Para deploys urgentes ou quando o webhook nao esta disponivel, use o template de deploy local:

```bash
cp templates/deploy-local.sh.template scripts/deploy.sh
chmod +x scripts/deploy.sh
# Edite as variaveis no topo

./scripts/deploy.sh              # com testes
./scripts/deploy.sh --skip-tests # urgente
```

Este script empacota o codigo, envia via SCP para a VPS, builda e deploya — tudo sem precisar de Docker local.

## Endpoints

| Rota | Metodo | Descricao |
|------|--------|-----------|
| `/deploy` | POST | Recebe webhook do GitHub |
| `/health` | GET | Health check — retorna projetos configurados |

## Comandos uteis

```bash
# Ver status do servico
ssh root@<VPS> "systemctl status deploy-service"

# Ver logs do webhook
ssh root@<VPS> "tail -50 /opt/webhook/webhook.log"

# Ver logs de deploy de um projeto
ssh root@<VPS> "tail -50 /opt/meu-projeto/deploy.log"

# Restart do servico
ssh root@<VPS> "systemctl restart deploy-service"

# Testar health
curl http://<VPS>:9876/health
```

## Requisitos da VPS

- Python 3 (sem dependencias externas)
- Docker + Docker Compose
- Git
- systemd
