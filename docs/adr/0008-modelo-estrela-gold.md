# ADR 0008: Modelo estrela da gold — grão da fato e dimensões

- **Status:** aceita
- **Data:** 2026-08-22
- **Responsável:** Giovanna

## Contexto

Com a geografia de cobertura resolvida (ADR 0007), o próximo passo é
desenhar o modelo estrela da gold antes de carregar os outros 6 meses de
dado — decisão deliberada do trio, pra não ter que redesenhar depois de a
tabela ficar 10x maior. Duas decisões de grão/escopo precisavam ser
fechadas antes de escrever qualquer model.

Este ADR **refina** o desenho original do ADR 0004, que previa uma
dimensão de estabelecimento — ver Decisão abaixo.

## Opções consideradas

**Grão da fato:**
1. **Uma linha por dose aplicada** (mesmo grão da silver) — mais flexível
   pra análises futuras não previstas hoje, mas ~8,9M linhas só em
   fevereiro (dezenas de milhões nos 7 meses), mais pesado no Power BI, e
   mantém uma linha por evento/pessoa na gold.
2. **Agregada por combinação de dimensões** (dia + município de cobertura
   + vacina/dose + faixa etária), com `qtd_doses` como métrica. Milhares de
   linhas em vez de milhões, muito mais rápida no Power BI, e reforça o
   princípio do ADR 0005 (nenhum dado pessoal identificável avança pra
   gold) — perde a capacidade de analisar por indivíduo, que não é
   necessária pro indicador de cobertura (o insight alvo, ADR 0001).

**Dimensão de estabelecimento:**
1. **Manter**, permitindo analisar também onde as pessoas se vacinam
   (útil pra identificar polos de saúde e deslocamento entre municípios).
2. **Remover**, mantendo o modelo focado só na geografia de cobertura
   (residência) decidida na ADR 0007 — mais simples, sem reintroduzir a
   ambiguidade aplicação-vs-residência que aquela ADR já resolveu.

## Decisão

**Grão da fato:** agregada — uma linha por combinação de
(`data_vacina`, `chave_municipio`, `chave_vacina`, `chave_faixa_etaria`),
com `qtd_doses` = contagem de doses naquela combinação.

**Dimensão de estabelecimento:** removida do escopo da gold. A `fct_cobertura_vacinal`
usa só a geografia de cobertura (`municipio_cobertura`/`uf_cobertura`, ADR 0007).

**Modelo estrela resultante:**

- `fct_cobertura_vacinal` (fato): `data_vacina`, `chave_municipio`,
  `chave_vacina`, `chave_faixa_etaria`, `qtd_doses`.
- `dim_tempo`: dimensão de calendário gerada (não vem da fonte), grão
  diário, cobrindo 2026 inteiro.
- `dim_municipio`: chave = `municipio_cobertura` quando existe, senão
  `uf_cobertura` (cobre os casos especiais 'ESTRANGEIRO'/'SEM INFORMACAO'
  como membros próprios da dimensão, sem sentinela numérico arbitrário).
  `nome_municipio` e `populacao` ficam **nulos por design** — dependem do
  enriquecimento com Base dos Dados/IBGE, que o ADR 0004 já previa
  acontecer na silver e ainda não foi implementado.
- `dim_vacina`: chave = `co_vacina || '-' || co_dose_vacina`. `nome_vacina`
  e `nome_dose` ficam nulos — de-para oficial do PNI ainda pendente (mesma
  pendência já registrada no dicionário de dados).
- `dim_faixa_etaria` (seed `faixa_etaria.csv`, referência fixa, não vem da
  fonte): buckets etários usuais de programas de imunização —  menor de 1
  ano, 1 ano, 2 a 4, 5 a 9, 10 a 19, 20 a 59, 60 ou mais, e "sem
  informação" pra idade nula. Fronteiras ajustáveis depois, é só editar o
  seed — não exige mudar a fato nem as outras dimensões.

## Consequências

- A gold fica pequena e rápida (milhares de linhas, não milhões), ideal
  pro Power BI e alinhada ao ADR 0005 (LGPD).
- Análises por indivíduo (ex.: histórico de doses de uma pessoa) não são
  possíveis a partir da gold — quem precisar disso vai direto na silver.
  Isso é aceito conscientemente: não é o objetivo do produto.
- `dim_municipio` e `dim_vacina` ficam com atributos "pendente" (nome,
  população, nome de vacina/dose) até o enriquecimento externo acontecer —
  o indicador de cobertura (contagem de doses) já funciona sem eles, mas o
  indicador de **taxa** de cobertura (doses ÷ população) só fica completo
  depois da integração com Base dos Dados/IBGE.
- Testes de integridade referencial (`relationships`) entre a fato e cada
  dimensão substituem a necessidade de chaves estrangeiras reais do
  BigQuery (que não existem no motor) — ver `_gold__models.yml`.

## Adendo (23/08/2026): dimensão de perfil demográfico

Com os 7 meses já carregados, Giovanna pediu pra revisar quais colunas
"limpar" antes do BI. Na revisão, decidiu que raça/cor e sexo do paciente
**devem** chegar na gold, pra mostrar características de quem foi vacinado
(indicador comum de equidade em vigilância em saúde pública) — o oposto do
instinto inicial de remover `co_raca_cor_paciente` por não ter uso definido
ainda.

**Decisão:** nova dimensão `dim_perfil_paciente` (chave = raça/cor + sexo
padronizados), referenciada por uma nova chave `chave_perfil` na
`fct_cobertura_vacinal`. Validado contra os 7 meses reais (23/08/2026):

- `tp_sexo_paciente`: F (63.844.931), M (51.311.897), I/Ignorado (1.827),
  N (2, provável erro de digitação da fonte) — sem nulo de fato. `I` e `N`
  viram `'SEM INFORMACAO'` em `sexo_cobertura`.
- `co_raca_cor_paciente`/`no_raca_cor_paciente`: par sempre consistente (01
  Branca, 02 Preta, 03 Parda, 04 Amarela, 05 Indígena, 99 Sem informação),
  nulo em só 4 de ~115M linhas — caem em `'99'`/`'SEM INFORMACAO'`.

Diferente de `dim_vacina`, o nome de raça/cor já vem pronto na fonte
(`no_raca_cor_paciente`) — sem de-para externo pendente.

Também aproveitado pra remover `status_documento` da silver: confirmado
sempre `"final"` nos 7 meses reais (não só na amostra de fevereiro), sem
valor analítico. Segue documentado como coluna da bronze
(`_silver__sources.yml`), só não é mais trazido pra silver/gold.

**Consequência:** `dim_perfil_paciente` é pequena (até 18 combinações) e
segue o mesmo princípio de agregação do ADR 0005 — raça/cor e sexo entram
só como contagem por combinação, nunca ligados a um paciente individual.
