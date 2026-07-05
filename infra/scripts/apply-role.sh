#!/usr/bin/env bash
# apply-role.sh — aplica papel (servidor / cliente / cliente-slew) a uma VM
# ja clonada de ntp-template.
#
# Uso: ./apply-role.sh <vm> <servidor|cliente|cliente-slew> [servidor-ip]
# Exemplos:
#   ./apply-role.sh ntp-servidor    servidor
#   ./apply-role.sh ntp-cliente-1   cliente       192.168.252.10
#   ./apply-role.sh ntp-cliente-slew cliente-slew 192.168.252.10

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Uso: $0 <vm> <servidor|cliente|cliente-slew> [servidor-ip]" >&2
  exit 1
fi

VM="$1"
ROLE="$2"
SERVIDOR_IP="${3:-}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA="$(cd "${HERE}/.." && pwd)"

case "${ROLE}" in
  servidor)       CONF="${INFRA}/chrony/chrony-servidor.conf" ;;
  cliente)        CONF="${INFRA}/chrony/chrony-cliente.conf" ;;
  cliente-slew)   CONF="${INFRA}/chrony/chrony-cliente-slew.conf" ;;
  *)              echo "Papel desconhecido: ${ROLE}" >&2; exit 1 ;;
esac

log() { printf '\033[1;36m[role]\033[0m %s\n' "$*"; }

# Substitui SERVIDOR_IP se aplicavel.
TMP=$(mktemp)
trap 'rm -f "${TMP}"' EXIT
if [ -n "${SERVIDOR_IP}" ]; then
  sed "s/SERVIDOR_IP/${SERVIDOR_IP}/g" "${CONF}" > "${TMP}"
else
  cp "${CONF}" "${TMP}"
fi

log "${VM}: instalando chrony.conf (papel: ${ROLE})..."
multipass transfer "${TMP}" "${VM}:/tmp/chrony.conf"
multipass exec "${VM}" -- sudo mv /tmp/chrony.conf /etc/chrony/chrony.conf
multipass exec "${VM}" -- sudo chown root:root /etc/chrony/chrony.conf
multipass exec "${VM}" -- sudo chmod 644 /etc/chrony/chrony.conf

log "${VM}: reiniciando chrony e log-offset..."
multipass exec "${VM}" -- sudo systemctl restart chrony
multipass exec "${VM}" -- sudo systemctl enable --now log-offset.service

log "${VM}: papel ${ROLE} aplicado."
