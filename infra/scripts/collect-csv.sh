#!/usr/bin/env bash
# collect-csv.sh — transfere os CSVs de cada VM para ./logs/ no host.
#
# Uso: ./collect-csv.sh
# Coleta de todas as VMs ntp-* existentes (servidor + clientes).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTIVITY_ROOT="$(cd "${HERE}/../.." && pwd)"
LOGS_DIR="${ACTIVITY_ROOT}/logs"
mkdir -p "${LOGS_DIR}"

log() { printf '\033[1;32m[collect]\033[0m %s\n' "$*"; }

VMS=$(multipass list --format csv | awk -F',' 'NR>1 && $1 ~ /^ntp-/ {print $1}')

if [ -z "${VMS}" ]; then
  echo "Nenhuma VM ntp-* encontrada." >&2
  exit 1
fi

for VM in ${VMS}; do
  CSV_REMOTO="/var/log/chrony/offset-${VM}.csv"
  CSV_LOCAL="${LOGS_DIR}/offset-${VM}.csv"
  if multipass exec "${VM}" -- test -f "${CSV_REMOTO}"; then
    # Multipass transfer nao tem permissao para /var/log/chrony, entao
    # copiamos via cat redirecionado.
    multipass exec "${VM}" -- sudo cat "${CSV_REMOTO}" > "${CSV_LOCAL}"
    LINHAS=$(wc -l < "${CSV_LOCAL}")
    log "${VM}: ${LINHAS} linhas -> ${CSV_LOCAL}"
  else
    echo "Aviso: ${CSV_REMOTO} ausente em ${VM}." >&2
  fi
done

log "Coleta concluida em ${LOGS_DIR}"
