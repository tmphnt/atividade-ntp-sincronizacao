#!/usr/bin/env bash
# destroy.sh — derruba VMs ntp-servidor e ntp-cliente-* (preserva template).
# Para limpar incluindo o template, use 'make purge'.
#
# Uso: ./destroy.sh

set -euo pipefail

log() { printf '\033[1;31m[destroy]\033[0m %s\n' "$*"; }

# Coleta todas VMs ntp-* EXCETO ntp-template.
VMS=$(multipass list --format csv | awk -F',' 'NR>1 && $1 ~ /^ntp-/ && $1 != "ntp-template" {print $1}')

if [ -z "${VMS}" ]; then
  log "Nenhuma VM ntp-* (alem do template) encontrada. Nada a fazer."
  exit 0
fi

for VM in ${VMS}; do
  log "Removendo ${VM}..."
  multipass delete "${VM}"
done

multipass purge
log "VMs removidas. Template preservado (use 'make purge' para remover tudo)."
