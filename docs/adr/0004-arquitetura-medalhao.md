# ADR 0004: Arquitetura medalhão (bronze / silver / gold)

- **Status:** aceita
- **Data:** 2026-08-21
- **Responsável:** trio

## Contexto

O pipeline precisa separar claramente responsabilidade de reprocessamento:
mudanças de regra de negócio não podem exigir voltar à fonte, e mudanças na
fonte não podem quebrar tudo a jusante.

## Decisão

Três camadas no BigQuery, orquestradas por dbt-bigquery:

- **bronze** — dado cru, todas as colunas `STRING`, particionado por mês,
  com `_carga_log` registrando cada carga (arquivo, hash, linhas,
  reconciliação).
- **silver** — tipagem, deduplicação por `codigo_documento`, padronização de
  nomes (sempre por código IBGE, nunca por nome de município),
  enriquecimento com Base dos Dados / IBGE.
- **gold** — modelo estrela: fato de doses aplicadas + dimensões (tempo,
  município, vacina, estabelecimento, faixa etária).

**Frase de defesa para a banca:** "separa responsabilidade de
reprocessamento — se a regra de negócio muda, reprocesso da bronze sem tocar
na fonte; se a fonte muda o schema, o impacto fica isolado na silver."

## Consequências

- Mais camadas de transformação dbt para manter, mas rastreabilidade e
  lineage automáticos (`dbt docs`) compensam o custo de manutenção.
- A tela de qualidade do Power BI se alimenta de `_carga_log` (bronze),
  tornando a evidência de qualidade parte do produto, não um anexo.
