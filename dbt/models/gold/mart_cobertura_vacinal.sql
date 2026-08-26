-- Tabela larga (mart) só de leitura, criada especificamente pro Looker
-- Studio (ADR 0011, 26/08/2026): a fato + as 5 dimensões já formam um
-- modelo estrela correto e leve pro Power BI, mas o Looker Studio não
-- tem uma visão de modelo relacional equivalente (não dá pra definir
-- relações fato ↔ dimensão como no Power BI). A alternativa nativa dele
-- ("Blend Data") é limitada e cada blend soma consultas de novo contra o
-- BigQuery. Em vez de lidar com essa limitação, geramos aqui UMA tabela
-- já com tudo junto (fato + nomes das dimensões), pronta pra ser
-- extraída de uma vez só com o conector "Extract Data" do Looker Studio
-- — 1 consulta, sem custo recorrente depois (ver docs/adr/0011).
--
-- Mesmo grão da fct_cobertura_vacinal — uma linha por combinação de
-- mes_vacina + chave_municipio + chave_vacina + chave_faixa_etaria +
-- chave_perfil + chave_estrategia. Só adiciona colunas de contexto
-- (nomes), não muda a granularidade nem duplica linha.
--
-- Left join em tudo de propósito: os testes de relationships em
-- fct_cobertura_vacinal (_gold__models.yml) já garantem que toda chave
-- bate em alguma dimensão, então na prática não deveria sobrar NULL de
-- join quebrado — mas left join evita que um problema futuro de dado
-- descarte uma linha inteira da fato silenciosamente.
--
-- meta_vacinal não entra aqui: sem de-para com dim_vacina (decisão de
-- escopo, ver ADR 0010) — não existe chave real pra juntar.

with fato as (

    select * from {{ ref('fct_cobertura_vacinal') }}

),

municipio as (

    select * from {{ ref('dim_municipio') }}

),

vacina as (

    select * from {{ ref('dim_vacina') }}

),

tempo as (

    select * from {{ ref('dim_tempo') }}

),

faixa as (

    select * from {{ ref('faixa_etaria') }}

),

perfil as (

    select * from {{ ref('dim_perfil_paciente') }}

),

estrategia as (

    select * from {{ ref('dim_estrategia_vacinacao') }}

)

select
    fato.mes_vacina,
    tempo.ano,
    tempo.mes_numero,
    tempo.nome_mes,
    tempo.trimestre,

    fato.chave_municipio,
    municipio.codigo_ibge,
    municipio.uf,
    municipio.nome_municipio,
    municipio.nome_regiao,
    municipio.populacao,
    municipio.ano_populacao,
    municipio.tipo_registro,

    fato.chave_vacina,
    vacina.nome_vacina,
    vacina.nome_dose,

    fato.chave_faixa_etaria,
    faixa.nome_faixa_etaria,
    faixa.idade_min,
    faixa.idade_max,

    fato.chave_perfil,
    perfil.codigo_raca_cor,
    perfil.nome_raca_cor,
    perfil.sexo,
    perfil.nome_sexo,

    fato.chave_estrategia,
    estrategia.nome_estrategia,

    fato.qtd_doses

from fato
left join municipio  on fato.chave_municipio   = municipio.chave_municipio
left join vacina     on fato.chave_vacina       = vacina.chave_vacina
left join tempo      on fato.mes_vacina         = tempo.mes
left join faixa      on fato.chave_faixa_etaria = faixa.ordem
left join perfil     on fato.chave_perfil       = perfil.chave_perfil
left join estrategia on fato.chave_estrategia   = estrategia.chave_estrategia
