# Plataforma de Dados — Cobertura Vacinal (PNI/DataSUS)

Projeto de pós-graduação (trio) que transforma os CSVs mensais de doses aplicadas
do PNI (Programa Nacional de Imunizações) em um dashboard de cobertura vacinal,
com arquitetura medalhão no BigQuery, transformação em dbt e consumo em Looker
Studio (Google Data Studio) — ver adendo 27/08/2026 do ADR 0011: o Power BI foi
avaliado no início do projeto, mas abandonado como ferramenta de consumo (não
roda no Linux de um dos integrantes do trio).

## Pipeline

```
01 Fonte → 02 Ingestão → 03 Transformação → 04 Dados preparados → 05 Insights
```

CSVs mensais do PNI → `ingestion/load_pni_csv.py` (load job, bronze particionada
por mês) → BigQuery bronze/silver/gold (dbt-bigquery) → GitHub Actions
(orquestração do dbt) → Looker Studio, conectado direto (sem Extract Data) na
tabela larga `mart_cobertura_vacinal` (consumo).

A gold mantém o modelo estrela de verdade (`fct_cobertura_vacinal` + 5
dimensões, ADR 0008) — testado e válido — mas quem alimenta o dashboard é a
tabela larga denormalizada `mart_cobertura_vacinal` (ADR 0011): o Looker
Studio não tem modelagem relacional (não dá pra definir relação fato ↔
dimensão como no Power BI), então cada linha da mart já vem com o nome de
todas as dimensões. O modelo estrela segue existindo como desenho correto da
gold e porta aberta pra um Power BI futuro, mas não é o caminho atual até a
visualização.

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
| Engenharia e dados | Giovanna | ingestão, projeto dbt (models silver/gold, testes, seeds), modelo estrela, GitHub Actions, IAM/BigQuery, dicionário de dados, ADRs, README |
| Consumo e narrativa | Ellen e Andressa | dashboard no Looker Studio (4 páginas: Visão Geral, Análise Territorial, Perfil da População, Sazonalidade & Oportunidades — filtros, gráficos e cartões conectados direto na gold), apresentação |

Regra combinada: ninguém faz merge de código que não sabe explicar.

## Regras de trabalho

- Tudo que for produzido fica versionado neste repositório — nada de ajuste
  final feito fora do controle de versão.
- A documentação (`docs/`) evolui junto com o projeto: cada decisão relevante
  vira um ADR no momento em que é tomada, não no fim do semestre.
- O painel final vive no Looker Studio (nuvem, fora do repositório) — não há
  mais arquivo binário (`.pbix`) pra versionar/mergear; o dashboard é editado
  direto na conta Google da Giovanna. O que fica versionado aqui é o que
  gera o dado que ele consome: os models dbt (inclusive `mart_cobertura_vacinal`,
  ADR 0011) e as decisões em ADR.

## Controle de custo (BigQuery)

Qualquer consulta acima do *always-free* (10 GiB armazenamento + 1 TiB
consulta/mês) vai direto ao cartão. Antes de qualquer carga real, configurar a
cota diária de consulta do BigQuery (barreira dura — recusa a consulta em vez
de cobrar) e o `maximum_bytes_billed` no `profiles.yml` do dbt. Detalhes e
checklist completo no handoff do projeto.

## Status atual

Ver `docs/adr/` para as decisões já tomadas e justificadas. Pendências
abertas estão registradas em cada ADR relevante e serão fechadas ao longo do
projeto. Mudança mais recente: troca da ferramenta de consumo de Power BI
para Looker Studio, com conexão direta ao BigQuery (adendo 27/08/2026 do
ADR 0011) — o modelo estrela da gold continua existindo, mas o dashboard
consome a tabela larga `mart_cobertura_vacinal`, não o modelo dimensional.
