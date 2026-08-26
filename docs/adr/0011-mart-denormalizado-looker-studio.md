# ADR 0011: Tabela larga (mart) denormalizada pro Looker Studio

- **Status:** aceita
- **Data:** 2026-08-26
- **Responsável:** Giovanna

## Contexto

O plano original era consumir o modelo estrela da gold (`fct_cobertura_vacinal`
+ 5 dimensões, ADR 0008) direto no Power BI. Mudança de plano: o Power BI
Desktop não roda no Linux (SO usado pela Ellen), e o trio precisa que todo
mundo consiga abrir/editar o painel. Avaliamos o Looker Studio (Google) como
alternativa — é 100% web, roda em qualquer sistema operacional.

Duas diferenças relevantes do Looker Studio em relação ao Power BI:

1. **Modelagem relacional.** O Power BI tem uma visão de modelo (Model view)
   onde se definem relações fato ↔ dimensão explicitamente, e o motor
   (VertiPaq) resolve os joins em memória depois de carregado. O Looker
   Studio não tem esse conceito — cada gráfico normalmente lê UMA fonte de
   dados; pra combinar mais de uma fonte existe o recurso "Blend Data", que
   tem limite de fontes por blend e reprocessa/reconsulta cada fonte
   envolvida.
2. **Custo de consulta.** Conectando o Looker Studio "ao vivo" no BigQuery
   (conector nativo do BigQuery, em modo tabela ou consulta customizada),
   a própria documentação do Google confirma que abrir, atualizar ou filtrar
   um relatório pode gerar consulta nova cobrada normalmente pelo BigQuery
   ("You might incur query processing or storage costs when you access
   BigQuery data through [...] reports" — [doc oficial do conector
   BigQuery no Looker
   Studio](https://docs.cloud.google.com/data-studio/connect-to-google-bigquery)).
   Há relatos reais de times que viram a conta subir só de uso cotidiano do
   painel (filtro, navegação), sem rodar nenhuma consulta manual — ver
   ["Cute Dashboards, Big Bills: Exploring Looker Studio Costs with BigQuery
   Data
   Sources"](https://medium.com/@aliiz/cute-dashboards-big-bills-exploring-looker-studio-costs-with-bigquery-data-sources-7e5b9e3b0086),
   que documenta um caso assim. Isso contraria diretamente a regra combinada
   do projeto de reduzir ao máximo consultas que possam gerar cobrança.

## Opções consideradas

1. **Conectar o Looker Studio ao vivo em cada uma das 6 tabelas da gold**
   (fato + 5 dimensões), usando "Blend Data" pra juntar tudo dentro do
   relatório. Reproduz o modelo estrela do Power BI, mas cada blend soma
   consulta contra o BigQuery, e cada visualização/filtro pode gerar
   consulta nova — justamente o padrão de custo que o achado acima
   descreve. Rejeitada.
2. **Conectar ao vivo numa única consulta customizada** (SQL com os joins
   escrito na hora, dentro do próprio conector do Looker Studio). Resolve a
   parte da modelagem, mas continua "ao vivo": mesmo problema de custo
   recorrente do item 1, e a consulta fica escrita dentro da configuração do
   relatório, fora do controle de versão do projeto. Rejeitada.
3. **Gerar uma tabela larga (mart) já denormalizada no dbt** (fato + nomes
   de todas as dimensões numa linha só) e extrair essa tabela ÚNICA pro
   Looker Studio com o conector nativo "Extract Data" (roda a consulta uma
   vez, guarda uma cópia dentro do próprio Looker Studio; abrir/filtrar o
   relatório depois disso não toca mais o BigQuery). Escolhida.

## Decisão

Criar `dbt/models/gold/mart_cobertura_vacinal.sql`: junta
`fct_cobertura_vacinal` com as 5 dimensões (`dim_municipio`, `dim_vacina`,
`dim_tempo`, `faixa_etaria`, `dim_perfil_paciente`, `dim_estrategia_vacinacao`)
via `left join`, mantendo o mesmo grão da fato (uma linha por combinação de
chaves — só adiciona colunas de nome/contexto, não duplica linha nem agrega
de novo). `meta_vacinal` fica de fora, pelo mesmo motivo do ADR 0010 (sem
de-para real com `dim_vacina`).

No Looker Studio, essa tabela é conectada usando o conector **"Extract
Data"** (não o conector "BigQuery" direto) — ver guia de migração
(`docs/guia_looker_studio.md`) para o passo a passo.

## Consequências

- **Não gera custo de consulta recorrente**: só a extração inicial (e uma
  reextração manual, se os dados mudarem — o que não é esperado depois da
  apresentação de 29/08, ver decisão de escopo já registrada sobre não
  atualizar os dados depois disso).
- O modelo estrela original (`fct_cobertura_vacinal` + dimensões) continua
  existindo e válido — o `mart_cobertura_vacinal` é um model adicional,
  read-only, que não substitui nem duplica a responsabilidade dos outros;
  ele só resolve a falta de modelagem relacional do Looker Studio.
- Como consequência de ser uma tabela larga, os nomes de dimensão (ex.
  `nome_municipio`) se repetem em cada linha da fato, em vez de ficar numa
  tabela separada — deixa o dado replicado, mas nesse volume (~16,2M linhas
  no grão mensal, poucas dezenas de colunas de texto curto) o ganho de
  simplicidade compensa o espaço extra; é a mesma troca que qualquer
  ferramenta de BI sem suporte a modelo relacional exige.
- Se o trio decidir voltar pro Power BI no futuro, esse model pode ser
  ignorado sem custo nenhum — ele não interfere no modelo estrela existente.
- Sem custo de BigQuery adicional pra criar o model em si: é só mais uma
  consulta de transformação dentro da cota diária já usada pelo `dbt build`.
