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

## Adendo (23/08/2026): dimensão de estratégia de vacinação

Mesma revisão de colunas: `co_estrategia_vacinacao` não era usada em nenhuma
dimensão/fato até então. Decisão: **manter e subir pra gold** (em vez de
remover) — estratégia de vacinação (rotina/campanha/bloqueio etc.) é um
recorte relevante pro indicador de cobertura (ADR 0001), permitindo separar
cobertura de rotina de picos pontuais de campanha.

**Decisão:** nova dimensão `dim_estrategia_vacinacao` (chave =
`estrategia_cobertura`), referenciada por uma nova chave `chave_estrategia`
na `fct_cobertura_vacinal`. Segue o mesmo padrão de `dim_vacina`: sobe só o
código por enquanto — `nome_estrategia` fica nulo, pendente do de-para
oficial do PNI (mesma pendência já registrada pra vacina/dose).

Distribuição real validada (23/08/2026, 7 meses, ~115M linhas): 16 códigos
distintos (0 a 15), volume concentrado em poucos códigos (maior: 90M
registros; menor: 8k), e ~686k linhas (~0,6%) com o código nulo — caem em
`'SEM INFORMACAO'` na silver (`estrategia_cobertura`), mesma convenção das
outras dimensões pequenas.

**Consequência:** mais uma chave na fato (6 chaves ao todo), mas a
dimensão continua pequena (17 linhas: 16 códigos + 'SEM INFORMACAO'). O
indicador de cobertura por estratégia já funciona pra contagem de doses;
só o rótulo textual (nome da estratégia) depende do de-para externo.

## Adendo (23/08/2026): grão mensal (era diário)

Ao preparar a conexão com o Power BI, o `dbt build` revelou que
`fct_cobertura_vacinal` tinha crescido pra **49 milhões de linhas** (12,4
GiB processados só pra criar a tabela) — contrariando diretamente o
objetivo original deste ADR ("milhares de linhas, não milhões"). Causa: os
dois adendos acima (`chave_perfil`, `chave_estrategia`) aumentaram o número
de combinações possíveis, e combinado com o grão diário original
(`data_vacina`, a dimensão de maior cardinalidade — ~212 dias distintos nos
7 meses, contra poucas dezenas de valores nas outras dimensões), a
compressão em relação às ~115M linhas da silver ficou próxima de zero.

**Opções consideradas:**
1. **Manter grão diário, usar DirectQuery no Power BI** — evita importar
   49M linhas pra memória, mas cada interação no relatório dispara uma
   nova consulta na BigQuery (mais lento, ainda dentro do free tier de
   consulta mas gerando jobs repetidos) e não resolve o desalinhamento
   com o objetivo original do ADR.
2. **Manter grão diário, importar mesmo assim** — arquivo pesado, risco de
   lentidão/travamento no Power BI Desktop, sem necessidade real (ninguém
   analisa cobertura vacinal por dia específico).
3. **Mudar o grão de `data_vacina` (dia) pra `mes_vacina` (mês)** — reduz
   a cardinalidade da dimensão de tempo de ~212 valores pra 7 (um por mês
   carregado), recuperando a compressão. Perde a granularidade de dia
   específico, que não é usada em indicadores de cobertura vacinal (sempre
   reportados por mês/ano) — trade-off aceitável.

**Decisão:** opção 3. `mes_vacina` (= `date_trunc(data_vacina, month)`)
substitui `data_vacina` na fato; `dim_tempo` passa a ter grão mensal
(chave `mes`, primeiro dia do mês), perdendo as colunas de dia da semana
(que só faziam sentido no grão diário).

**Consequências:**
- Reduz drasticamente o número de combinações possíveis na fato (a
  dimensão de tempo cai de ~212 valores distintos pra 7), sem eliminar
  nenhuma das outras chaves (`chave_perfil` e `chave_estrategia`
  continuam).
- Análises por dia específico deixam de ser possíveis a partir da gold —
  aceito conscientemente, mesmo raciocínio do ADR original pra não
  permitir análise por indivíduo: não é o objetivo do produto.
- `dim_tempo` fica mais simples (sem dia da semana), mas continua cobrindo
  2026 inteiro (12 meses gerados, mesmo que só 7 tenham dado carregado).

**Validado com `dbt build` contra os 7 meses reais (23/08/2026):**
`fct_cobertura_vacinal` caiu de 49,0 milhões pra **16,2 milhões de linhas**
(12,4 GiB processados, mesmo volume de antes — o custo de processamento não
muda, só o tamanho do resultado). A redução (~67%) é menor do que o
esperado só pela queda de ~212 dias pra 7 meses na dimensão de tempo:
`chave_municipio` (~5,6 mil) × `chave_vacina` (~1,7 mil) já formam um teto
de combinações na casa dos milhões por conta própria, então boa parte do
volume da fato vem dessas duas dimensões, não da granularidade de tempo.
16,2 milhões de linhas é grande pro objetivo original ("milhares, não
milhões") mas é uma escala normal pro Power BI em modo Import — o VertiPaq
comprime bem colunas categóricas repetidas como essas, então o `.pbix`
final deve ficar bem menor do que os 12,4 GiB processados sugerem.
PASS=50 WARN=1 ERROR=0 (o único warning é o de `populacao` já conhecido e
documentado no ADR 0009, não relacionado a essa mudança) — todos os testes
de `relationships` entre a fato e as 6 dimensões, incluindo o novo
`mes_vacina` → `dim_tempo.mes`, passaram.

## Adendo (23/08/2026): coluna `faixa_etaria` renomeada pra `nome_faixa_etaria`

Ao conectar o Power BI (Get Data → Google BigQuery → Importar), a tabela
`faixa_etaria` carregou com a coluna de rótulo (o nome da faixa, ex. "1
ano", "60 anos ou mais") mostrando `[Record]` em toda linha em vez do
texto — achado real, não afeta o `dbt build` nem o BigQuery em si, só a
visualização no Power BI. Causa: a coluna tinha o **mesmo nome da
tabela** (`faixa_etaria`), e o conector do Power BI pro BigQuery trata essa
coincidência de forma ambígua, encapsulando o valor num record em vez de
expor o texto direto.

**Decisão:** renomear a coluna de `faixa_etaria` pra `nome_faixa_etaria`
no seed (`dbt/seeds/faixa_etaria.csv` + `_seeds__seeds.yml`), seguindo o
mesmo padrão `nome_*` já usado em `dim_tempo.nome_mes`,
`dim_vacina.nome_vacina`, `dim_estrategia_vacinacao.nome_estrategia` e
`dim_perfil_paciente.nome_raca_cor`. Nenhum outro model referencia essa
coluna diretamente (só `ordem`, `idade_min`, `idade_max` são usados em
`fct_cobertura_vacinal.sql`), então a mudança não teve nenhum impacto
além do próprio seed — sem re-teste de relationships necessário.

## Adendo (23/08/2026): de-para de vacina/dose/estratégia resolvido direto da fonte

Ao inspecionar `dim_vacina`/`dim_estrategia_vacinacao` no Power BI (colunas
`nome_vacina`/`nome_dose`/`nome_estrategia` vazias, como já era esperado —
"pendente do de-para oficial do PNI"), Giovanna reparou que a bronze tem
`ds_nome` com o nome da vacina. Investigando o cabeçalho completo da
bronze (`INFORMATION_SCHEMA.COLUMNS`, ~56 colunas — bem mais do que o
subconjunto documentado em 22/08/2026), apareceram também `ds_tipo_dose`
(nome da dose) e `no_estrategia` (nome da estratégia). As três eliminam de
uma vez a pendência de de-para externo pesquisada (sem sucesso) no dia
anterior.

Validado 1-pra-1 contra os 7 meses reais antes de aplicar (mesma checagem
usada pra raça/cor): nenhum código com mais de um nome distinto.
`co_estrategia_vacinacao` = `0` e `NULL` não têm nome na fonte — ambos
caem em `'SEM INFORMACAO'`, sem conflito com a chave já usada. Os 16
códigos de estratégia (incluindo os 10-15 que a tabela do RNDS não
cobria — ver `docs/dicionario_dados.md`) agora têm nome oficial direto da
fonte, superando a pesquisa externa inconclusiva.

**Decisão:** `stg_pni__doses_aplicadas` passa a expor
`nome_vacina_cobertura`, `nome_dose_cobertura` e
`nome_estrategia_cobertura` (mesmo padrão `coalesce(..., 'SEM
INFORMACAO')` das outras colunas `*_cobertura`). `dim_vacina.sql` e
`dim_estrategia_vacinacao.sql` passam a preencher `nome_vacina`/
`nome_dose`/`nome_estrategia` a partir dessas colunas, em vez de
`cast(null as string)`. Testes `not_null` adicionados nessas 3 colunas na
gold (antes não existiam, porque eram sempre nulas por design).

**Consequências:**
- Elimina a última pendência de de-para externo do projeto — as únicas
  três dimensões que dependiam de uma tabela oficial do PNI agora vêm
  completas direto da fonte, sem risco de aplicar um mapeamento incorreto
  (o motivo pelo qual a pesquisa do dia anterior não foi aplicada).
- `docs/dicionario_dados.md` atualizado: a seção "Códigos pendentes de
  de-para" virou "De-para de vacina/dose/estratégia — RESOLVIDO", com a
  pesquisa anterior mantida como registro histórico (não mais necessária).
- Reforça a lição do achado do cabeçalho incompleto (ver seção
  correspondente no dicionário): a confirmação de colunas de 22/08/2026
  cobria só um subconjunto real do CSV — outras colunas relevantes
  (estabelecimento, lote/fabricante) também existem e estão em discussão
  pra novas dimensões (pedido 23/08/2026, ainda não implementado por
  causa do risco de cardinalidade — ver próximo adendo quando a decisão
  for fechada).
