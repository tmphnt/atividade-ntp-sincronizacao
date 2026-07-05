#!/usr/bin/env bash
# launch.sh — sobe Parte A via clone do ntp-template.
#
# Fluxo:
#   1. Garante que ntp-template existe (cria se faltante; chrony instalado).
#   2. Para o template (clone exige source stopped).
#   3. Clona em ntp-servidor + ntp-cliente-1 + ntp-cliente-2.
#   4. Inicia os clones.
#   5. Aplica papeis (chrony.conf correto) via apply-role.sh.
#   6. Injeta drift nos clientes.
#
# Uso: ./launch.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA="$(cd "${HERE}/.." && pwd)"

log() { printf '\033[1;34m[launch]\033[0m %s\n' "$*"; }

wait_cloud_init_done() {
  local VM="$1"
  local MAX=120
  echo "[launch] aguardando cloud-init em ${VM}..."
  for i in $(seq 1 ${MAX}); do
    local OUT
    OUT=$(timeout 10 multipass exec "${VM}" -- cloud-init status 2>/dev/null || echo "")
    case "${OUT}" in
      *"status: done"*|*"status: error"*) return 0 ;;
    esac
    sleep 3
  done
  echo "[launch] timeout aguardando cloud-init em ${VM}" >&2
  return 1
}

# 1. Template
if ! multipass info ntp-template >/dev/null 2>&1; then
  log "Subindo ntp-template..."
  multipass launch 22.04 --name ntp-template --cpus 1 --memory 512M --disk 3G \
    --timeout 600 --cloud-init "${INFRA}/cloud-init/template.yaml"
  wait_cloud_init_done ntp-template
  log "Parando ntp-template..."
  multipass stop ntp-template
else
  log "ntp-template ja existe."
  # Garante stopped antes do clone.
  STATE=$(multipass info ntp-template --format csv | awk -F',' 'NR==2 {print $2}')
  if [ "${STATE}" != "Stopped" ]; then
    multipass stop ntp-template
  fi
fi

# 2. Clones
clone_if_missing() {
  local NAME="$1"
  if ! multipass info "${NAME}" >/dev/null 2>&1; then
    log "Clonando ntp-template -> ${NAME}..."
    multipass clone ntp-template --name "${NAME}"
  else
    log "${NAME} ja existe; pulando clone."
  fi
}

clone_if_missing ntp-servidor
clone_if_missing ntp-cliente-1
clone_if_missing ntp-cliente-2

# 3. Start
for VM in ntp-servidor ntp-cliente-1 ntp-cliente-2; do
  STATE=$(multipass info "${VM}" --format csv | awk -F',' 'NR==2 {print $2}')
  if [ "${STATE}" != "Running" ]; then
    log "Iniciando ${VM}..."
    multipass start "${VM}"
  fi
done

# 4. Descobre IP do servidor
SERVIDOR_IP=$(multipass info ntp-servidor --format csv | awk -F',' 'NR==2 {print $3}')
log "Servidor em ${SERVIDOR_IP}"

# 5. Aplica papeis
"${HERE}/apply-role.sh" ntp-servidor   servidor
"${HERE}/apply-role.sh" ntp-cliente-1  cliente  "${SERVIDOR_IP}"
"${HERE}/apply-role.sh" ntp-cliente-2  cliente  "${SERVIDOR_IP}"

# 6. Drift
"${HERE}/inject-drift.sh" ntp-cliente-1 +30
"${HERE}/inject-drift.sh" ntp-cliente-2 -45

log "Parte A pronta. Inspecione: multipass exec ntp-cliente-1 -- chronyc tracking"
