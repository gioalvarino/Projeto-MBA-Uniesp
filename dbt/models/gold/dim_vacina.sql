-- Dimensão de vacina/dose (ADR 0008). De-para oficial de nomes do PNI
-- ainda pendente (ver "Códigos pendentes de de-para" em
-- docs/dicionario_dados.md) — por enquanto carrega só os códigos.

with silver as (

    select distinct
        co_vacina,
        co_dose_vacina
    from {{ ref('stg_pni__doses_aplicadas') }}

)

select
    concat(co_vacina, '-', co_dose_vacina) as chave_vacina,
    co_vacina,
    co_dose_vacina,
    cast(null as string) as nome_vacina,  -- pendente: de-para oficial do PNI
    cast(null as string) as nome_dose     -- pendente: de-para oficial do PNI
from silver
