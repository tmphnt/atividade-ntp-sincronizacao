# Relatório — Atividade Prática: Sincronização de Relógios com NTP/chrony

**Disciplina:**
**Dupla:** /
**Data:**

---

## Nível 0 — Rodar e observar

1. Qual VM aparece como sincronizada primeiro (`Leap status: Normal`, `Stratum` baixo)? Por que o servidor não precisa esperar nenhum cliente?

> _Resposta:_

2. Os offsets injetados (+30s no cliente-1 e −45s no cliente-2) aparecem em `chronyc tracking` antes de qualquer correção? Em qual campo?

> _Resposta:_

3. Olhando para `/var/log/chrony/tracking.log`, a primeira correção foi um **step** (salto único e grande) ou um **slew** (correções pequenas e contínuas)? Como você distinguiu?

> _Resposta:_

### Momento didático — drift recusado

Tentativa de mudar o relógio sem desabilitar antes o `set-ntp`. Cole a mensagem de erro do `timedatectl` / `date -s` e explique-a em uma frase:

```
(cole a mensagem aqui)
```

> _Explicação:_

---

## Nível 1 — Inspecionar

### 1.1 Conceitos do protocolo materializados em configuração

| Conceito do protocolo                                                       | Qual linha do `.conf` implementa? | Por que esse mecanismo é necessário? |
|-----------------------------------------------------------------------------|-----------------------------------|--------------------------------------|
| Endereço da fonte de tempo                                                  |                                   |                                      |
| Convergência rápida no primeiro contato (rajada inicial de pacotes)         |                                   |                                      |
| Fronteira entre **step** e **slew**: tamanho mínimo de offset para fazer salto |                                |                                      |
| Persistência do *drift* do relógio local entre reinícios                    |                                   |                                      |
| Onde os logs com histórico de correções são gravados                        |                                   |                                      |

---

### 1.2 Campos do `chronyc tracking`

| Campo            | Valor observado | Significado físico                                                                 |
|------------------|-----------------|------------------------------------------------------------------------------------|
| `Reference ID`   |                 |                                                                                    |
| `Stratum`        |                 |                                                                                    |
| `Last offset`    |                 |                                                                                    |
| `RMS offset`     |                 |                                                                                    |
| `Frequency`      |                 |                                                                                    |
| `Root delay`     |                 |                                                                                    |
| `Root dispersion`|                 |                                                                                    |

**Perguntas conceituais:**

1. `Last offset` é o resultado da fórmula `((T2 − T1) + (T3 − T4)) / 2`. Quais são os quatro instantes `T1..T4` nesse cálculo?

> _Resposta:_

2. Por que `Root dispersion` é uma **cota superior** do erro acumulado, e não o erro exato?

> _Resposta:_

3. O servidor da subrede aparece com `Stratum` alto (8 ou 9) porque está configurado como `local stratum 8`. Em produção, por que essa configuração seria perigosa?

> _Resposta:_

---

### 1.3 Step vs slew nos logs

Cole um trecho do log que evidencia um **step** (correção grande e instantânea):

```
(cole o trecho aqui)
```

Cole um trecho do log que evidencia um **slew** (correção pequena, contínua, microssegundos):

```
(cole o trecho aqui)
```

> _Como você distinguiu uma da outra:_

---

## Nível 2 — Experimentar

### Parte A — Convergência em 3 VMs

1. Anexe o gráfico `convergencia-parte-a.png` aqui:

![Convergência Parte A](./logs/convergencia-parte-a.png)

2. Em quantos segundos o `Last offset` caiu abaixo de 1ms para cada cliente?

| VM            | Offset inicial | Tempo até `|offset| < 1ms` |
|---------------|----------------|-----------------------------|
| ntp-cliente-1 | +30s           |                             |
| ntp-cliente-2 | −45s           |                             |

3. Os clientes 1 e 2 convergem em tempos parecidos, mesmo tendo drifts iniciais diferentes (+30s vs −45s)? Por quê? Qual é o mecanismo dominante de correção nesse cenário?

> _Resposta:_

---

### Parte B — Slew puro vs step+slew

1. Anexe o gráfico `comparacao-parte-b.png` aqui:

![Comparação Parte B](./logs/comparacao-parte-b.png)

2. Tempo até convergência:

| VM                | Offset inicial | Estratégia | Tempo até `|offset| < 1ms` |
|-------------------|----------------|------------|-----------------------------|
| ntp-cliente-1     | +30s           | step+slew  |                             |
| ntp-cliente-slew  | +60s           | slew puro  |                             |

3. Em produção, em que situação você escolheria slew puro **mesmo sabendo que é mais lento**? Pense em sistemas que dependem de monotonicidade do relógio.

> _Resposta:_

4. Em que situação `makestep` poderia ser **perigoso** mesmo em laboratório?

> _Resposta:_

---

## Observações livres

_(Comportamentos inesperados, erros encontrados, dificuldades técnicas — descreva o que aconteceu e como você resolveu)_

>

---

## Dúvida para a próxima aula

_(Formule uma pergunta substantiva que surgiu durante a atividade)_

>
