# Dicionário de dados — PNI (doses aplicadas)

> **Atualizado em 22/08/2026 — nomes de coluna CONFIRMADOS** contra o
> cabeçalho real dos CSVs mensais baixados manualmente (jan–jul/2026). O
> CSV usa prefixos abreviados em português (`co_` código, `no_` nome, `dt_`
> data, `st_` status, `sg_` sigla, `tp_` tipo, `ds_` descrição, `nu_`
> número) — diferentes dos nomes por extenso do dicionário da API do PNI
> que orientou a primeira versão deste documento. A coluna "Campo (CSV)"
> abaixo é o nome real; `ingestion/load_pni_csv.py` sanitiza só acentos e
> caracteres inválidos, então o nome na bronze do BigQuery é o mesmo.
> Delimitador `;`, encoding não-UTF-8 (aparenta ISO-8859-1/Windows-1252 —
> caracteres acentuados aparecem corrompidos numa leitura direta em UTF-8).

## Campos-chave

| Campo (CSV) | Papel |
|---|---|
| `co_documento` | UUID por dose → chave única para deduplicação na silver |
| `dt_entrada_rnds` | Data de entrada no RNDS → mede a defasagem da fonte |
| `dt_deletado_rnds` | Exclusão lógica na origem → filtrar na silver |
| `dt_vacina` | Data do evento (vem com hora `00:00:00-03`; é DATE, não timestamp) |
| `co_municipio_estabelecimento` / `co_municipio_paciente` | Códigos IBGE — as duas geografias possíveis |
| `co_pais_paciente` | País de residência do paciente ('10' = Brasil). Usado na resolução de geografia de cobertura (ADR 0007) |
| `co_vacina`, `co_dose_vacina` | Códigos numéricos; precisam de de-para do dicionário oficial do PNI (pendente) |
| `co_estrategia_vacinacao` | Código da estratégia de vacinação; de-para pendente |
| `st_documento` | **Confirmado só `"final"`** nos 7 meses reais — sem valor analítico; removido da silver em 23/08/2026 (segue só na bronze) |
| `sg_uf_paciente` / `sg_uf_estabelecimento` | Sigla da UF — mais confiável que os nomes por extenso (`no_uf_*`) pra filtrar/agrupar |
| `nu_idade_paciente` | Idade do paciente — ver regra de qualidade abaixo |
| `co_raca_cor_paciente` / `no_raca_cor_paciente` | Código e nome de raça/cor (nome já vem pronto da fonte) |
| `tp_sexo_paciente` | Sexo do paciente (F/M/I/N — ver "Perfil demográfico" abaixo) |

A silver (`stg_pni__doses_aplicadas`, ver `dbt/`) renomeia estes campos de
volta para nomes por extenso (`codigo_documento`, `data_vacina` etc.) — a
abreviação fica só na bronze, fiel ao dado original.

## Geografia de cobertura (ADR 0007)

Resolvida na silver em dois campos novos, `municipio_cobertura` e
`uf_cobertura` — residência como principal (é a geografia que casa com o
denominador populacional do IBGE), com fallback pra aplicação quando a
residência não vem preenchida:

1. `co_pais_paciente` vazio → `uf_cobertura = 'SEM INFORMACAO'`, município nulo.
2. `co_pais_paciente` diferente de Brasil (`'10'`) → `uf_cobertura = 'ESTRANGEIRO'`, município nulo.
3. Brasileiro com município de residência vazio → usa município/UF de **aplicação**.
4. Brasileiro com residência preenchida → usa residência normalmente.

**Refinamento (achado real, 22/08/2026):** em 1.162 de 8,9M linhas (fev/2026),
o país é Brasil e o município vem preenchido, mas a sigla da UF (`sg_uf_paciente`)
vem vazia mesmo assim — inconsistência pontual na fonte. Nesse caso, a UF é
**derivada dos 2 primeiros dígitos do código IBGE do município** (seed
`dbt/seeds/uf_ibge.csv`, tabela fixa e estável — não é um de-para pendente
como `co_vacina`), em vez de cair em "SEM INFORMACAO" e descartar uma
informação que na verdade temos.

Ver `docs/adr/0007-geografia-de-cobertura-municipio-residencia.md` pro
raciocínio completo e os números reais que embasaram a regra.

## Perfil demográfico — raça/cor e sexo (adendo ADR 0008, 23/08/2026)

Resolvido na silver em três campos novos — `raca_cor_cobertura`,
`nome_raca_cor_cobertura` e `sexo_cobertura` — pra alimentar a dimensão
`dim_perfil_paciente` na gold, permitindo cobertura vacinal por
característica do vacinado.

Distribuição real, os 7 meses (jan–jul/2026, ~115M linhas):

| `tp_sexo_paciente` | Linhas |
|---|---|
| F | 63.844.931 |
| M | 51.311.897 |
| I (Ignorado) | 1.827 |
| N (provável erro de digitação da fonte) | 2 |

`I` e `N` viram `'SEM INFORMACAO'` em `sexo_cobertura` — nenhum registro
chegou com o campo de fato nulo.

| `co_raca_cor_paciente` | `no_raca_cor_paciente` | Linhas |
|---|---|---|
| 01 | BRANCA | 40.015.873 |
| 02 | PRETA | 3.902.212 |
| 03 | PARDA | 38.376.492 |
| 04 | AMARELA | 8.483.148 |
| 05 | INDIGENA | 729.758 |
| 99 | SEM INFORMACAO | 23.651.170 |
| NULL | NULL | 4 |

As 4 linhas nulas caem em `'99'`/`'SEM INFORMACAO'` em
`raca_cor_cobertura`/`nome_raca_cor_cobertura` — mesmo código que a fonte já
usa pra "sem informação" explícito. O nome já vem pronto da fonte, sem
precisar de um de-para externo como vacina/dose/estratégia.

## Códigos pendentes de de-para

- `co_vacina`
- `co_dose_vacina`
- `co_estrategia_vacinacao`

## Regras de qualidade conhecidas

- Nomes de município inconsistentes entre estabelecimento e paciente (ex.:
  "AREZ" no estabelecimento e "ARES" no paciente, mesmo código IBGE
  `240120`). **Regra: juntar sempre pelo código, nunca pelo nome.**
- `nu_idade_paciente = "0"` é bebê de menos de 1 ano, não idade faltante —
  cuidado ao montar faixas etárias.
- `co_municipio_paciente` vem nulo em parte dos registros — esses não
  entram no cálculo de cobertura por residência; contar e expor na tela de
  qualidade.
- CEP sujo — nulos e valores genéricos como `55000000`.
- `co_raca_cor_paciente = 99` ("SEM INFORMACAO") é muito frequente.
- `co_municipio_paciente`/`co_municipio_estabelecimento = '999999'` e
  `sg_uf_paciente`/`sg_uf_estabelecimento = 'XX'` são sentinelas de
  "ignorado" da fonte, não código IBGE/sigla de verdade (achado real,
  23/08/2026 — quebrava a chave única de `dim_municipio` nos 7 meses
  completos). Tratados como vazio na silver (ver ADR 0007, segundo
  refinamento).
- `ds_vacina_fabricante` nulo em parte dos registros.
- `no_fantasia_estalecimento` — o typo é da própria fonte (confirmado no
  CSV real, não é sanitização nossa). Mantido cru na bronze (fidelidade ao
  dado original), renomear só na silver.

## Volume real (arquivos baixados em 22/08/2026, jan–jul/2026)

CSVs uncompressed, um por mês:

| Mês | Tamanho (CSV, descompactado) |
|---|---|
| jan/2026 | 7,3 GB |
| fev/2026 | 5,4 GB |
| mar/2026 | 9,7 GB |
| abr/2026 | 16,7 GB |
| mai/2026 | 12,8 GB |
| jun/2026 | 10,5 GB |
| jul/2026 | 7,7 GB |
| **Total (7 meses)** | **~70 GB** |

Isso é muito maior que os 10 GiB de armazenamento sempre-gratuito do
BigQuery (ver ADR 0003) — carregar os 7 meses como estão é uma decisão de
escopo (custo real de armazenamento, ainda modesto mas não mais zero) que
precisa ser tomada conscientemente, não assumida. Ver pendência de recorte
de escopo no handoff do projeto.

## Validação end-to-end (22/08/2026)

Fevereiro/2026 carregado na bronze real (8.908.175 linhas, reconciliação
perfeita) e `dbt build` rodado contra `dev_giovanna`: a view
`stg_pni__doses_aplicadas` materializou e os 4 testes passaram
(PASS=5 WARN=0 ERROR=0), confirmando que o mapeamento de colunas e a
lógica de deduplicação (`QUALIFY ROW_NUMBER` por `codigo_documento`) estão
corretos contra dado real de produção — não só a amostra usada para
inspecionar o cabeçalho.
