# ADR 0006: Estrutura do projeto dbt e isolamento por pessoa via schema custom

- **Status:** aceita
- **Data:** 2026-08-22
- **Responsável:** Giovanna

## Contexto

O projeto dbt precisava de uma estrutura antes que os models silver/gold de
verdade começassem a ser escritos pelo trio. Dois problemas concretos a
resolver logo de início:

1. A bronze não é gerida pelo dbt — é carregada por
   `ingestion/load_pni_csv.py` via load job (ADR 0002). O dbt só *lê* dela.
2. O IAM já configurado (ver handoff) dá a cada pessoa `Data Editor` **só**
   no próprio dataset `dev_<nome>`, nunca em `silver`/`gold` diretamente —
   só a service account `github-actions` (usada pelo GitHub Actions) tem
   `Data Editor` nesses datasets compartilhados. Isso significa que os
   models dbt de cada pessoa, quando rodados localmente, **precisam**
   materializar em `dev_<nome>`, nunca em `silver`/`gold` — senão a run
   falha por permissão (o que é o comportamento correto, não um bug).

O comportamento padrão do dbt-bigquery para "custom schemas" (a config
`+schema:` em `dbt_project.yml`) é *concatenar* o schema do target com o
schema custom (ex.: rodando com target `dev_giovanna` e `+schema: silver`
resultaria em tentar criar o dataset `dev_giovanna_silver`). Isso não
resolve o problema: cada pessoa continuaria sem conseguir apontar pro
dataset compartilhado real quando quisesse validar contra ele, e o nome do
dataset gerado seria estranho.

## Opções consideradas

1. **Deixar o comportamento padrão do dbt** (concatenar target + custom
   schema) — mais simples de configurar, mas cria datasets do tipo
   `dev_giovanna_silver` que não existem no IAM e não correspondem a nada
   que o BigQuery reconheça sem criar mais datasets (e mais permissões) só
   pra isso.
2. **Um profiles.yml por pessoa sem custom schema, todo mundo aponta pro
   próprio `dev_<nome>` para tudo** — simples, mas perde a separação
   silver/gold mesmo dentro do dataset de rascunho de cada um, e ninguém
   local conseguiria testar contra os datasets reais sem trocar
   manualmente a config toda vez.
3. **Macro `generate_schema_name` customizado** (o padrão recomendado pela
   própria documentação do dbt para este tipo de caso): dois targets no
   profile (`dev` e `ci`) e um macro que decide, em tempo de execução, se o
   schema custom (`silver`/`gold`) é respeitado como está ou se é ignorado
   em favor do dataset do target.

## Decisão

Opção 3. `dbt/macros/generate_schema_name.sql` faz: quando `target.name ==
'ci'`, os models materializam exatamente no schema custom (`silver` ou
`gold`, sem prefixo) — é o único target com permissão de escrita lá. Para
qualquer outro target (o `dev` de cada pessoa), o schema custom é
ignorado e tudo materializa no dataset do próprio target
(`dev_<nome>`), batendo exatamente com o que o IAM já permite.

`profiles.yml.example` documenta os dois targets. O `profiles.yml` real de
cada pessoa não é versionado (`.gitignore`); o target `ci` só existe de
fato dentro do GitHub Actions, montado em tempo de execução a partir do
secret `GCP_SA_KEY` (não a partir do arquivo do repo).

## Consequências

- Rodar `dbt build` localmente é sempre seguro: na pior hipótese, escreve
  no dataset de rascunho da própria pessoa, nunca em `silver`/`gold`.
- Só o pipeline do GitHub Actions (target `ci`, autenticado com a service
  account) escreve nos datasets compartilhados — center único de verdade
  para o que está "publicado" em silver/gold.
- Testar contra os datasets reais localmente exige rodar com
  `--target ci` e ter as credenciais da service account à mão — não é o
  fluxo do dia a dia, é intencional (evita escrita acidental fora do
  próprio sandbox).
- Assim como toda a documentação do projeto, este ADR e a estrutura do dbt
  foram criados incrementalmente, junto com o primeiro model real (ver
  `models/silver/stg_pni__doses_aplicadas.sql`), não deixados pro final.
