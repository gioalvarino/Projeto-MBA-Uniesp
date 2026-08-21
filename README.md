# Plataforma de Dados — Cobertura Vacinal (PNI/DataSUS)

Projeto de pós-graduação (trio) que transforma os CSVs mensais de doses aplicadas
do PNI (Programa Nacional de Imunizações) em um dashboard de cobertura vacinal,
com arquitetura medalhão no BigQuery, transformação em dbt e consumo em Power BI.

## Pipeline

```
01 Fonte → 02 Ingestão → 03 Transformação → 04 Dados preparados → 05 Insights
```

CSVs mensais do PNI → `ingestion/load_pni_csv.py` (load job, bronze particionada
por mês) → BigQuery bronze/silver/gold (dbt-bigquery) → GitHub Actions
(orquestração do dbt) → Power BI Desktop (consumo).

## Estrutura do repositório

- `ingestion/` — script de carga (`load_pni_csv.py`) e o que mais entrar na
  camada de ingestão.
- `dbt/` — projeto dbt (modelos silver/gold, testes, docs). A ser criado.
- `docs/adr/` — Architecture Decision Records. Toda decisão relevante do
  projeto entra aqui: contexto, opções avaliadas, escolha e consequência. É a
  peça mais importante para a banca — o enunciado pesa mais a justificativa
  das decisões do que a ferramenta escolhida.
- `docs/dicionario_dados.md` — de-para de colunas e códigos (vacina, dose,
  estratégia de vacinação).
- `docs/descartados/` — código e caminhos avaliados e não escolhidos,
  mantidos como evidência de que a alternativa foi construída e comparada
  (fortalece o ADR correspondente em vez de enfraquecê-lo).
- `.github/workflows/` — automação (dbt build, dbt docs generate, publicação
  no GitHub Pages).

## Time

| Frente | Responsável | Entregáveis |
|---|---|---|
| Engenharia | Giovanna | ingestão, projeto dbt, GitHub Actions, IAM/BigQuery |
| Dados e qualidade | a definir | modelos SQL silver/gold, testes em YAML, dicionário de dados |
| Consumo e narrativa | a definir | modelo estrela, Power BI, DAX, ADRs, README, apresentação |

Regra combinada: ninguém faz merge de código que não sabe explicar.

## Regras de trabalho

- Tudo que for produzido fica versionado neste repositório — nada de ajuste
  final feito fora do controle de versão.
- A documentação (`docs/`) evolui junto com o projeto: cada decisão relevante
  vira um ADR no momento em que é tomada, não no fim do semestre.
- `.pbix` é arquivo binário e não faz merge — uma dona por vez.

## Controle de custo (BigQuery)

O crédito de Free Trial do projeto já expirou, então não há colchão: qualquer
consulta acima do *always-free* (10 GiB armazenamento + 1 TiB consulta/mês) vai
direto ao cartão. Antes de qualquer carga real, configurar a cota diária de
consulta do BigQuery (barreira dura — recusa a consulta em vez de cobrar) e o
`maximum_bytes_billed` no `profiles.yml` do dbt. Detalhes e checklist completo
no handoff do projeto.

## Status atual

Ver `docs/adr/` para as decisões já tomadas e justificadas. Pendências
abertas estão registradas em cada ADR relevante e serão fechadas ao longo do
projeto.
