# Relatório — Atividade Prática: Sincronização de Relógios com NTP/chrony

**Disciplina:** Sistemas Distribuídos
**Dupla:** Tom Pereira Hunt / Pedro Henrique Gimenez
**Data:** 05/07/2026

---

## Nível 0 — Rodar e observar

1. Qual VM aparece como sincronizada primeiro (`Leap status: Normal`, `Stratum` baixo)? Por que o servidor não precisa esperar nenhum cliente?

> _Resposta:_ O ntp-servidor. Ele é a referência de tempo da subrede: sincroniza
> com o pool público (`pool 2.pool.ntp.org`) quando tem internet e, se não tiver,
> assume `local stratum 8` e vira a própria referência. No nosso caso tinha
> internet, então ele pegou uma fonte real (Reference ID `c.ntp.br`, Stratum 3) e
> os clientes ficaram em Stratum 4 logo atrás dele. De qualquer jeito o servidor
> tem hora válida sem depender de ninguém; os clientes é que dependem dele, então
> ele não espera cliente nenhum.

2. Os offsets injetados (+30s no cliente-1 e −45s no cliente-2) aparecem em `chronyc tracking` antes de qualquer correção? Em qual campo?

> _Resposta:_ Aparecem, mas na janela curtinha antes do chrony corrigir. Quem
> mostra o desalinhamento é o campo `System time` ("X seconds fast/slow of NTP
> time"), e no `tracking.log` a coluna de Offset registra o valor medido perto do
> que foi injetado (a gente viu uma linha com Offset `2.975e+01` s no cliente-1,
> ou seja ~30s). Como o `makestep` salta nas primeiras medidas, a janela some
> rápido.

3. Olhando para `/var/log/chrony/tracking.log`, a primeira correção foi um **step** (salto único e grande) ou um **slew** (correções pequenas e contínuas)? Como você distinguiu?

> _Resposta:_ Foi **step**. O drift injetado (~30s) é bem maior que a fronteira de
> 1s do `makestep 1.0 3`, então o chrony saltou o relógio de uma vez. No log dá pra
> distinguir pela magnitude: a linha do step tem Offset na casa das dezenas de
> segundos (2.975e+01) e some numa tacada só, enquanto as linhas de slew depois têm
> Offset na casa de micro/milissegundos (ex. 1.944e-04 = 194 µs) sendo absorvidas
> aos pouquinhos.

### Momento didático — drift recusado

Tentativa de mudar o relógio sem desabilitar antes o `set-ntp`. Cole a mensagem de erro do `timedatectl` / `date -s` e explique-a em uma frase:

```
# timedatectl com NTP ativo:
$ sudo timedatectl set-time "2030-01-01 00:00:00"
Failed to set time: Automatic time synchronization is enabled

# date -s com NTP ativo (curiosidade):
$ sudo date -s "2030-01-01 00:00:00"
Tue Jan  1 00:00:00 -03 2030      # nao foi recusado; o chrony so corrige de volta depois
```

> _Explicação:_ O `systemd-timedated` é o dono do relógio enquanto o NTP está ativo
> e recusa o `set-time` com "Automatic time synchronization is enabled", pra ninguém
> sobrescrever a hora que o daemon mantém. Por isso o `inject-drift.sh` começa com
> `sudo timedatectl set-ntp false`. (Curiosidade: o `date -s` bruto não passa pelo
> timedated, então o kernel aceita o salto na hora, mas o chrony rapidamente puxa a
> hora de volta — só o caminho do `timedatectl` é bloqueado de forma limpa.)

---

## Nível 1 — Inspecionar

### 1.1 Conceitos do protocolo materializados em configuração

| Conceito do protocolo                                                       | Qual linha do `.conf` implementa? | Por que esse mecanismo é necessário? |
|-----------------------------------------------------------------------------|-----------------------------------|--------------------------------------|
| Endereço da fonte de tempo                                                  | `server SERVIDOR_IP iburst`       | O cliente precisa saber com quem sincronizar. Sem apontar uma fonte, ele não tem referência pra comparar o relógio. |
| Convergência rápida no primeiro contato (rajada inicial de pacotes)         | `iburst` (na linha `server SERVIDOR_IP iburst`) | O `iburst` dispara uma rajada de pacotes logo no início, em vez de esperar o intervalo normal de polling, então o cliente converge em segundos e não em minutos no primeiro contato. |
| Fronteira entre **step** e **slew**: tamanho mínimo de offset para fazer salto | `makestep 1.0 3`               | Diz que, se `|offset| > 1.0s` nas 3 primeiras medidas, o chrony corrige com salto (step); depois disso só via slew. Grandes desvios precisam de step pra não demorar demais. |
| Persistência do *drift* do relógio local entre reinícios                    | `driftfile /var/lib/chrony/drift` | Guarda a taxa de drift do oscilador local em disco, então no próximo boot o chrony já começa compensando esse desvio conhecido, em vez de reaprender do zero. |
| Onde os logs com histórico de correções são gravados                        | `logdir /var/log/chrony` (com `log measurements statistics tracking`) | Define o diretório e o que é gravado, pra dar pra inspecionar o histórico de correções (é o que a gente lê no `tracking.log`). |

> Obs.: no `chrony-cliente-slew.conf` a diretiva `makestep` está **ausente** de
> propósito. É por isso que aquele cliente nunca salta e só corrige via slew.

---

### 1.2 Campos do `chronyc tracking`

Valores observados no `ntp-cliente-1` já convergido (`chronyc tracking`):

| Campo            | Valor observado | Significado físico                                                                 |
|------------------|-----------------|------------------------------------------------------------------------------------|
| `Reference ID`   | `C0A84006 (192.168.64.6)` | Identifica a fonte com quem está sincronizado. Aqui é o ntp-servidor (IP 192.168.64.6). |
| `Stratum`        | `4`             | Distância em saltos até o relógio de referência. O servidor pegou uma fonte real em Stratum 3, então o cliente fica em 4. |
| `Last offset`    | `+0.000194449 s` | Correção aplicada na última atualização do relógio (o quanto ele ajustou por último). |
| `RMS offset`     | `0.000248025 s` | Média quadrática dos offsets recentes. Mede a estabilidade/qualidade da sincronização ao longo do tempo. |
| `Frequency`      | `2.340 ppm slow` | Erro de frequência do oscilador local (o relógio corre 2,34 ppm devagar por si só). É o que o chrony compensa continuamente. |
| `Root delay`     | `0.050430071 s` | Soma dos atrasos de rede (RTT) no caminho até o stratum 0. |
| `Root dispersion`| `0.005785384 s` | Cota superior do erro acumulado até o stratum 0 (incerteza máxima garantida). |

**Perguntas conceituais:**

1. `Last offset` é o resultado da fórmula `((T2 − T1) + (T3 − T4)) / 2`. Quais são os quatro instantes `T1..T4` nesse cálculo?

> _Resposta:_ São os quatro carimbos de tempo da troca NTP: T1 é quando o cliente
> manda a requisição, T2 é quando o servidor recebe, T3 é quando o servidor manda a
> resposta e T4 é quando o cliente recebe de volta. `(T2 − T1)` é o caminho de ida e
> `(T3 − T4)` o de volta; a média dos dois cancela o RTT e sobra o desvio entre os
> dois relógios. Assim dá pra separar o offset do relógio do atraso da rede.

2. Por que `Root dispersion` é uma **cota superior** do erro acumulado, e não o erro exato?

> _Resposta:_ Porque o erro real do relógio não dá pra saber com exatidão (se desse,
> era só corrigir). Então o chrony soma as incertezas máximas do caminho — resolução
> de cada relógio, drift possível desde a última atualização, jitter de rede — e vai
> acumulando até o stratum 0. O resultado é uma garantia de pior caso ("o erro não
> passa disso"), não a medida exata do desvio.

3. O servidor da subrede aparece com `Stratum` alto (8 ou 9) porque está configurado como `local stratum 8`. Em produção, por que essa configuração seria perigosa?

> _Resposta:_ Porque o `local stratum 8` faz o servidor se anunciar como fonte
> válida mesmo quando não está sincronizado com nenhuma referência real. Ele pode
> estar com a hora errada e os clientes aceitam assim mesmo, porque ele "parece"
> legítimo, e aí espalha hora errada pela subrede sem ninguém detectar. Em lab
> isolado é proposital (garante sincronização sem internet); em produção é
> perigoso. (No nosso caso tinha internet, então o servidor pegou uma fonte real
> `c.ntp.br` em Stratum 3 e não caiu no fallback local — mas o risco do fallback
> continua valendo.)

---

### 1.3 Step vs slew nos logs

Trecho do `tracking.log` do `ntp-cliente-1` (colunas: Date Time / IP / St / Freq / Skew / **Offset** / L / ...).

Linha de **step** (correção grande e instantânea — Offset em dezenas de segundos, ~ o drift de +30s injetado):

```
2026-07-05 17:23:48 192.168.64.6   4   -5.183    1.369   2.975e+01 N  1  2.803e-05 ...
```

Linha de **slew** (correção pequena e contínua — Offset em microssegundos):

```
2026-07-05 17:48:16 192.168.64.6   4   -2.340    6.827   1.944e-04 N  1  1.619e-04 ...
```

> _Como você distinguiu uma da outra:_ Pela ordem de grandeza da coluna Offset. No
> step o valor é enorme (`2.975e+01` s ≈ 30 segundos) e o relógio é acertado de uma
> vez. No slew o valor é minúsculo (`1.944e-04` s ≈ 194 µs), uma de várias correções
> contínuas que o chrony aplica mudando de leve a velocidade do relógio.

---

## Nível 2 — Experimentar

> **Nota sobre a métrica dos gráficos:** o logger da atividade grava o campo
> `Last offset`, que é só a correção da **última** atualização — depois de um step
> ele já fica minúsculo e não mostra a convergência. Quem mostra o offset que ainda
> falta corrigir é o campo `System time` do `chronyc tracking`. Então plotamos o
> `System time` (offset remanescente) ao longo do tempo, que é o que deixa a
> convergência visível. O `plot.py` original não foi alterado.

### Parte A — Convergência em 3 VMs

1. Anexe o gráfico `convergencia-parte-a.png` aqui:

![Convergência Parte A](./logs/convergencia-parte-a.png)

2. Em quantos segundos o `Last offset` caiu abaixo de 1ms para cada cliente?

| VM            | Offset inicial | Tempo até `|offset| < 1ms` |
|---------------|----------------|-----------------------------|
| ntp-cliente-1 | +30s           | praticamente imediato (< poucos segundos) |
| ntp-cliente-2 | −45s           | praticamente imediato (< poucos segundos) |

> No gráfico dá pra ver que os dois clientes ficam colados no zero: o eixo Y nem sai
> da casa do sub-milissegundo (± 0,8 ms). O step corrige os 30s/45s já na primeira
> medição, então o offset remanescente cai abaixo de 1ms praticamente de imediato,
> e o que sobra são só uns tremidos de microssegundos do ajuste fino via slew.

3. Os clientes 1 e 2 convergem em tempos parecidos, mesmo tendo drifts iniciais diferentes (+30s vs −45s)? Por quê? Qual é o mecanismo dominante de correção nesse cenário?

> _Resposta:_ Sim, convergem em tempos parecidos (os dois quase instantâneos). O
> mecanismo dominante é o **step**: como +30 e −45 são bem maiores que a fronteira
> de 1s do `makestep`, o chrony salta quase todo o desalinhamento de uma vez, e o
> tamanho ou o sinal do drift quase não muda o tempo total. Depois do salto sobra só
> o slew fino, que é pequeno e parecido pros dois. Por isso o +30 e o −45, apesar de
> diferentes, levam mais ou menos o mesmo tempo.

---

### Parte B — Slew puro vs step+slew

1. Anexe o gráfico `comparacao-parte-b.png` aqui:

![Comparação Parte B](./logs/comparacao-parte-b.png)

2. Tempo até convergência:

| VM                | Offset inicial | Estratégia | Tempo até `|offset| < 1ms` |
|-------------------|----------------|------------|-----------------------------|
| ntp-cliente-1     | +30s           | step+slew  | praticamente imediato (segundos) |
| ntp-cliente-slew  | +60s           | slew puro  | ~11 minutos (rampa linear de 60s → 0) |

> O gráfico deixa a diferença gritante: o cliente-slew (sem `makestep`) sobe pra 60s
> e desce numa **rampa linear** até zerar em torno de 11 minutos, enquanto o
> cliente-1 (com step) fica colado no zero o tempo todo. A inclinação da rampa bate
> com a taxa máxima de slew do chrony (~83000 ppm ≈ corrigir ~1s a cada ~12s reais).

3. Em produção, em que situação você escolheria slew puro **mesmo sabendo que é mais lento**? Pense em sistemas que dependem de monotonicidade do relógio.

> _Resposta:_ Quando o sistema depende do relógio nunca andar pra trás nem saltar,
> ou seja, monotonicidade. Coisas como TTLs, leases, timestamps que ordenam eventos
> em log, validade de certificados e tokens. Um step pra trás faria o tempo "voltar"
> e isso quebraria a ordenação dos eventos, poderia expirar/renovar coisa na hora
> errada, invalidar um lease que ainda valia. O slew nunca salta nem retrocede, só
> ajusta a velocidade de leve, então mantém o tempo sempre crescente. Nesses casos
> vale trocar velocidade de correção por segurança.

4. Em que situação `makestep` poderia ser **perigoso** mesmo em laboratório?

> _Resposta:_ Sempre que um salto abrupto puder quebrar algo que estava contando com
> o tempo. Por exemplo, um step pra trás no meio de uma medição de duração (mediria
> tempo negativo), ou logo depois de o sistema já ter subido serviços com timers/TTLs
> — o salto pode disparar timeouts na hora errada, bagunçar a ordem dos logs, ou
> fazer um cache/lease expirar (ou "renascer") de repente. Mesmo em lab, um makestep
> grande num momento ruim atrapalha qualquer coisa sensível a tempo.

---

## Observações livres

_(Comportamentos inesperados, erros encontrados, dificuldades técnicas — descreva o que aconteceu e como você resolveu)_

> - O passo do `set-ntp false` antes de injetar o drift é o pulo do gato: sem ele o
>   `timedatectl set-time` recusa mudar a hora enquanto o NTP está ativo, que é
>   justamente o momento didático.
> - Descobrimos na prática que o campo certo pra visualizar a convergência é o
>   `System time` (offset que ainda falta), e não o `Last offset` que o logger grava
>   — o `Last offset` fica minúsculo logo depois do step e esconde a história. Por
>   isso registramos o `System time` também e plotamos ele.
> - A diferença step x slew ficou clara comparando o cliente-1 com o cliente-slew: o
>   mesmo tipo de problema (relógio muito fora) resolve em segundos com step e em ~11
>   minutos só com slew. É a lição da atividade num gráfico.
> - Detalhe de ambiente: nossa máquina de vez em quando pausava as VMs (o host
>   segurava CPU), então o relógio "real" e o das VMs andaram em ritmos diferentes por
>   alguns instantes e a coleta demorou mais que o esperado. A rampa do slew em si
>   saiu limpa porque medimos o offset relativo ao servidor, não o tempo de parede.

---

## Dúvida para a próxima aula

_(Formule uma pergunta substantiva que surgiu durante a atividade)_

> A taxa máxima de slew do chrony é o que faz o slew puro levar ~11 min pra 60s.
> Existe um ponto de equilíbrio usado na prática: até quantos segundos de offset vale
> a pena corrigir só com slew (mantendo a monotonicidade) antes de o atraso ficar
> inaceitável e compensar aceitar um step? Como sistemas reais que dependem de tempo
> (por exemplo bancos de dados distribuídos) decidem esse limite?
