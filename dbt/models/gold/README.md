# gold

Modelo estrela de cobertura vacinal (ADR 0008), desenhado e implementado
em 22/08/2026 antes de carregar os outros 6 meses de dado, pra não ter que
redesenhar depois de a bronze ficar 10x maior. `dim_perfil_paciente` e
`dim_estrategia_vacinacao` foram adicionadas em 23/08/2026 (adendos ao ADR
0008), já com os 7 meses carregados. Nesse mesmo dia, o grão da fato mudou
de diário pra **mensal** (adendo ao ADR 0008) — o grão diário combinado com
as novas dimensões tinha levado a fato a 49 milhões de linhas.

- `fct_cobertura_vacinal` — fato, grão **agregado**: uma linha por
  combinação de (`mes_vacina`, `chave_municipio`, `chave_vacina`,
  `chave_faixa_etaria`, `chave_perfil`, `chave_estrategia`), métrica
  `qtd_doses`. Não é uma linha por dose — ver ADR 0008 pro porquê
  (tamanho/velocidade no Power BI + reforço do ADR 0005/LGPD).
- `dim_tempo` — calendário gerado, grão **mensal** (era diário até
  23/08/2026), cobre 2026 inteiro.
- `dim_municipio` — geografia de cobertura (ADR 0007), com membros
  especiais pra `ESTRANGEIRO`/`SEM INFORMACAO`. `nome_municipio`,
  `nome_regiao` e `populacao` já vêm da Base dos Dados/IBGE
  (`stg_ibge__municipios` — ADR 0004 + ADR 0009, implementado em
  23/08/2026), nulos só pros membros especiais. Join corrigido em
  23/08/2026 pra usar código de 6 dígitos (`id_municipio_6d`), não 7 — o
  join original não batia com nenhum município real (2º refinamento do ADR
  0009). `nome_regiao` (macro-região Norte/Nordeste/Centro-Oeste/Sudeste/
  Sul) acrescentada em 24/08/2026 — já vinha pronta na mesma tabela da Base
  dos Dados, sem seed novo (3º refinamento do ADR 0009).
- `dim_vacina` — códigos de vacina/dose. `nome_vacina`/`nome_dose`
  resolvidos direto da fonte (`ds_nome`/`ds_tipo_dose`) em 23/08/2026 —
  sem de-para externo pendente (ver adendo do ADR 0008).
- `dim_perfil_paciente` — raça/cor + sexo do paciente, padronizados na
  silver (ver "Perfil demográfico" em docs/dicionario_dados.md). Nome de
  raça/cor já vem pronto da fonte, sem de-para pendente.
- `dim_estrategia_vacinacao` — código de estratégia de vacinação (rotina,
  campanha, bloqueio etc.). `nome_estrategia` resolvido direto da fonte
  (`no_estrategia`) em 23/08/2026 — mesmo achado de `dim_vacina`.
- `faixa_etaria` (seed, não model) — buckets etários fixos, ver ADR 0008.
  Coluna de rótulo é `nome_faixa_etaria` (renomeada de `faixa_etaria` em
  23/08/2026 — nome de coluna igual ao nome da tabela fazia o conector do
  Power BI mostrar `[Record]` em vez do texto).
- `meta_vacinal` (seed, não model) — meta oficial de cobertura das 19
  vacinas do calendário infantil do PNI (ADR 0010, 24/08/2026). Ainda **sem
  join** com `dim_vacina` — ver pendência abaixo.

**Decisão explícita:** sem dimensão de estabelecimento (onde a dose foi
aplicada) — o modelo foca só na geografia de residência (cobertura). Isso
refina o desenho original do ADR 0004. Ver ADR 0008 pro raciocínio.

**Pendências em aberto:**
- Duas novas dimensões cogitadas em 23/08/2026 (estabelecimento; lote e
  fabricante da vacina) — **adiadas por decisão da Giovanna** (23/08/2026):
  seguimos sem elas por enquanto, por causa do risco de cardinalidade alta
  (mesmo problema que levou ao grão mensal da fato); implementa depois se
  a necessidade aparecer.
- De-para entre `meta_vacinal` (19 nomes oficiais do calendário) e
  `dim_vacina` (~90 variações reais de `ds_nome`) — ver ADR 0010. Sem isso,
  a meta é só referência solta no Power BI, não uma medida calculada
  automaticamente por vacina.

Validado com `dbt build` contra os 7 meses reais completos, já com o
enriquecimento IBGE (com o join corrigido) e o grão mensal (23/08/2026):
`fct_cobertura_vacinal` com 16,2 milhões de linhas (era 49 milhões no grão
diário, ver adendo do ADR 0008) — **pendente revalidar** depois da
correção do join de município e do de-para de vacina/dose/estratégia
(ambos implementados nesta mesma leva de mudanças, ainda sem novo
`dbt build` confirmado).
