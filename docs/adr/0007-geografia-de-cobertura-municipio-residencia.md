# ADR 0007: Geografia de cobertura — município/UF de residência com fallback

- **Status:** aceita
- **Data:** 2026-08-22
- **Responsável:** Giovanna

## Contexto

Cada dose aplicada carrega duas geografias possíveis: o município de
**aplicação** (`co_municipio_estabelecimento`/`sg_uf_estabelecimento`, onde a
dose foi dada) e o município de **residência** do paciente
(`co_municipio_paciente`/`sg_uf_paciente`, onde ele mora). O cálculo de
cobertura vacinal (doses aplicadas ÷ população-alvo, ver ADR 0001) só faz
sentido casando a geografia da dose com a geografia do denominador
populacional (censo/estimativa do IBGE, que é sempre por local de
residência) — usar aplicação misturaria gente que se vacina fora do
município onde mora (comum em regiões metropolitanas e polos de saúde) e
infla artificialmente a cobertura de quem tem grande estrutura de saúde e
esvazia a de municípios vizinhos.

Mas o dado real de residência não vem sempre completo: parte dos registros
tem `co_pais_paciente`/`co_municipio_paciente` vazios, e parte declara
residência em outro país (paciente estrangeiro vacinado no Brasil). Isso
foi confirmado numa amostra de 300 mil linhas reais (fev/2026):

| Caso | Ocorrências na amostra |
|---|---|
| `co_pais_paciente = 10` (Brasil) | 294.694 (~98,2%) |
| `co_pais_paciente` vazio | 5.298 (~1,8%) — nesses casos `co_municipio_paciente` também vem sempre vazio |
| `co_pais_paciente` estrangeiro (ex.: Paraguai=24, Bolívia=22) | 7 |

Precisamos de uma regra determinística de fallback pra chegar numa única
geografia de cobertura por dose, sem descartar registros.

## Opções consideradas

1. **Usar sempre o município de aplicação.** Mais simples e sempre
   preenchido, mas mede "onde vacina" em vez de "onde mora" — não serve
   pro indicador de cobertura por população residente, que é o insight
   alvo do projeto (ADR 0001).
2. **Usar sempre o município de residência, descartando registros
   incompletos/estrangeiros.** Preserva o significado do indicador, mas
   perde ~1,8%+ dos registros silenciosamente e não trata estrangeiros.
3. **Residência como principal, com fallback determinístico e uma
   categoria explícita pra "sem informação" e "estrangeiro".** Preserva o
   significado do indicador pro grosso dos dados e não descarta nenhum
   registro — cada um cai numa categoria explícita e auditável.

## Decisão

Dois campos derivados na silver (`stg_pni__doses_aplicadas`):
`municipio_cobertura` e `uf_cobertura`, resolvidos nesta ordem:

1. Se `co_pais_paciente` vier vazio/nulo → `uf_cobertura = 'SEM INFORMACAO'`,
   `municipio_cobertura = null` (mesma convenção já usada em
   `co_raca_cor_paciente = 99`, ver `docs/dicionario_dados.md`).
2. Senão, se `co_pais_paciente` for diferente de Brasil (`'10'`) →
   `uf_cobertura = 'ESTRANGEIRO'`, `municipio_cobertura = null`.
3. Senão (paciente brasileiro), se `co_municipio_paciente` vier vazio →
   usa o município/UF de **aplicação** como fallback:
   `municipio_cobertura = co_municipio_estabelecimento`,
   `uf_cobertura = sg_uf_estabelecimento`.
4. Senão → usa a residência normalmente:
   `municipio_cobertura = co_municipio_paciente`,
   `uf_cobertura = sg_uf_paciente`.

O caso 1 é checado antes do caso 3 porque, nos dados reais, todo registro
com país vazio também tem município de residência vazio — sem essa ordem,
esses registros cairiam no fallback de aplicação e se misturariam com os
casos de país=Brasil-mas-município-vazio, perdendo a distinção entre "não
sabemos o país" e "sabemos que é do Brasil, só falta o município".

**Refinamento (achado ao validar contra o dado real completo, 22/08/2026):**
depois de rodar `dbt build` com essa regra, um teste `not_null` em
`uf_cobertura` acusou 1.162 linhas nulas de 8,9M (fev/2026). Investigando
por que (consulta agregada no BigQuery, ver histórico do projeto): não é um
caminho novo do CASE — é que, nos casos 3 e 4 acima, o campo de sigla
(`sg_uf_paciente` ou `sg_uf_estabelecimento`) às vezes vem vazio **mesmo com
o código do município preenchido**. Como o código IBGE de município sempre
carrega a UF nos 2 primeiros dígitos (tabela fixa, nunca muda — diferente
do de-para pendente de `co_vacina`), a regra foi refinada pra **derivar a
UF a partir do próprio município** nesse caso, em vez de descartar a
informação: `uf_cobertura = coalesce(sigla_direta_do_csv,
uf_derivada_do_prefixo_do_municipio, 'SEM INFORMACAO')`. A tabela de
derivação está em `dbt/seeds/uf_ibge.csv`.

## Consequências

- A camada gold (fato de doses + dimensão de município) usa
  `municipio_cobertura`/`uf_cobertura`, nunca as colunas cruas de
  paciente/estabelecimento diretamente — isso desbloqueia os models de
  gold que dependiam desta decisão.
- A dimensão de município da gold precisa de uma linha "placeholder" (ou
  chave nula tratada) pra cobrir `municipio_cobertura is null` — casos
  1 e 2 acima. Fica registrado como próximo passo ao desenhar o modelo
  estrela.
- O indicador de cobertura vai ter uma fatia "SEM INFORMACAO" e uma fatia
  "ESTRANGEIRO" que não somam pra nenhum município/UF do Brasil — isso é
  intencional e deve aparecer explicitamente no Power BI (não escondido
  nem redistribuído), pra não inflar artificialmente a cobertura de UFs
  reais.
- Assume-se `co_pais_paciente = '10'` como código estável pra Brasil — 
  confirmado empiricamente contra o dado real (todas as 294.694 ocorrências
  de código `10` tinham `no_pais_paciente = 'BRASIL'` na amostra), mas não
  contra uma tabela de-para oficial do PNI (mesma pendência já registrada
  pra `co_vacina`/`co_dose_vacina`/`co_estrategia_vacinacao`).
- Com o refinamento, a estrutura do CASE + `COALESCE` final garante
  estruturalmente que `uf_cobertura` nunca fica nula — por isso o teste
  `not_null` em `uf_cobertura` foi promovido de `warn` pra `error`
  (`_silver__models.yml`): se voltar a falhar no futuro, é sinal de um
  caminho genuinamente novo (ex.: prefixo de município fora da tabela
  `uf_ibge`), não de ruído esperado do dado real.
