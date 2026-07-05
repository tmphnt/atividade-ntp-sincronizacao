#!/usr/bin/env bash
# log-offset.sh — copia de referencia do logger CSV (a versao em uso roda
# DENTRO de cada VM, instalada via cloud-init em /usr/local/bin/log-offset.sh).
#
# Mantida aqui para inspecao pelo aluno (Nivel 1) sem precisar entrar na VM.

HOSTNAME=$(hostname)
CSV=/var/log/chrony/offset-${HOSTNAME}.csv

if [ ! -f "$CSV" ]; then
  echo "timestamp,last_offset_s,rms_offset_s,frequency_ppm" > "$CSV"
fi

while true; do
  TS=$(date -Ins)
  LINE=$(chronyc tracking 2>/dev/null | awk -F': *' '
    /Last offset/    {gsub(/ seconds/, "", $2); lo=$2}
    /RMS offset/     {gsub(/ seconds/, "", $2); ro=$2}
    /Frequency/      {split($2, a, " "); f=a[1]; if (a[2]=="ppm" && a[3]=="slow") f=-f; }
    END {print lo "," ro "," f}')
  echo "${TS},${LINE}" >> "$CSV"
  sleep 1
done
