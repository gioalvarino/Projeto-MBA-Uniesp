{#
  Por que este macro existe (ver ADR 0006):

  O trio trabalha com datasets fixos no BigQuery (bronze/silver/gold, criados
  fora do dbt) e cada pessoa tem seu próprio dataset de rascunho (dev_<nome>).
  O comportamento padrão do dbt-bigquery gera datasets combinando o schema do
  target com o schema custom (`+schema:` em dbt_project.yml), o que criaria
  datasets do tipo `dev_giovanna_silver` — não é o que queremos.

  Regra adotada (é o macro recomendado pela própria documentação do dbt,
  adaptado aos dois targets deste projeto — ver profiles.yml.example):
    - target `ci`  -> usa o schema custom (silver/gold) *sozinho*, sem prefixo.
      É o único target com permissão de escrita nos datasets compartilhados
      (IAM: só a service account github-actions tem Data Editor em
      bronze/silver/gold).
    - qualquer outro target (ex.: `dev`, o de cada pessoa) -> ignora o schema
      custom e usa sempre o dataset do próprio target (dev_<nome>). Isso é
      proposital: cada pessoa só tem Data Editor no seu dev_<nome>, então
      silver e gold "de teste" de cada um ficam isoladas ali, sem risco de
      escrever (ou tentar escrever, e falhar por IAM) em cima dos datasets
      compartilhados.
#}

{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}

    {%- if target.name == 'ci' -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ default_schema }}
    {%- endif -%}

{%- endmacro %}
