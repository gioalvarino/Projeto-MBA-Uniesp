-- Versão resumida da mart_cobertura_vacinal, criada pra caber no limite
-- de volume do conector "Extract Data" do Looker Studio (ADR 0011,
-- adendo 26/08/2026): a mart_cobertura_vacinal original (mesmo grão da
-- fct_cobertura_vacinal, incluindo raça/sexo/estratégia linha a linha)
-- tem 16.150.756 linhas e 4,08 GB — 2 tentativas de extração falharam
-- por volume (erros genéricos 99090e12 e e5fd980d).
--
-- Esta tabela agrega o mesmo dado a um grão mais alto: uma linha por
-- combinação de mes_vacina + chave_municipio + chave_vacina +
-- chave_faixa_etaria, somando qtd_doses através de raça/sexo/perfil e
-- estratégia de vacinação (o painel principal de cobertura não precisa
-- detalhar essas duas dimensões linha a linha). Reduz drasticamente o
-- número de linhas mantendo o suficiente pro painel.
--
-- Não substitui a mart_cobertura_vacinal original (mantida como está,
-- pode servir de referência ou uso futuro no Power BI) nem os models
-- star-schema (fct_cobertura_vacinal/dim_*) — arquivo novo, adicional.

with fato as (

    select
        mes_vacina,
        chave_municipio,
        chave_vacina,
        chave_faixa_etaria,
        sum(qtd_doses) as qtd_doses

    from {{ ref('fct_cobertura_vacinal') }}
    group by mes_vacina, chave_municipio, chave_vacina, chave_faixa_etaria

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

    fato.qtd_doses

from fato
left join municipio  on fato.chave_municipio   = municipio.chave_municipio
left join vacina     on fato.chave_vacina       = vacina.chave_vacina
left join tempo      on fato.mes_vacina         = tempo.mes
left join faixa      on fato.chave_faixa_etaria = faixa.ordem
