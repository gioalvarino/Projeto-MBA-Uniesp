# gold

Modelo estrela de cobertura vacinal (ADR 0008), desenhado e implementado
em 22/08/2026 antes de carregar os outros 6 meses de dado, pra não ter que
redesenhar depois de a bronze ficar 10x maior.

- `fct_cobertura_vacinal` — fato, grão **agregado**: uma linha por
  combinação de (`data_vacina`, `chave_municipio`, `chave_vacina`,
  `chave_faixa_etaria`), métrica `qtd_doses`. Não é uma linha por dose —
  ver ADR 0008 pro porquê (tamanho/velocidade no Power BI + reforço do
  ADR 0005/LGPD).
- `dim_tempo` — calendário gerado, grão diário, cobre 2026 inteiro.
- `dim_municipio` — geografia de cobertura (ADR 0007), com membros
  especiais pra `ESTRANGEIRO`/`SEM INFORMACAO`. `nome_municipio` e
  `populacao` ainda nulos — pendem do enriquecimento com Base dos
  Dados/IBGE (ADR 0004, não implementado ainda).
- `dim_vacina` — códigos de vacina/dose. `nome_vacina`/`nome_dose` ainda
  nulos — pendem do de-para oficial do PNI (docs/dicionario_dados.md).
- `faixa_etaria` (seed, não model) — buckets etários fixos, ver ADR 0008.

**Decisão explícita:** sem dimensão de estabelecimento (onde a dose foi
aplicada) — o modelo foca só na geografia de residência (cobertura). Isso
refina o desenho original do ADR 0004. Ver ADR 0008 pro raciocínio.

**Pendências que ainda bloqueiam o indicador completo:**
- Enriquecimento com Base dos Dados/IBGE (nome de município + população) —
  sem isso, dá pra contar doses mas não calcular taxa de cobertura.
- De-para oficial de vacina/dose/estratégia do PNI.

Ainda não validado com `dbt build` contra o dado real — próximo passo.
