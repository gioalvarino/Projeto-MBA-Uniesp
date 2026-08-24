# ADR 0010: Meta de cobertura vacinal — seed de referência

- **Status:** aceita
- **Data:** 2026-08-24
- **Responsável:** Giovanna

## Contexto

O insight alvo do projeto (ADR 0001) é "cobertura vacinal por município
contra a meta". Até aqui a fato/gold sabia calcular a cobertura (doses ÷
população, via `dim_municipio` — ADR 0009), mas não tinha a meta em lugar
nenhum pra comparar contra. Sem isso, o Power BI só mostra o valor absoluto,
não "está acima ou abaixo do que deveria".

## Pesquisa

Buscamos se a meta de cobertura vacinal do PNI varia por estado — não varia.
É um valor nacional único, o mesmo para todo estado/município; o que varia
de fato é a cobertura *alcançada*. Duas fontes usadas:

- Portal Médico/CFM, ["Brasil não cumpre meta de 95% em cobertura
  vacinal"](https://portal.cfm.org.br/noticias/vacinacao-precisa-avancar-para-seja-alcancada-a-meta-urgente-de-cobertura-vacinal-acima-de-95/)
  — confirma a meta nacional de 95% para a maioria dos imunizantes do
  calendário, sem distinção por região.
- APM, ["Brasil atingiu meta em apenas 3 das 19 vacinas para o público
  infantil"](https://www.apm.org.br/brasil-atingiu-meta-em-apenas-3-das-19-vacinas-para-o-publico-infantil-especialistas-apontam-risco/)
  — traz a lista completa das 19 vacinas do calendário infantil com a meta
  de cada uma (95%, 90% ou 80% conforme o imunizante), usada linha a linha
  no seed abaixo.
- SSIR, ["VacinaBR: as metas no mapa"](https://ssir.com.br/as-metas-no-mapa/)
  — confirma o padrão nacional único e contextualiza a desigualdade
  regional na cobertura *alcançada* (só 499 dos 5.570 municípios bateram
  todas as metas em 2023).

Consultado em 24/08/2026. São fontes jornalísticas/de análise em saúde
pública que citam dados do PNI/Ministério da Saúde, não a portaria oficial
em si — se a banca pedir a fonte primária, vale confirmar contra o
painel ImunizaSUS do Ministério da Saúde antes da apresentação final.

## Decisão

Criar `dbt/seeds/meta_vacinal.csv`: 19 linhas, uma por vacina/dose do
calendário infantil, com a meta oficial (`meta_cobertura`, fração de 0 a 1).

**Não** foi feito o join com `dim_vacina.nome_vacina`/`nome_dose` — essas
colunas vêm direto do `ds_nome`/`ds_tipo_dose` bruto do PNI (ex.: "vacina
febre amarela (atenuada)"), que tem ~90 variações reais e não bate
string-a-string com os 19 nomes oficiais do calendário usados aqui (ex.:
"Febre amarela"). Ligar as duas listas precisa do mesmo tipo de de-para
manual feito pra `co_vacina`/`co_dose_vacina` (ADR 0008, adendo
23/08/2026) — comparar as ~90 variações reais uma a uma contra as 19 linhas
do calendário e decidir a qual meta cada uma pertence (ex.: as várias
variações de "poliomielite" que existem na base real todas caem na mesma
meta de 95%, mas isso precisa ser verificado, não assumido).

## Consequências

- O seed já serve como referência solta no Power BI (ex.: linha de meta
  fixa nos gráficos de cobertura, comparação manual por vacina).
- Ainda não dá pra montar uma medida DAX tipo "cobertura ÷ meta" ligada
  automaticamente por vacina — falta o de-para acima. Fica registrado como
  pendência, no mesmo padrão das dimensões de estabelecimento/lote
  adiadas (README, "Pendências em aberto").
- Sem custo de BigQuery: é só mais um seed pequeno, mesmo padrão de
  `uf_ibge.csv`/`faixa_etaria.csv`.
