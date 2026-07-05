# Atividade Prática: Sincronização de Relógios com NTP/chrony

## Pré-requisitos

- [Git](https://git-scm.com/)
- [Multipass](https://multipass.run/) — máquinas virtuais Ubuntu leves
- Python 3 com `matplotlib` no host (apenas para gerar os gráficos)

Verifique com:

```bash
multipass version
python3 -c "import matplotlib; print(matplotlib.__version__)"
```

**Instalação do Multipass:**
- macOS: `brew install --cask multipass`
- Linux: `sudo snap install multipass`
- Windows: instalador em https://multipass.run/install

> **Nota:** Não é necessário instalar `chrony` no seu host. Cada VM provisionada por esta atividade instala sua própria cópia automaticamente via cloud-init.

---

## Material Teórico

Os slides do professor são a fonte principal e podem ser encontrados no Moodle da disciplina; o [arquivo de contexto teórico](./contexto-teorico.md) é um complemento.

---

## Contexto histórico

Em 1985, David Mills propôs o **Network Time Protocol (NTP)** em uma rede em que a Internet ainda mal existia. Quatro décadas depois, o NTP continua sendo o protocolo dominante de sincronização de relógios em servidores Linux, roteadores, smartphones e satélites. Poucos protocolos sobreviveram tanto sem precisar ser substituídos.

Sincronizar relógios distribuídos parece simples — "todos olham para o mesmo servidor" — mas não é. Cada pacote NTP atravessa uma rede com atraso variável e potencialmente assimétrico. Cada relógio físico tem desvio próprio. Saltos abruptos no tempo quebram TTLs, certificados e logs ordenados. Esta atividade coloca você frente a frente com essas dificuldades em pequena escala, usando o `chrony` (o daemon NTP padrão em Ubuntu e RHEL) sobre VMs reais — não contêineres, porque contêineres compartilham o relógio do hospedeiro e não permitem o tipo de desalinhamento que queremos observar.

---

## Objetivos

Ao final desta atividade, você será capaz de:

1. Explicar o que são **offset**, **RTT**, **dispersão** e **stratum**, e por que cada um é uma métrica de qualidade da fonte de tempo.
2. Distinguir as duas estratégias de correção de relógio — **step** (salto) e **slew** (deslizamento) — e justificar quando cada uma é apropriada em produção.
3. Observar empiricamente a **convergência** de relógios desalinhados sob um protocolo de sincronização real e medir o tempo dessa convergência.
4. Reconhecer por que sistemas distribuídos modernos (TrueTime no Spanner, HLC no CockroachDB, PTP em finanças, NTS contra spoofing) continuam investindo em sincronização de relógios, mesmo com NTP há quatro décadas no campo.

---

## Estrutura do projeto

```
atividade-ntp-sincronizacao/
├── Makefile                      ← targets: up, up-b, logs, plot, down, clean
├── infra/
│   ├── cloud-init/               ← provisionamento declarativo por papel
│   │   ├── servidor.yaml
│   │   ├── cliente-step.yaml
│   │   └── cliente-slew.yaml
│   ├── chrony/                   ← configurações de chrony (servidor x cliente x slew puro)
│   │   ├── chrony-servidor.conf
│   │   ├── chrony-cliente.conf
│   │   └── chrony-cliente-slew.conf
│   ├── scripts/                  ← orquestração via multipass
│   │   ├── launch.sh
│   │   ├── launch-part-b.sh
│   │   ├── inject-drift.sh
│   │   ├── log-offset.sh
│   │   ├── collect-csv.sh
│   │   └── destroy.sh
│   └── plot.py                   ← matplotlib, ≤30 linhas (não modificar)
└── logs/                         ← criado em runtime; CSVs coletados das VMs
```

### Topologia das VMs

```
host (seu computador)
 │
 │ multipass
 │
 ├─ ntp-servidor       (chrony servidor; serve tempo à sub-rede multipass)
 ├─ ntp-cliente-1      (offset injetado: +30s ; makestep ATIVO)
 ├─ ntp-cliente-2      (offset injetado: -45s ; makestep ATIVO)
 └─ ntp-cliente-slew   (Parte B; offset +60s ; makestep DESABILITADO)
```

Observe a topologia: os clientes não se falam entre si. Cada cliente fala apenas com o servidor. O servidor é a única referência de tempo da subrede.

---

## Nível 0 — Rodar e observar

Suba a Parte A (1 servidor + 2 clientes) com um único comando:

```bash
make up
```

O `Makefile` encapsula: provisionar 3 VMs com Multipass, instalar `chrony`, aplicar as configurações, injetar drift de `+30s` no cliente-1 e `-45s` no cliente-2, e iniciar o logger CSV em cada VM.

Aguarde alguns segundos e inspecione o estado do cliente-1:

```bash
multipass exec ntp-cliente-1 -- chronyc tracking
```

Você verá algo parecido com:

```
Reference ID    : 0A0001D3 (ntp-servidor)
Stratum         : 9
Ref time (UTC)  : Mon May 18 19:42:11 2026
System time     : 0.000123456 seconds slow of NTP time
Last offset     : -0.000098712 seconds
RMS offset      : 0.001234567 seconds
Frequency       : 12.345 ppm fast
Residual freq   : +0.002 ppm
Skew            : 0.123 ppm
Root delay      : 0.000345 seconds
Root dispersion : 0.000567 seconds
Update interval : 16.4 seconds
Leap status     : Normal
```

Faça o mesmo para `ntp-cliente-2` e para `ntp-servidor`.

> **Momento didático — drift recusado:** Se você tentar mudar o relógio de uma VM com `sudo date -s "..."` enquanto `systemd-timesyncd` ou `chronyd` estiverem ativos, o comando é **recusado** com uma mensagem clara. Por isso o script de injeção de drift começa com `sudo timedatectl set-ntp false`. Tente o caminho errado em uma VM extra (`multipass launch --name teste` e depois `multipass exec teste -- sudo date -s "2030-01-01"`) — anote no relatório o que acontece.

**Observe e responda (anote no relatório):**

1. Qual VM aparece como sincronizada (`Leap status: Normal`, `Stratum` baixo) primeiro? Por que o servidor não precisa esperar nenhum cliente?
2. Os offsets injetados (`+30s` e `-45s`) aparecem em `chronyc tracking` antes de qualquer correção? Em qual campo?
3. Olhando para os logs (`multipass exec ntp-cliente-1 -- sudo cat /var/log/chrony/tracking.log`), a primeira correção foi um **step** (salto único e grande) ou um **slew** (correções pequenas e contínuas)? Como você distingue uma da outra no log?

---

## Nível 1 — Inspecionar

### 1.1 Conceitos do protocolo materializados em configuração

Abra `infra/chrony/chrony-cliente.conf` e localize, para cada conceito abaixo, **qual linha do arquivo o implementa**. Preencha a tabela no relatório.

| Conceito do protocolo                                                       | Qual linha do `.conf` implementa? | Por que esse mecanismo é necessário? |
|-----------------------------------------------------------------------------|-----------------------------------|--------------------------------------|
| Endereço da fonte de tempo                                                  |                                   |                                      |
| Convergência rápida no primeiro contato (rajada inicial de pacotes)         |                                   |                                      |
| Fronteira entre **step** e **slew**: tamanho mínimo de offset para fazer salto |                                |                                      |
| Persistência do *drift* do relógio local entre reinícios                    |                                   |                                      |
| Onde os logs com histórico de correções são gravados                        |                                   |                                      |

> **Dica:** A documentação está em `man chrony.conf` dentro da VM (`multipass exec ntp-cliente-1 -- man chrony.conf`). O objetivo é relacionar conceito ↔ linha, não decorar diretivas.

### 1.2 Campos do `chronyc tracking`

Cada campo da saída de `chronyc tracking` é uma métrica com significado físico. Preencha no relatório:

| Campo            | Valor observado | Significado físico                                                                 |
|------------------|-----------------|------------------------------------------------------------------------------------|
| `Reference ID`   |                 |                                                                                    |
| `Stratum`        |                 |                                                                                    |
| `Last offset`    |                 |                                                                                    |
| `RMS offset`     |                 |                                                                                    |
| `Frequency`      |                 |                                                                                    |
| `Root delay`     |                 |                                                                                    |
| `Root dispersion`|                 |                                                                                    |

**Relacione com o que você leu no [contexto teórico](./contexto-teorico.md):**

- `Last offset` é o resultado da fórmula `((T2 - T1) + (T3 - T4)) / 2`. Quais são os quatro instantes `T1..T4` nesse cálculo?
- `Root dispersion` é uma **cota superior** do erro até o stratum 0. Por que é "cota superior" e não o erro exato?
- `Stratum` do servidor da subrede é alto (8 ou 9) porque ele está configurado como `local stratum 8`. Em produção, por que isso seria perigoso?

### 1.3 Step vs slew nos logs

Examine o arquivo `/var/log/chrony/tracking.log` em cada cliente:

```bash
multipass exec ntp-cliente-1 -- sudo cat /var/log/chrony/tracking.log
```

No relatório, cole **dois trechos**:

1. Uma linha em que houve **step** (correção grande e instantânea — observada na coluna de offset, com valor próximo ao drift que você injetou).
2. Uma linha em que houve **slew** (correção pequena, contínua, com `Last offset` na casa de microssegundos).

Explique como você distinguiu uma da outra.

---

## Nível 2 — Experimentar

### Parte A — Convergência em 3 VMs

O experimento já está rodando desde o `make up`. Os loggers CSV em cada VM gravam, a cada segundo, o `Last offset` reportado por `chronyc tracking`.

Após ao menos 2 minutos de execução, colete os dados e gere o gráfico:

```bash
make logs        # transfere os CSVs das VMs para ./logs/
make plot        # gera convergencia-parte-a.png a partir de logs/*.csv
```

**Responda no relatório:**

1. Anexe `convergencia-parte-a.png`.
2. Em quantos segundos o `Last offset` caiu abaixo de 1ms para cada cliente?
3. Os clientes 1 e 2 convergem em tempos parecidos, mesmo tendo drifts iniciais diferentes (+30s vs −45s)? Por que (ou por que não)? Pense em qual é o mecanismo dominante de correção nesse cenário.

### Parte B — Slew puro vs step+slew

Acrescente uma 4ª VM (`ntp-cliente-slew`) com `makestep` desabilitado:

```bash
make up-b
```

Essa VM começa com offset `+60s`. Como `makestep` não está presente em `chrony-cliente-slew.conf`, o chrony **não pode** corrigir esse desalinhamento via salto — só pode usar slew, que é limitado a aproximadamente 500 ppm no kernel Linux (= 0,05% = 1 segundo de correção a cada ~2000 segundos reais).

**Aguarde pelo menos 5 minutos** após o `make up-b`. O slew puro é lento — esta é a lição.

Depois guarde os logs e plote:

```bash
make logs
make plot        # gera comparacao-parte-b.png com a 4ª curva sobreposta
```

**Responda no relatório:**

1. Anexe `comparacao-parte-b.png`.
2. Qual o tempo até convergência do `cliente-slew` comparado aos clientes default (1 e 2)?
3. Em produção, em que situação você escolheria slew puro **mesmo sabendo que é mais lento**? (Pense em sistemas que dependem de monotonicidade do relógio: TTLs, *leases*, logs ordenados, certificados.)
4. Em que situação `makestep` poderia ser **perigoso** mesmo em laboratório?

---

## Entregável

1. Faça um *fork* (ou clone) deste repositório.
2. Complete os Níveis 1 e 2.
3. Preencha o `relatorio-template.md` com suas respostas e anexe os dois gráficos (`convergencia-parte-a.png` e `comparacao-parte-b.png`).
4. Envie o link do repositório com seus commits (ou o `.zip` do projeto com o relatório preenchido), conforme orientação do professor.

Lembre-se de derrubar as VMs ao final para liberar recursos do seu computador:

```bash
make clean
```

---

## Dúvidas

Abra uma *issue* neste repositório ou traga sua pergunta para a próxima aula.
