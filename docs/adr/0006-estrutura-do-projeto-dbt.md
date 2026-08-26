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

## Adendo (26/08/2026) — CI nunca tinha rodado um `dbt build` de verdade

Achado real: Ellen e Andressa não conseguiam ver nenhuma tabela em
`gold` — só existiam em `dev_giovanna`. Isso não é falha do desenho acima
(que continua correto): é porque `.github/workflows/pipeline.yml` (o único
lugar com permissão de escrita em `silver`/`gold`) ficou rodando só `dbt
debug` + `dbt compile` desde que foi criado — um placeholder de quando a
bronze ainda não tinha dado real, nunca atualizado depois que os 7 meses
foram carregados (item já registrado como pendência de baixa prioridade).
Ou seja: o mecanismo pra publicar no compartilhado sempre existiu e estava
certo, só nunca tinha sido de fato acionado.

Corrigido: o workflow agora roda `dbt build` (não só debug/compile).
Também removido o gatilho de agendamento diário (`schedule: cron`), ficando
só o disparo manual (`workflow_dispatch`, botão "Run workflow" na aba
Actions do GitHub) — não há mais carga nova prevista antes da apresentação
de 29/08, então rodar todo dia sem necessidade só geraria custo à toa
(regra do projeto de reduzir consultas que geram cobrança). Cada run é
limitada por `maximum_bytes_billed` no profile do CI, mesma proteção de
sempre.

## Adendo (26/08/2026, 2) — primeira run real falhou por limite baixo demais

A primeira run com `dbt build` de verdade (run #8) falhou: dois testes
`not_null` na silver (`stg_pni__doses_aplicadas`) precisaram de ~10 GB e
~14,14 GB, estourando o `maximum_bytes_billed` de 10 GB que o profile `ci`
tinha até então. Como um teste que falha derruba (SKIP) tudo que depende
dele no `dbt build`, essa run não publicou nenhuma das 7 tabelas gold no
dataset compartilhado — o mesmo motivo, então, pelo qual Ellen e Andressa
ainda não viam nada em `gold` mesmo depois do fix acima.

Este é exatamente o mesmo problema (e mesma causa: a silver é uma view que
recomputa a transformação inteira dos 7 meses reais a cada teste) já
resolvido no profile `dev` em 23/08/2026 — só que a correção não tinha sido
replicada no profile `ci`. Corrigido: `maximum_bytes_billed` do profile
`ci` (dentro de `.github/workflows/pipeline.yml`) subido de 10 GB para
20 GB, igualando o `dev`.
