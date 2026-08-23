# gold

Modelo estrela de cobertura vacinal (ADR 0008), desenhado e implementado
em 22/08/2026 antes de carregar os outros 6 meses de dado, pra não ter que
redesenhar depois de a bronze ficar 10x maior. `dim_perfil_paciente` e
`dim_estrategia_vacinacao` foram adicionadas em 23/08/2026 (adendos ao ADR
0008), já com os 7 meses carregados.

- `fct_cobertura_vacinal` — fato, grão **agregado**: uma linha por
  combinação de (`data_vacina`, `chave_municipio`, `chave_vacina`,
  `chave_faixa_etaria`, `chave_perfil`, `chave_estrategia`), métrica
  `qtd_doses`. Não é uma linha por dose — ver ADR 0008 pro porquê
  (tamanho/velocidade no Power BI + reforço do ADR 0005/LGPD).
- `dim_tempo` — calendário gerado, grão diário, cobre 2026 inteiro.
- `dim_municipio` — geografia de cobertura (ADR 0007), com membros
  especiais pra `ESTRANGEIRO`/`SEM INFORMACAO`. `nome_municipio` e
  `populacao` (estimativa 2025) já vêm da Base dos Dados/IBGE
  (`stg_ibge__municipios` — ADR 0004 + ADR 0009, implementado em
  23/08/2026), nulos só pros membros especiais.
- `dim_vacina` — códigos de vacina/dose. `nome_vacina`/`nome_dose` ainda
  nulos — pendem do de-para oficial do PNI (docs/dicionario_dados.md).
- `dim_perfil_paciente` — raça/cor + sexo do paciente, padronizados na
  silver (ver "Perfil demográfico" em docs/dicionario_dados.md). Nome de
  raça/cor já vem pronto da fonte, sem de-para pendente.
- `dim_estrategia_vacinacao` — código de estratégia de vacinação (rotina,
  campanha, bloqueio etc.). `nome_estrategia` ainda nulo — pendente do
  de-para oficial do PNI, mesmo padrão de `dim_vacina`.
- `faixa_etaria` (seed, não model) — buckets etários fixos, ver ADR 0008.

**Decisão explícita:** sem dimensão de estabelecimento (onde a dose foi
aplicada) — o modelo foca só na geografia de residência (cobertura). Isso
refina o desenho original do ADR 0004. Ver ADR 0008 pro raciocínio.

**Pendência que ainda falta:**
- De-para oficial de vacina/dose/estratégia do PNI — só o rótulo textual,
  não bloqueia mais o cálculo de taxa de cobertura.

Validado com `dbt build` contra os 7 meses reais completos (23/08/2026,
PASS=46 WARN=0 ERROR=0, antes do enriquecimento IBGE — revalidar depois
dele).
