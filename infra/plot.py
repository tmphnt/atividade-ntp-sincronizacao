#!/usr/bin/env python3
"""plot.py — gera grafico de convergencia a partir dos CSVs coletados.

Uso: python3 plot.py logs/*.csv
Saida: ./convergencia.png (no diretorio atual)

Aluno nao deve modificar este script; plotagem nao e avaliada.
"""
import sys
from pathlib import Path
import csv
from datetime import datetime
import matplotlib.pyplot as plt

if len(sys.argv) < 2:
    sys.exit("Uso: python3 plot.py <csv1> [csv2 ...]")

fig, ax = plt.subplots(figsize=(10, 5))
for path in sys.argv[1:]:
    rows = list(csv.DictReader(open(path)))
    t0 = datetime.fromisoformat(rows[0]["timestamp"].replace(",", "."))
    xs = [(datetime.fromisoformat(r["timestamp"].replace(",", ".")) - t0).total_seconds() for r in rows]
    ys = [float(r["last_offset_s"]) * 1000 for r in rows if r["last_offset_s"]]
    ax.plot(xs[:len(ys)], ys, label=Path(path).stem.replace("offset-", ""))

ax.axhline(0, color="gray", linewidth=0.8)
ax.set_xlabel("Tempo desde o inicio (segundos)")
ax.set_ylabel("Last offset (milissegundos)")
ax.set_title("Convergencia do relogio sob NTP/chrony")
ax.legend()
ax.grid(True, alpha=0.3)
plt.tight_layout()
plt.savefig("convergencia.png", dpi=120)
print("Grafico salvo em ./convergencia.png")
