#!/usr/bin/env bash
# Setup do deploy-service na VPS.
# Uso: ./setup.sh <VPS_HOST> [VPS_USER]
set -euo pipefail

VPS_HOST="${1:?Uso: ./setup.sh <VPS_HOST> [VPS_USER]}"
VPS_USER="${2:-root}"
REMOTE_PATH="/opt/webhook"

echo "=== deploy-service setup ==="
echo "VPS: ${VPS_USER}@${VPS_HOST}"
echo ""

# Envia arquivos
echo "Enviando arquivos para VPS..."
ssh "${VPS_USER}@${VPS_HOST}" "mkdir -p ${REMOTE_PATH}"
scp webhook-server.py deploy-service.service "${VPS_USER}@${VPS_HOST}:${REMOTE_PATH}/"

# Cria projects.json se nao existir
ssh "${VPS_USER}@${VPS_HOST}" bash -s <<'REMOTE'
REMOTE_PATH="/opt/webhook"

if [ ! -f "${REMOTE_PATH}/projects.json" ]; then
  echo '{}' > "${REMOTE_PATH}/projects.json"
  chmod 600 "${REMOTE_PATH}/projects.json"
  echo "projects.json criado (vazio)"
else
  echo "projects.json ja existe, mantendo"
fi

# Instala systemd service
cp "${REMOTE_PATH}/deploy-service.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now deploy-service

sleep 2
echo ""
systemctl status deploy-service --no-pager | head -10
echo ""
curl -s http://127.0.0.1:9876/health
echo ""
REMOTE

echo ""
echo "Setup concluido!"
echo ""
echo "Proximo passo: adicione projetos com:"
echo "  ./add-project.sh <VPS_HOST> <github-user/repo> <deploy-script-path>"
