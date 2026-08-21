# ADR 0003: BigQuery com billing habilitado (não sandbox)

- **Status:** aceita
- **Data:** 2026-08-21
- **Responsável:** trio

## Contexto

O projeto precisava de um data warehouse gratuito ou quase gratuito,
acessível pelas três integrantes sem instalar servidor, com um adapter dbt
maduro.

## Opções consideradas

| Opção | Motivo do descarte |
|---|---|
| **Apache Hop** (ETL visual, grátis) | Capaz — testes unitários com golden datasets, cobre ingestão+transformação+orquestração — mas nivela o time por baixo, e o trio tem quem programa. Perde no que a banca vê: diff legível em PR, lineage automático, docs publicadas. |
| **PostgreSQL gratuito** (Neon 0,5 GB / Supabase 500 MB) | Espaço insuficiente sem recortar agressivamente a fonte. |
| **BigQuery sandbox** (sem cartão) | Tabelas expiram em 60 dias — o projeto morreria pouco depois da apresentação. Não suporta DML, fechando a porta para `MERGE` futuro na silver. |
| **Microsoft Fabric** (trial 60 dias) | Tecnicamente forte (Direct Lake), mas o relógio de 60 dias é o maior risco de cronograma. Exige as três no mesmo tenant. |
| **Databricks Free Edition** | 1 workspace por conta, sem console de conta nem SCIM — uso individual, não de time. |
| **MotherDuck Free** | Compartilhamento de banco só a partir do plano Pro. |
| **dbt Cloud** | Plano gratuito com 1 assento de desenvolvedor só. |
| **DuckDB local** | O arquivo `.duckdb` não versiona nem compartilha entre as três máquinas. |
| **Cloud Composer / Cloud Scheduler** | Complexidade e custo sem ganho — GitHub Actions resolve o agendamento sem servidor e com log visível para o trio. |

## Decisão

BigQuery com billing habilitado. *Always-free* permanente de 10 GiB de
armazenamento + 1 TiB de consulta por mês. Billing elimina a expiração
automática de 60 dias do sandbox e libera DML (`MERGE`/`UPDATE`), útil na
silver.

## Consequências

- Sem colchão de crédito: o Free Trial já expirou, então qualquer gasto
  acima do *always-free* vai direto ao cartão.
- Exige cota diária de consulta configurada como barreira dura **antes da
  primeira carga** — é a única proteção que recusa a consulta em vez de
  cobrar.
- Datasets criados antes de habilitar o billing mantêm expiração padrão de
  60 dias — remover manualmente o *default table expiration* de cada um.
- Decisão explícita de **não** criar uma segunda conta Google para obter
  novo trial: viola os termos de uso, arrisca suspensão da conta, e não
  resolveria o problema real (que não é falta de crédito, e sim manter o
  projeto dentro do always-free de forma permanente).
