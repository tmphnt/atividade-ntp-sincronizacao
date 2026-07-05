# Contexto Teórico — Sincronização de Relógios e NTP

> **Fonte primária:** Os slides do professor são o ponto de entrada recomendado para este conteúdo. Este documento é um complemento de referência, não um substituto.

---

## 1. Por que sincronizar relógios em sistemas distribuídos?

Um relógio é uma resposta à pergunta "agora". Em um único processo essa resposta é trivial — o sistema operacional consulta um cristal de quartzo e devolve um número. Em um sistema distribuído, com dois ou mais processos rodando em máquinas diferentes, "agora" deixa de ser uma resposta única. Cada máquina tem seu próprio cristal, cada cristal tem *drift* próprio, e dois processos que perguntam "agora" no mesmo instante recebem respostas diferentes.

Isso não é apenas um detalhe técnico. Boa parte da semântica de sistemas distribuídos depende implicitamente de tempo: TTLs (*time-to-live*) de cache, *leases* em mutexes distribuídos, validade de certificados TLS, expiração de tokens de autenticação, ordenação de logs para depuração, *cache invalidation* em CDNs e janelas de validade em transações financeiras. Se os relógios divergem, esses mecanismos quebram de formas sutis: um TTL expira "antes do tempo" em um nó, um certificado é considerado inválido em outro, dois eventos parecem fora de ordem no log agregado.

Lamport, em 1978, ofereceu uma resposta filosófica a esse problema: abandone o tempo físico onde possível e use **tempo lógico** baseado em causalidade (a relação *happened-before*). Mas tempo lógico não substitui tempo físico em todos os casos — TTLs e certificados precisam de tempo real. Por isso convivemos com duas tradições paralelas: protocolos como NTP que tentam aproximar relógios físicos, e estruturas como *vector clocks*, *Lamport timestamps* e Hybrid Logical Clocks (HLC) que aceitam a divergência física e modelam causalidade explicitamente.

---

## 2. NTP: história e contexto (Mills, 1985)

O Network Time Protocol foi proposto por **David L. Mills** em 1985 (RFC 958). Sua versão atual, NTPv4, é descrita na RFC 5905 (2010). Poucos protocolos da Internet têm essa longevidade — TCP e IP são contemporâneos, mas pouco mais. NTP sobreviveu quatro décadas sem precisar ser substituído principalmente porque Mills projetou-o para tolerar exatamente o tipo de Internet que de fato existiria: rede não confiável, latências variáveis, servidores que falham, atacantes que mentem.

A arquitetura de NTP organiza fontes de tempo em **estratos** (strata) hierárquicos:

- **Stratum 0:** dispositivos físicos de referência — relógios atômicos, receptores GPS, oscilantes de rubídio. Não estão na rede; entregam o tempo a um servidor stratum 1 via cabo.
- **Stratum 1:** servidores diretamente conectados a um stratum 0. São as "fontes primárias" da rede.
- **Stratum 2..15:** servidores que sincronizam com um stratum imediatamente acima.
- **Stratum 16:** marcado como "não sincronizado" — sinal de erro.

A hierarquia distribui carga (nem todos consultam stratum 1 diretamente) e isola falhas (um stratum 2 ruim afeta apenas seu sub-ramo). O `pool.ntp.org` é uma federação voluntária de servidores stratum 2 mantida pela comunidade desde 2003. Sua infraestrutura atende dezenas de bilhões de consultas por dia e é, na prática, a fonte de tempo da maior parte dos dispositivos conectados à Internet.

---

## 3. Algoritmo de Cristian e algoritmo de Berkeley

Antes de NTP existirem dois algoritmos clássicos de sincronização que ajudam a entender o problema.

**Algoritmo de Cristian (1989).** Modelo cliente-servidor. O cliente envia uma mensagem ao servidor pedindo o tempo. O servidor responde imediatamente com seu tempo `T_s`. O cliente mede o RTT (round-trip time) — o tempo entre o envio do pedido e a chegada da resposta — e **assume** que o atraso é simétrico (metade na ida, metade na volta). Estima então o tempo do servidor como `T_s + RTT/2` e ajusta seu próprio relógio. A premissa de simetria é a fraqueza central: redes reais frequentemente têm atrasos assimétricos (uma direção mais lenta que a outra), e quando isso acontece a correção fica enviesada.

**Algoritmo de Berkeley (Gusella e Zatti, 1989).** Modelo sem fonte externa. Um coordenador consulta todos os nós do grupo, coleta os tempos reportados, descarta valores aberrantes (*outliers*), calcula a média truncada dos restantes e envia a **cada** nó o ajuste relativo que deve aplicar. Não há "tempo correto" absoluto — há um tempo de consenso interno. Útil em ambientes isolados onde não há acesso a uma referência externa confiável.

| | Cristian (1989) | Berkeley (1989) |
|---|---|---|
| Modelo | Cliente consulta servidor externo | Coordenador interno consulta o grupo |
| Premissa central | Atraso simétrico na rede | Maioria dos nós está aproximadamente correta |
| Saída | Cliente ajusta para o tempo do servidor | Cada nó recebe um ajuste relativo |
| Tolerância a mentiroso | Baixa (servidor é confiável por construção) | Média (filtro de outliers) |

NTP herda elementos dos dois: estima offset via algo equivalente a Cristian, mas filtra múltiplas amostras e múltiplas fontes para tolerar mentirosos, como Berkeley.

---

## 4. NTP em detalhe: offset, delay, dispersion, stratum

NTP mede o desalinhamento entre cliente e servidor com quatro instantes:

- `T1` — instante em que o cliente envia a consulta (relógio do cliente)
- `T2` — instante em que o servidor recebe a consulta (relógio do servidor)
- `T3` — instante em que o servidor envia a resposta (relógio do servidor)
- `T4` — instante em que o cliente recebe a resposta (relógio do cliente)

Cliente e servidor trocam todos esses quatro valores em um único pacote. A partir deles, NTP calcula:

```
offset = ((T2 - T1) + (T3 - T4)) / 2
delay  = (T4 - T1) - (T3 - T2)
```

O **offset** estima a diferença entre os dois relógios assumindo que `delay/2` foi gasto em cada direção (mesma premissa de Cristian). O **delay** é o RTT descontando o tempo que o servidor levou para processar internamente.

NTP também rastreia a **dispersão** (`root dispersion`), que é uma **cota superior** do erro acumulado ao longo do caminho até stratum 0. Ela não é o erro exato — é o pior caso garantido pelo protocolo. Em uma rede saudável a dispersão fica abaixo de alguns milissegundos; em redes congestionadas ou via Wi-Fi instável pode atingir centenas de milissegundos.

A seleção de pares (*peer selection*) no NTP usa o **algoritmo de Marzullo** (Marzullo e Owicki, 1983) para escolher, entre vários servidores configurados, o conjunto cujos intervalos de incerteza se sobrepõem. Pares cujo intervalo não se sobrepõe ao da maioria são marcados como *falsetickers* e descartados. Isso dá ao NTP uma tolerância modesta a fontes de tempo defeituosas ou maliciosas — mas não substitui autenticação (ver §7, NTS).

---

## 5. Slew vs step: as duas estratégias de correção

Quando o cliente NTP detecta que seu relógio está desalinhado, ele precisa decidir **como** corrigir. Há duas estratégias, com trade-offs muito diferentes.

**Step (salto).** O cliente chama `settimeofday()` (ou equivalente) e o relógio do sistema **salta** instantaneamente para o valor correto. Rápido — a correção é imediata, qualquer que seja o tamanho do desalinhamento. Mas **viola a monotonicidade** do relógio: dois eventos consecutivos podem receber timestamps fora de ordem, ou um TTL pode expirar antes ou depois do esperado. Tudo que assume "tempo só avança" pode quebrar: locks por tempo, escalonadores de tarefas que comparam timestamps, certificados que verificam se uma data está no passado.

**Slew (deslizamento).** O cliente ajusta a **taxa** do relógio — fazendo-o avançar um pouco mais rápido ou mais devagar — até que a divergência seja absorvida gradualmente. No Linux, isso é feito via `adjtimex()` com um PLL (Phase-Locked Loop) do kernel. A taxa de slew é limitada na prática a cerca de **500 ppm** (partes por milhão), o que significa que corrigir 1 segundo de offset via slew puro leva aproximadamente **2000 segundos** (≈33 minutos). Mas o relógio permanece **monotônico**: nenhum evento é re-ordenado.

Regra prática usada em produção e codificada no chrony pela diretiva `makestep 1.0 3`:

> **Step apenas se o offset for grande (> 1 segundo) e somente nas primeiras 3 atualizações após o boot. Daí em diante, slew.**

A intuição: no boot ou após uma falha prolongada, o relógio pode estar minutos ou horas fora — slew levaria dias. Step é necessário. Mas durante operação normal os desvios são pequenos (centenas de microssegundos), perfeitamente absorvíveis por slew, e a monotonicidade do relógio é mais valiosa do que correção instantânea.

---

## 6. chrony como implementação contemporânea

O daemon NTP histórico é o `ntpd` da [NTP Project](https://www.ntp.org/), mantido por Mills e colaboradores desde os anos 1980. Em 2017, o Red Hat Enterprise Linux substituiu `ntpd` por **`chrony`** como daemon NTP padrão; o Ubuntu seguiu na versão 20.04 (2020). Hoje, chrony é o NTP que você de fato encontra em servidores Linux de produção.

As razões da substituição são técnicas:

- **Comportamento melhor em laptops e VMs.** ntpd assume relógio constantemente ativo; chrony lida bem com hibernação, suspensão, migração de VM e redes intermitentes.
- **Convergência mais rápida no boot.** chrony usa `iburst` por padrão (rajada de pacotes iniciais) e converge em segundos onde ntpd levava minutos.
- **Implementação enxuta.** Cerca de 30 mil linhas de C, contra 100 mil do ntpd. Superfície de ataque menor.
- **Suporte a NTS (Network Time Security).** chrony suporta a autenticação NTS desde 2020.

**Esta atividade usa chrony como veículo, não como objeto de estudo.** Os conceitos (offset, slew, step, dispersão, stratum) são do NTP em geral; chrony é apenas a ferramenta que torna o experimento prático. Não é necessário decorar diretivas do `chrony.conf` — saber identificar o que cada uma faz é suficiente.

---

## 7. Estado-da-arte 2026: NTS, PTP, TrueTime, HLC

NTP é dominante mas não é a única abordagem em produção. Quatro tecnologias merecem menção porque resolvem problemas que NTP não resolve sozinho.

**NTS — Network Time Security (RFC 8915, 2020).** NTP em si não é autenticado: um atacante na rede pode forjar pacotes de resposta e enviar relógios para o passado, fazendo certificados parecerem válidos ou bloqueando *rate-limiters* baseados em tempo. NTS adiciona autenticação via TLS — o cliente faz um *key exchange* com um servidor NTS-KE (Key Establishment) por TLS, recebe cookies criptográficos, e usa esses cookies para autenticar pacotes NTP subsequentes. Cloudflare oferece `time.cloudflare.com` como servidor NTS público. chrony suporta NTS com uma linha de configuração: `server time.cloudflare.com nts`.

**PTP — Precision Time Protocol (IEEE 1588).** Para aplicações que precisam de precisão sub-microssegundo (negociação automática em bolsas de valores, telecom 5G, transmissão de TV ao vivo), NTP não basta. PTP usa **timestamps em hardware** — interfaces de rede gravam o tempo exato em que cada pacote cruza o controlador, eliminando o jitter introduzido pelo sistema operacional. Em data centers da Meta (2022) e em bolsas reguladas pela MiFID II, PTP é mandatório.

**TrueTime (Spanner — Corbett et al., 2012).** O Google enfrentou um problema diferente: como garantir transações distribuídas externamente consistentes em uma base de dados que abrange continentes? A resposta foi **expor a incerteza do relógio explicitamente**. TrueTime é uma API que retorna `[earliest, latest]` em vez de um único instante — o cliente sabe que o tempo real está nesse intervalo, com altíssima confiança, baseada em GPS e relógios atômicos em cada data center. O Spanner usa essa incerteza para esperar (`commit-wait`) o suficiente antes de confirmar transações, garantindo ordenação global sem coordenação síncrona entre regiões.

**HLC — Hybrid Logical Clocks (Kulkarni et al., 2014).** Combina o melhor de Lamport (tempo lógico, captura causalidade exata) com NTP (tempo físico, alinhado com o relógio de parede). Cada timestamp HLC é o par `(physical_time, logical_counter)`. Se o tempo físico avança, o logical counter zera; se eventos chegam fora de ordem física, o logical counter compensa. CockroachDB e YugabyteDB usam HLC internamente para ordenar transações sem precisar de TrueTime.

A lição transversal: **sincronização de relógios continua sendo uma área ativa de pesquisa em 2026**, apesar de NTP estar no campo há 40 anos. Os problemas mudaram (autenticação, precisão extrema, transações distribuídas), mas o protocolo de base não envelheceu — ele coexiste e compõe com as soluções modernas.

---

## 8. Por que VMs (e não containers) para esta atividade

A escolha de Multipass + VMs leves nesta atividade é deliberada e contrasta com as duas atividades anteriores, que usaram Docker.

**Contêineres compartilham o relógio do kernel hospedeiro.** Quando você executa `docker run` e dentro dele `date -s "2030-01-01"`, ou você não tem permissão (sem `--cap-add SYS_TIME`), ou — com a capability — você muda o relógio do **host**, não do contêiner. Não existe relógio "do contêiner" para ser desalinhado: namespaces no Linux isolam rede, processos, montagens, mas **não isolam o relógio** (o `time namespace` introduzido em 2020 é parcial e raramente usado).

**Máquinas virtuais têm relógio independente.** Cada VM rodando sob KVM/QEMU (que é o que Multipass usa por baixo) tem seu próprio relógio virtual mantido pelo `kvm-clock` ou pelo `RTC` (Real Time Clock) emulado. Isso permite dessincronizar de verdade: cada VM pode estar minutos ou horas fora do host sem afetar o host.

Como bônus pedagógico, esta atividade preenche o slot **"VMs e Scripts"** do eixo tecnológico do arcabouço — as duas atividades anteriores usaram Docker, esta usa Multipass scripts. O aluno experimenta as duas categorias de tecnologia de virtualização.

---

## 9. Referências

**Fonte primária recomendada:** slides do professor.

MILLS, D. L. Network Time Protocol (NTP). **RFC 958**, Internet Engineering Task Force, 1985.
> Especificação original do NTP.

MILLS, D. L.; MARTIN, J.; BURBANK, J.; KASCH, W. Network Time Protocol Version 4: Protocol and Algorithms Specification. **RFC 5905**, IETF, 2010.
> Especificação atual (NTPv4). Cobre offset, delay, dispersion e seleção de pares.

CRISTIAN, F. Probabilistic clock synchronization. **Distributed Computing**, v. 3, n. 3, p. 146–158, 1989.
> Artigo seminal do algoritmo de Cristian.

GUSELLA, R.; ZATTI, S. The accuracy of the clock synchronization achieved by TEMPO in Berkeley UNIX 4.3BSD. **IEEE Transactions on Software Engineering**, v. 15, n. 7, p. 847–853, 1989.
> Algoritmo de Berkeley.

LAMPORT, L. Time, clocks, and the ordering of events in a distributed system. **Communications of the ACM**, v. 21, n. 7, p. 558–565, 1978.

MARZULLO, K.; OWICKI, S. Maintaining the time in a distributed system. In: **ACM Symposium on Principles of Distributed Computing**, 1983, p. 295–305.
> Algoritmo de Marzullo, usado pelo NTP para selecionar pares confiáveis.

CORBETT, J. C. et al. Spanner: Google's globally distributed database. In: **OSDI**, 2012.
> Apresenta o TrueTime e a ideia de relógio com intervalo de incerteza explícito.

KULKARNI, S. S. et al. Logical physical clocks. In: **OPODIS**, 2014.
> Hybrid Logical Clocks. Adotado por CockroachDB e YugabyteDB.

FRANKE, D.; SIBOLD, D.; TEICHEL, K.; DANSARIE, M.; SUNDBLAD, R. Network Time Security for the Network Time Protocol. **RFC 8915**, IETF, 2020.
> NTS — autenticação criptográfica para NTP.

CHRONY PROJECT. **chrony Reference Manual**. Disponível em: https://chrony-project.org. Acesso em: 2026.
> Documentação oficial do chrony, incluindo `chrony.conf` e `chronyc`.
