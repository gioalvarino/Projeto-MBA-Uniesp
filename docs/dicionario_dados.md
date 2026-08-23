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
| `co_vacina`, `co_dose_vacina` | Códigos numéricos; nome já vem pronto na própria fonte (`ds_nome`, `ds_tipo_dose` — achado real 23/08/2026, ver seção "De-para" abaixo) |
| `co_estrategia_vacinacao` | Código da estratégia de vacinação; nome pronto em `no_estrategia` (mesmo achado) |
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

## De-para de vacina/dose/estratégia — RESOLVIDO (achado real, 23/08/2026)

Ao conectar o Power BI, percebemos que a bronze tem MUITO mais colunas do
que o subconjunto documentado em 22/08/2026 (ver "Cabeçalho completo da
bronze" abaixo) — e três delas já trazem o nome pronto por linha:

| Código | Nome (coluna da fonte) |
|---|---|
| `co_vacina` | `ds_nome` |
| `co_dose_vacina` | `ds_tipo_dose` |
| `co_estrategia_vacinacao` | `no_estrategia` |

Validado 1-pra-1 contra os 7 meses reais antes de aplicar (mesma checagem
feita pra raça/cor): nenhum código apareceu com mais de um nome distinto.
Amostra real (23/08/2026):

- `co_vacina`/`ds_nome`: 90 códigos distintos, ex. `14` → "vacina febre
  amarela (atenuada)" (5.045.301 doses), `33` → "vacina influenza
  trivalente (fragmentada, inativada)" (44.115.030 doses).
- `co_dose_vacina`/`ds_tipo_dose`: ex. `1` → "1ª Dose" (19.451.296), `9` →
  "Única" (52.454.494), `38` → "Reforço" (10.251.872).
- `co_estrategia_vacinacao`/`no_estrategia`: os 16 códigos batem com a
  tabela oficial do RNDS pra 1-9 (ver pesquisa abaixo) **e também** cobrem
  10-15 com nome próprio (`10` Pesquisa, `11` Pré-exposição, `12`
  Pós-exposição, `13` Reexposição, `14` Vacinação Escolar, `15` Operação
  Gota) — resolve de vez o range que a tabela do RNDS não cobria. Código
  `0` e nulo (`NULL`) não têm nome na fonte — ambos caem em `'SEM
  INFORMACAO'`, mesmo padrão das outras dimensões pequenas.

**Implementado em `stg_pni__doses_aplicadas`** (`nome_vacina_cobertura`,
`nome_dose_cobertura`, `nome_estrategia_cobertura`) e propagado pra
`dim_vacina.nome_vacina`/`nome_dose` e
`dim_estrategia_vacinacao.nome_estrategia` na gold — nenhuma das três
pendências abaixo (pesquisa de 23/08/2026, mantida por registro histórico)
precisou ser usada.

<details>
<summary>Pesquisa de de-para externo feita em 23/08/2026 (superada pelo achado acima, mantida só como registro)</summary>

- `co_estrategia_vacinacao`: existe uma tabela oficial do RNDS/Ministério
  da Saúde (`CodeSystem BREstrategiaVacinacao`), com 9 valores fixos (1
  Rotina, 2 Especial, 3 Bloqueio, 4 Intensificação, 5 Campanha
  indiscriminada, 6 Campanha seletiva, 7 Soroterapia, 8 Serviço Privado, 9
  Monitoramento rápido de cobertura vacinal). Não cobria os códigos 10-15
  — resolvido pelo achado acima (`no_estrategia` já traz nome pra todos).
- `co_vacina`/`co_dose_vacina`: só se achou uma tabela de referência
  estadual (Goiás, guia de implementação FHIR), não confirmada como a
  tabela nacional do SI-PNI — ficou sem uso, resolvido pelo achado acima
  (`ds_nome`/`ds_tipo_dose`).
- Os manuais oficiais do SI-PNI não puderam ser acessados (infraestrutura
  antiga, erros de redirecionamento/timeout) — não foi mais necessário.
</details>

## Cabeçalho completo da bronze (achado real, 23/08/2026)

A confirmação de 22/08/2026 (seção acima) listou só um subconjunto do
cabeçalho real do CSV. Consulta completa contra
`INFORMATION_SCHEMA.COLUMNS` em 23/08/2026 revelou ~56 colunas ao todo.
Além das já documentadas (Campos-chave) e das três resolvidas acima, o
restante ainda não avança pra silver/gold:

- **Estabelecimento**: `co_cnes_estabelecimento`, `co_natureza_estabelecimento`/`ds_natureza_estabelecimento`,
  `co_tipo_estabelecimento`/`ds_tipo_estabelecimento`, `no_fantasia_estalecimento`,
  `no_razao_social_estabelecimento`, `no_municipio_estabelecimento`, `no_uf_estabelecimento`.
- **Lote/fabricante da vacina**: `co_lote_vacina`, `co_vacina_fabricante`/`ds_vacina_fabricante`,
  `sg_imunobiologico`, `co_vacina_grupo_atendimento`/`no_grupo_atendimento`.
- **Aplicação/categoria**: `co_local_aplicacao`/`ds_local_aplicacao`, `co_via_administracao`/`ds_via_administracao`,
  `co_categoria`/`ds_categoria`, `co_condicao_maternal`/`ds_condicao_maternal`.
- **Paciente (adicional)**: `co_paciente`, `co_etnia_indigena_paciente`/`no_etnia_indigena_paciente`,
  `no_pais_paciente`, `no_uf_paciente`, `nu_cep_paciente` (já marcado pra não ir pro BI),
  `ds_nacionalidade_paciente` (já marcado pra não ir pro BI).
- **Metadados de origem** (já confirmados sem valor analítico ou marcados
  pra não ir pro BI): `co_troca_documento`, `co_sistema_origem`/`ds_sistema_origem`,
  `co_origem_registro`/`ds_origem_registro`, `_PARTITIONTIME` (metadado do BigQuery, não da fonte).

Discussão em andamento sobre novas dimensões de estabelecimento e de
lote/fabricante (pedido 23/08/2026) — ver adendo correspondente no ADR
0008 quando a decisão de grão for fechada (risco de cardinalidade alta,
mesmo problema que levou ao grão mensal da fato).

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
- `co_municipio_paciente`/`co_municipio_estabelecimento` (e portanto
  `municipio_cobertura` na silver) usam o código **legado de 6 dígitos**
  do DATASUS/SUS, não o código de 7 dígitos do IBGE usado pela Base dos
  Dados — achado real, 23/08/2026, ao conectar o Power BI (o join de
  `dim_municipio` não batia com NENHUM município real até a correção). Ver
  2º refinamento do ADR 0009.
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
