# ADR 0009: Enriquecimento de município — nome e população via Base dos Dados/IBGE

- **Status:** aceita
- **Data:** 2026-08-23
- **Responsável:** Giovanna

## Contexto

O ADR 0004 já previa esse enriquecimento acontecendo na silver, e o ADR 0001
registra o insight alvo do projeto: cobertura vacinal por município cruzando
com população do IBGE. Sem nome e população reais, `dim_municipio` (ADR
0007 + ADR 0008) só permitia contar doses, não calcular a taxa de cobertura
(doses ÷ população) — o indicador central do produto. Com o modelo estrela
inteiro já validado contra os 7 meses reais, esse era o próximo bloqueio
real.

## Opções consideradas

1. **Baixar uma planilha/CSV oficial do IBGE (população estimada) e
   versionar como seed**, igual `uf_ibge.csv`/`faixa_etaria.csv`. Simples e
   sem dependência externa em tempo de consulta, mas exige atualização
   manual a cada nova estimativa do IBGE, e nome de município já é uma
   tabela maior (5.570 linhas) que não muda com frequência suficiente pra
   justificar reprocessar/versionar à mão.
2. **Consultar o dataset público da Base dos Dados diretamente no
   BigQuery** (`basedosdados.br_bd_diretorios_brasil.municipio` e
   `basedosdados.br_ibge_populacao.municipio`), via `source()` do dbt. Sem
   cópia de dado, sem custo de armazenamento nosso, mesma fonte (IBGE) já
   tratada e num formato que casa direto com o código de município que já
   usamos (`id_municipio`, 7 dígitos). Dependência de um projeto público de
   terceiros permanecer disponível — aceitável pro escopo do projeto.

## Decisão

Consultar a Base dos Dados diretamente como `source` do dbt, num novo model
de silver (`stg_ibge__municipios`) — schema confirmado contra o dado real
em 23/08/2026. `dim_municipio` (gold) passa a fazer `left join` desse model
por `id_municipio = municipio_cobertura`.

**População:** estimativa de **2025** por padrão (ano mais recente
disponível), com fallback pro ano anterior mais recente que tiver valor
preenchido, por município — ver "Refinamento" abaixo. É estimativa, não
censo, e não é o mesmo ano dos dados de vacinação (2026) — melhor
aproximação disponível. `dim_municipio` expõe `ano_populacao` pra deixar
explícito de qual ano veio a estimativa usada em cada linha.

**Refinamento (achado real, 23/08/2026):** o primeiro `dbt build` acusou 1
`warn` — `Boa Esperança do Norte/MT` (`5101837`), município antigo e já
estabelecido (não é criação recente por desmembramento), com `populacao`
nula pra `ano=2025`. Ajustei `stg_ibge__municipios` pra usar a estimativa
mais recente disponível **com valor preenchido** (`populacao is not null`)
até 2025, em vez de exigir exatamente 2025 — pensado pra autocorrigir
lacunas pontuais de um ano específico. O `warn` persistiu depois do
ajuste; não deu pra confirmar por consulta direta se esse município tem
valor preenchido em algum ano anterior na Base dos Dados (consulta travou
sem retornar), então fica registrado como **limitação aceita**: 1 de 5.570
municípios (0,018%) sem população disponível na fonte, por motivo não
totalmente investigado. O ajuste de "ano mais recente com valor" continua
correto e é mantido (resolve o caso geral e qualquer lacuna de só-um-ano
que apareça no futuro); esse caso específico só não tem dado nenhum pra
usar.

## Segundo refinamento (achado real, 23/08/2026 — ao conectar o Power BI)

Depois de conectar o Power BI, Giovanna reparou que `dim_municipio` tinha
carregado com `nome_municipio`/`populacao`/`ano_populacao` **vazios pra
TODOS os municípios**, não só o caso isolado de Boa Esperança do
Norte/MT do refinamento acima. Diagnóstico: `municipio_cobertura` (vindo
de `co_municipio_paciente`/`co_municipio_estabelecimento` na bronze) usa
o código **legado de 6 dígitos** que o DATASUS/SUS usa historicamente
(ex. `110001`), não o código de 7 dígitos do IBGE (`1100015`) que a Base
dos Dados usa em `id_municipio` — o 7º dígito é um dígito verificador,
calculado a partir dos 6 primeiros. A suposição original deste ADR
("`id_municipio` é o mesmo código de 7 dígitos usado em
`municipio_cobertura`") estava errada. O join original comparava strings
de tamanhos diferentes e nunca batia — passou pelo `dbt build` de
23/08/2026 sem erro porque **não existia teste de `not_null` em
`nome_municipio`/`populacao` na própria `dim_municipio`**; o único teste
relacionado (`not_null` em `stg_ibge__municipios.populacao`) testa a Base
dos Dados isoladamente, sem envolver o join com o PNI — por isso o bug não
apareceu mesmo com o WARN=1 já presente naquele build (esse WARN é sobre o
caso isolado do refinamento acima, não sobre o join).

**Correção:** `stg_ibge__municipios` passa a expor `id_municipio_6d`
(`substr(id_municipio, 1, 6)`, truncando o dígito verificador), e
`dim_municipio` faz o `left join` por `id_municipio_6d` em vez de
`id_municipio`. Testes de `unique`/`not_null` adicionados em
`id_municipio_6d` e, mais importante, testes de `not_null` novos em
`dim_municipio.nome_municipio` (severity error) e `dim_municipio.populacao`
(severity warn, mesmo motivo do caso isolado) com `where: tipo_registro =
'Município válido'` — esses testes não existiam antes e são o motivo de o
bug ter passado despercebido por um build inteiro. Pendente: revalidar com
`dbt build` que o join agora bate pra (quase) todos os 5.570 municípios.

## Consequências

- `dim_municipio.nome_municipio`/`populacao`/`ano_populacao` passam a vir
  preenchidos pra município real; continuam nulos só pros membros
  especiais ('ESTRANGEIRO'/'SEM INFORMACAO', sem código IBGE de verdade
  pra casar).
- Município real que não casar com a Base dos Dados (código descontinuado,
  por exemplo), ou que não tenha NENHUM ano com população preenchida (1
  caso conhecido, Boa Esperança do Norte/MT), também fica com
  nome/população nulos — teste `not_null` em `populacao` fica como `warn`
  em `stg_ibge__municipios` de propósito, pra sinalizar sem travar o
  pipeline por 1 caso isolado e não solucionável do nosso lado.
- A taxa de cobertura (doses ÷ população) já pode ser calculada no Power BI
  a partir daqui — desbloqueia o insight alvo do ADR 0001.
- Consulta a dataset público não copia dado pro nosso projeto (sem custo de
  armazenamento) e o volume consultado é pequeno (~5,6 mil municípios) —
  custo de processamento irrisório, dentro do free tier de 1 TB/mês.
- Diferente de `co_vacina`/`co_dose_vacina`/`co_estrategia_vacinacao`, esse
  de-para não depende de uma tabela oficial pendente do PNI — a Base dos
  Dados já resolve nome e população de município de forma completa.

## Terceiro refinamento (24/08/2026) — macro-região do Brasil

Pedido: acrescentar a região (Norte/Nordeste/Centro-Oeste/Sudeste/Sul) em
`dim_municipio`, pra permitir corte regional além de UF/município.

Antes de criar um seed novo (padrão `uf_ibge.csv`), checamos se a própria
fonte já não trazia essa informação — e trazia: a tabela
`basedosdados.br_bd_diretorios_brasil.municipio` (a mesma já usada em
`stg_ibge__municipios` pra nome/UF) tem uma coluna `regiao` nativa.
Confirmado num exemplo de consulta publicado pela própria Base dos Dados
([artigo oficial no dev.to](https://dev.to/basedosdados/entenda-como-nossa-base-de-diretorios-brasileiros-facilita-sua-vida-27ji),
consultado 24/08/2026) que faz `SELECT ... regiao ... FROM
basedosdados.br_bd_diretorios_brasil.municipio` — confirma o nome exato da
coluna nessa mesma tabela.

**Decisão:** sem seed novo. `stg_ibge__municipios` passa a expor a
macro-região (`nome_regiao`) e `dim_municipio` expõe a mesma coluna. Zero
custo adicional — é a mesma tabela pública já consultada, só mais uma
coluna no SELECT.

**Pendente (na época):** a grafia exata dos 5 valores (acentos, hífen em
"Centro-Oeste") ainda não foi confirmada contra o dado real — o teste
`accepted_values` em `stg_ibge__municipios.nome_regiao` está em `warn` até
o próximo `dbt build` confirmar.

## Quarto refinamento (24/08/2026) — correção do nome real da coluna-fonte

O `dbt build` de 24/08/2026 (rodando `stg_ibge__municipios` já com a coluna
de região) falhou com `Unrecognized name: regiao` — a hipótese deste ADR
("a coluna se chama `regiao` na fonte, confirmado pelo tutorial da Base dos
Dados") estava errada. Giovanna rodou uma consulta direta de metadados
(`INFORMATION_SCHEMA.COLUMNS`, custo irrisório — é metadado, não dado) contra
`basedosdados.br_bd_diretorios_brasil.municipio` e confirmou o schema real:
a coluna já se chama **`nome_regiao`** na própria fonte (não `regiao`) —
o tutorial externo usado como referência estava desatualizado ou se referia
a uma versão/tabela diferente do dataset.

**Correção:** `stg_ibge__municipios` passa a fazer `select nome_regiao`
direto (sem `as`, já que o nome de origem e o nome usado no projeto
coincidem). Nenhuma outra mudança necessária — `dim_municipio` já
referenciava `nome_regiao` (o nome de saída, que não mudou).

**Lição registrada:** confirmar schema real via `INFORMATION_SCHEMA` antes
de confiar em documentação/tutorial de terceiros pra nome de coluna, mesmo
quando a fonte parece autoritativa (nesse caso, o próprio blog oficial da
Base dos Dados).

## Quinto refinamento (24/08/2026) — 45 municípios sem join após carga dos 7 meses completos

Primeiro `dbt build` de `dim_municipio` contra os 7 meses completos (antes
só fevereiro tinha sido validado): 45 códigos com `tipo_registro =
'Município válido'` ficaram sem `nome_municipio`/`nome_regiao` — a falha
de teste (severity error) acusou o problema, exatamente a intenção dos
testes adicionados no 2º refinamento. Investigação via consulta direta em
`dim_municipio` (barata — só 5,6 mil linhas) revelou 2 padrões claros nos
45 códigos:

1. **31 códigos são Regiões Administrativas do Distrito Federal**
   (`530020`–`530135`, `539901`–`539934`): o DATASUS/SUS usa código
   próprio pra cada Região Administrativa do DF (Taguatinga, Ceilândia,
   Samambaia, Águas Claras etc.) — uso comum em dados de saúde do DF, já
   que os serviços são organizados por RA. O IBGE, porém, reconhece o DF
   como **um único município legal** (Brasília, `5300108`) — nenhuma RA é
   município separado, por isso nenhuma bate com a Base dos Dados.
2. **9 códigos terminam em `'0000'`** (`210000` MA, `230000` CE, `260000`
   PE, `290000` BA, `310000` MG, `320000` ES, `350000` SP, `410000` PR,
   `420000` SC) — um por estado, sem repetição. Padrão de sentinela do
   DATASUS pra "UF conhecida, município não informado" (mesma família de
   ideia do `999999`/`XX` já tratado no ADR 0007, só que codificado como
   UF real + zeros em vez de um valor claramente inválido).

Restam **5 códigos sem padrão identificado**: `430145` (RS) e
`520100`/`520210`/`520900`/`520950` (GO). Não reconhecemos o padrão (podem
ser municípios incorporados/renomeados ao longo do tempo, ou outro tipo de
código regional de saúde específico de GO) — não investigado a fundo por
causa do prazo até a apresentação (29/08/2026).

**Decisão (pedido explícito da Giovanna, 24/08/2026):** corrigir os 40
casos explicados agora, aceitar os 5 residuais como limitação documentada:

- Regiões Administrativas do DF → `nome_municipio`/`nome_regiao`/
  `populacao` preenchidos por aproximação, usando os dados de Brasília
  (`id_municipio_6d = '530010'`) — `tipo_registro` vira `'Região
  administrativa do DF (aprox. Brasília)'` pra deixar explícito que é
  aproximação, não o nome real da RA.
- Sentinelas "UF sem município" → `nome_regiao` preenchido só a partir da
  UF (a região não depende do município específico — basta agrupar o
  diretório do IBGE por `sigla_uf`); `nome_municipio` continua nulo (não
  existe município real pra nomear). `tipo_registro` vira `'UF sem
  município específico'`.
- Os 5 residuais continuam com `tipo_registro = 'Município válido'` e
  `nome_municipio`/`nome_regiao` nulos — mesmo tratamento do caso isolado
  de Boa Esperança do Norte/MT (população nula): teste de `not_null`
  rebaixado de error pra warn, documentado como limitação aceita.

## Consequências (5º refinamento)

- `dim_municipio.tipo_registro` ganha 2 valores novos — qualquer análise
  em Power BI que filtre por "Município válido" precisa decidir se inclui
  ou não as Regiões Administrativas do DF (que representam doses reais
  aplicadas, só não distinguidas entre si).
- A cobertura vacinal do DF fica agregada num único "município"
  (Brasília) em vez de 31 — perda de granularidade dentro do DF, mas sem
  perder nenhuma dose do cálculo geral.
- 5 códigos (0,09% dos ~5.600 principais) seguem sem nome/região — aceito
  como limitação, igual ao caso já documentado de Boa Esperança do
  Norte/MT.

## Sexto refinamento (24/08/2026) — nome_regiao nulo pros membros especiais

Pedido da Giovanna: `nome_regiao` ficava vazio pros dois membros especiais
da dimensão — `chave_municipio = 'SEM INFORMACAO'` e `chave_municipio =
'ESTRANGEIRO'` — porque a CTE `uf_regiao` (usada como fallback de região
por UF, criada no 5º refinamento) faz `join` por `sigla_uf = uf_cobertura`,
e nenhuma delas é uma sigla de UF real, então nunca casava com o
diretório do IBGE. Diferente dos casos do 5º refinamento (Regiões
Administrativas do DF, sentinelas "UF+0000"), aqui não existe região
geográfica nenhuma pra resolver — são categorias de "não é Brasil" ou
"não sabemos onde" —, então nulo até fazia sentido semanticamente, mas
lia como join quebrado num relatório de Power BI (mesmo risco de
confusão do 2º refinamento, só que numa coluna diferente).

**Decisão:** em vez de nulo, `nome_regiao` repete o próprio valor de `uf`
para esses dois membros — ou seja, fica `'SEM INFORMACAO'`/`'ESTRANGEIRO'`
também em `nome_regiao`, não uma macro-região real do Brasil. Implementado
como mais um `coalesce` no `select` de `dim_municipio`, sem precisar de
join novo nem de seed.

**Consequências:**
- `nome_regiao` deixa de ser nulo pra qualquer linha de `dim_municipio` —
  os únicos campos que continuam nulos pros membros especiais são
  `nome_municipio` e `populacao` (não têm equivalente sensato pra repetir).
- Nenhum teste mudou: o `not_null` de `nome_regiao` já era escopado a
  `where: tipo_registro = 'Município válido'`, que nunca incluiu os
  membros especiais — o comportamento dos testes automatizados não é
  afetado por essa mudança.
- Zero custo adicional — é lógica pura de `CASE`/`COALESCE` em cima de
  colunas já presentes na consulta, sem novo join nem novo bytes
  escaneados de fonte externa.
