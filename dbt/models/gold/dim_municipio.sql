-- Dimensão de município de cobertura (ADR 0007 + ADR 0008). Derivada das
-- combinações observadas em municipio_cobertura/uf_cobertura na silver.
--
-- chave_municipio: municipio_cobertura quando existe, senão uf_cobertura
-- ('ESTRANGEIRO'/'SEM INFORMACAO') — cobre os casos especiais como
-- membros próprios da dimensão, sem sentinela numérico arbitrário.
--
-- nome_municipio e populacao ficam nulos por design: dependem do
-- enriquecimento com Base dos Dados/IBGE (previsto na silver pelo ADR
-- 0004, ainda não implementado). O indicador de contagem de doses já
-- funciona sem eles; a taxa de cobertura (doses ÷ população) só fica
-- completa depois desse enriquecimento.

with silver as (

    select distinct
        municipio_cobertura,
        uf_cobertura
    from {{ ref('stg_pni__doses_aplicadas') }}

)

select
    coalesce(municipio_cobertura, uf_cobertura) as chave_municipio,
    municipio_cobertura                          as codigo_ibge,
    uf_cobertura                                  as uf,
    cast(null as string)                          as nome_municipio,
    cast(null as int64)                           as populacao,
    case
        when uf_cobertura = 'SEM INFORMACAO' then 'Sem informação'
        when uf_cobertura = 'ESTRANGEIRO' then 'Estrangeiro'
        else 'Município válido'
    end as tipo_registro
from silver
