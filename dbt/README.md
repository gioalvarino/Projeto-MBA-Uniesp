# Projeto dbt

Transforma a bronze (carregada por `ingestion/load_pni_csv.py`) em silver e
gold. Ver [`docs/adr/0004-arquitetura-medalhao.md`](../docs/adr/0004-arquitetura-medalhao.md)
para a justificativa da separação em camadas e
[`docs/adr/0006-estrutura-do-projeto-dbt.md`](../docs/adr/0006-estrutura-do-projeto-dbt.md)
para como o projeto dbt em si está organizado (schemas, targets).

## O que já existe

- `models/silver/_silver__sources.yml` — a bronze declarada como source
  (`bronze.doses_aplicadas_pni`, `bronze._carga_log`). **Os nomes de coluna
  ainda não foram confirmados contra o CSV real** — ver o aviso no próprio
  arquivo.
- `models/silver/stg_pni__doses_aplicadas.sql` — primeiro model: tipagem
  básica + deduplicação por `codigo_documento` + regras de qualidade já
  conhecidas (`docs/dicionario_dados.md`).
- `models/silver/_silver__models.yml` — testes desse model (`unique`,
  `not_null`, `accepted_values`).
- `macros/generate_schema_name.sql` — faz cada pessoa materializar no
  próprio `dev_<nome>` e só o CI materializar de fato em `silver`/`gold`.

## O que ainda falta

- Confirmar o cabeçalho real do CSV (`--dry-run`) e ajustar os nomes de
  coluna em `_silver__sources.yml`/`stg_pni__doses_aplicadas.sql` se
  necessário.
- Models de `gold/`: modelo estrela (fato de doses aplicadas + dimensões de
  tempo, município, vacina, estabelecimento, faixa etária) — depende da
  decisão de município de aplicação vs. residência (pendência aberta) e do
  enriquecimento com Base dos Dados/IBGE.
- Trocar os passos de `dbt debug`/`dbt compile` do
  `.github/workflows/pipeline.yml` por `dbt build` de verdade assim que a
  bronze tiver dados carregados (hoje o build falharia: a view da silver
  referencia uma tabela que ainda não existe, porque nenhum CSV foi
  carregado ainda).

## Rodando localmente

1. Instalar as dependências: `pip install -r requirements.txt` (na raiz do
   repo).
2. Autenticar: `gcloud auth application-default login`.
3. Copiar `profiles.yml.example` para `~/.dbt/profiles.yml` e trocar
   `dev_giovanna` pelo seu próprio dataset (`dev_<nome>`).
4. Dentro de `dbt/`: `dbt debug` (testa a conexão) e `dbt build` (roda os
   models + testes — vai materializar no seu `dev_<nome>`, nunca em
   `silver`/`gold` diretamente, ver ADR 0006).

`profiles.yml` **não** é versionado (está no `.gitignore`) — cada pessoa
mantém o seu, com `maximum_bytes_billed: 10000000000` (proteção de custo,
ver ADR 0003).
