#!/usr/bin/env bash
# inject-drift.sh — desalinha o relogio de uma VM por OFFSET segundos.
#
# Por que o passo `set-ntp false` e necessario:
# systemd-timedated recusa qualquer tentativa de mudar o relogio enquanto
# NTP estiver ativo. Esse e o momento didatico mencionado no README.
#
# Uso: ./inject-drift.sh <vm> <offset-segundos>
# Exemplo: ./inject-drift.sh ntp-cliente-1 +30
#          ./inject-drift.sh ntp-cliente-2 -45

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Uso: $0 <vm-name> <offset-segundos>" >&2
  exit 1
fi

VM="$1"
OFFSET="$2"

log() { printf '\033[1;33m[drift]\033[0m %s\n' "$*"; }

log "Parando chrony em ${VM}..."
multipass exec "${VM}" -- sudo systemctl stop chrony

log "Desabilitando NTP no systemd-timedated..."
multipass exec "${VM}" -- sudo timedatectl set-ntp false

# Calcula novo tempo. Aceita OFFSET com sinal (+30, -45, 30).
# Detecta GNU date (Linux, Git Bash no Windows) vs BSD date (macOS).
if date --version >/dev/null 2>&1; then
  # GNU date: aceita "+30 seconds" ou "-45 seconds" diretamente.
  NOVO=$(date -u -d "${OFFSET} seconds" '+%Y-%m-%d %H:%M:%S')
else
  # BSD date (macOS): precisa sinal SEM duplicacao.
  # Garante exatamente um sinal no inicio: remove + se houver, depois prefixa.
  CLEAN="${OFFSET#+}"   # remove + leading se existir
  case "${CLEAN}" in
    -*) ARG="${CLEAN}S" ;;   # ja tem - (negativo)
    *)  ARG="+${CLEAN}S" ;;  # positivo: prefixa +
  esac
  NOVO=$(date -u -v "${ARG}" '+%Y-%m-%d %H:%M:%S')
fi
log "Aplicando offset ${OFFSET}s em ${VM} (novo tempo UTC: ${NOVO})..."
multipass exec "${VM}" -- sudo timedatectl set-time "${NOVO}"

log "Reiniciando chrony em ${VM}..."
multipass exec "${VM}" -- sudo systemctl start chrony

log "Drift aplicado. Inspecione com: multipass exec ${VM} -- chronyc tracking"
