#!/usr/bin/env bash
# Adiciona um projeto ao deploy-service.
# Uso: ./add-project.sh <VPS_HOST> <github-user/repo> <deploy-script-path> [branch]
# Exemplo: ./add-project.sh 46.202.147.81 leogaldioli/clube-patinep /opt/clube-patinep/deploy.sh
set -euo pipefail

VPS_HOST="${1:?Uso: ./add-project.sh <VPS_HOST> <github-user/repo> <deploy-script>}"
REPO="${2:?Informe o repo (ex: leogaldioli/clube-patinep)}"
DEPLOY_SCRIPT="${3:?Informe o path do deploy script na VPS}"
BRANCH="${4:-main}"
VPS_USER="${VPS_USER:-root}"

DEPLOY_DIR=$(dirname "$DEPLOY_SCRIPT")

echo "=== Adicionando projeto ==="
echo "Repo: $REPO"
echo "Script: $DEPLOY_SCRIPT"
echo "Branch: $BRANCH"
echo ""

# Gera secret e adiciona ao projects.json na VPS
SECRET=$(ssh "${VPS_USER}@${VPS_HOST}" "python3 -c \"import secrets; print(secrets.token_hex(32))\"")

ssh "${VPS_USER}@${VPS_HOST}" python3 - "$REPO" "$SECRET" "$DEPLOY_SCRIPT" "$BRANCH" "$DEPLOY_DIR" <<'PYSCRIPT'
import json, sys

repo = sys.argv[1]
secret = sys.argv[2]
script = sys.argv[3]
branch = sys.argv[4]
deploy_dir = sys.argv[5]

config_file = "/opt/webhook/projects.json"
try:
    with open(config_file) as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {}

cfg[repo] = {
    "secret": secret,
    "deploy_script": script,
    "branch": branch,
    "log_file": f"{deploy_dir}/deploy.log"
}

with open(config_file, "w") as f:
    json.dump(cfg, f, indent=2)

print(f"Projeto {repo} adicionado ao projects.json")
PYSCRIPT

# Restart webhook para carregar config
ssh "${VPS_USER}@${VPS_HOST}" "systemctl restart deploy-service && sleep 1 && curl -s http://127.0.0.1:9876/health"

echo ""
echo "=== Configurar webhook no GitHub ==="
echo ""
echo "Va em: https://github.com/${REPO}/settings/hooks/new"
echo ""
echo "  Payload URL: http://${VPS_HOST}:9876/deploy"
echo "  Content type: application/json"
echo "  Secret: ${SECRET}"
echo "  Events: Just the push event"
echo ""
echo "Ou rode (requer gh CLI):"
echo ""
echo "  gh api repos/${REPO}/hooks --method POST \\"
echo "    -f name=web \\"
echo "    -f 'config[url]=http://${VPS_HOST}:9876/deploy' \\"
echo "    -f 'config[content_type]=json' \\"
echo "    -f 'config[secret]=${SECRET}' \\"
echo "    -f 'events[]=push' \\"
echo "    -F 'active=true'"
