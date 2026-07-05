#!/usr/bin/env bash
# launch-part-b.sh — acrescenta ntp-cliente-slew via clone do template.
# Pre-req: launch.sh ja rodou (ntp-template + ntp-servidor existem).
# Uso: ./launch-part-b.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\033[1;34m[launch-b]\033[0m %s\n' "$*"; }

if ! multipass info ntp-template >/dev/null 2>&1; then
  echo "Erro: ntp-template nao existe. Rode launch.sh primeiro." >&2
  exit 1
fi
if ! multipass info ntp-servidor >/dev/null 2>&1; then
  echo "Erro: ntp-servidor nao existe. Rode launch.sh primeiro." >&2
  exit 1
fi

# Template precisa estar stopped para clone.
STATE=$(multipass info ntp-template --format csv | awk -F',' 'NR==2 {print $2}')
if [ "${STATE}" != "Stopped" ]; then
  multipass stop ntp-template
fi

if ! multipass info ntp-cliente-slew >/dev/null 2>&1; then
  log "Clonando ntp-template -> ntp-cliente-slew..."
  multipass clone ntp-template --name ntp-cliente-slew
fi

STATE=$(multipass info ntp-cliente-slew --format csv | awk -F',' 'NR==2 {print $2}')
if [ "${STATE}" != "Running" ]; then
  log "Iniciando ntp-cliente-slew..."
  multipass start ntp-cliente-slew
fi

SERVIDOR_IP=$(multipass info ntp-servidor --format csv | awk -F',' 'NR==2 {print $3}')
log "Servidor em ${SERVIDOR_IP}"

"${HERE}/apply-role.sh" ntp-cliente-slew cliente-slew "${SERVIDOR_IP}"
"${HERE}/inject-drift.sh" ntp-cliente-slew +60

log "Parte B pronta. Slew puro leva ~30 min para 60s. Aguarde antes de coletar."
