# Makefile — atividade NTP/chrony sobre Multipass.
#
# Targets:
#   make up       sobe 3 VMs (1 servidor + 2 clientes) e injeta drift.
#   make up-b     acrescenta a 4a VM (cliente-slew) para Parte B.
#   make logs     coleta os CSVs das VMs para ./logs/.
#   make plot     gera grafico convergencia.png a partir dos CSVs.
#   make down     pausa as VMs sem destruir (multipass stop).
#   make clean    destroi tudo (multipass delete + purge + remove ./logs/).

SHELL := /usr/bin/env bash
SCRIPTS := infra/scripts
PYTHON ?= python3

.PHONY: up up-b logs plot down clean purge help

help:
	@echo "Targets disponiveis:"
	@echo "  make up       sobe Parte A (1 servidor + 2 clientes)"
	@echo "  make up-b     acrescenta cliente-slew (Parte B)"
	@echo "  make logs     coleta CSVs das VMs para ./logs/"
	@echo "  make plot     gera grafico convergencia.png"
	@echo "  make down     pausa as VMs (sem destruir)"
	@echo "  make clean    destroi VMs (preserva template; re-run rapido)"
	@echo "  make purge    destroi TUDO incluindo template"

up:
	@$(SCRIPTS)/launch.sh

up-b:
	@$(SCRIPTS)/launch-part-b.sh

logs:
	@$(SCRIPTS)/collect-csv.sh

plot: logs
	@$(PYTHON) infra/plot.py logs/*.csv

down:
	@for vm in $$(multipass list --format csv | awk -F',' 'NR>1 && $$1 ~ /^ntp-/ {print $$1}'); do \
	  echo "[down] pausando $$vm..."; \
	  multipass stop $$vm; \
	done

clean:
	@$(SCRIPTS)/destroy.sh
	@rm -rf logs
	@echo "[clean] logs/ removido. Template preservado."

purge:
	@for vm in $$(multipass list --format csv | awk -F',' 'NR>1 && $$1 ~ /^ntp-/ {print $$1}'); do \
	  echo "[purge] removendo $$vm..."; \
	  multipass delete $$vm; \
	done
	@multipass purge
	@rm -rf logs
	@echo "[purge] tudo removido (inclusive ntp-template)."
