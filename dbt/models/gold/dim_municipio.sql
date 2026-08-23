-- Dimensão de município de cobertura (ADR 0007 + ADR 0008). Derivada das
-- combinações observadas em municipio_cobertura/uf_cobertura na silver,
-- enriquecida com nome e população reais via Base dos Dados/IBGE
-- (stg_ibge__municipios — ADR 0004 + ADR 0009, implementado em 23/08/2026).
--
-- chave_municipio: municipio_cobertura quando existe, senão uf_cobertura
-- ('ESTRANGEIRO'/'SEM INFORMACAO') — cobre os casos especiais como
-- membros próprios da dimensão, sem sentinela numérico arbitrário.
--
-- nome_municipio e populacao ficam nulos só pros membros especiais
-- ('ESTRANGEIRO'/'SEM INFORMACAO' não têm código IBGE de verdade pra
-- casar com a Base dos Dados) — pra município real, agora vêm
-- preenchidos. Se algum município real não casar (código descontinuado,
-- por exemplo), também fica nulo — checar após o build.
--
-- ano_populacao: qual ano a estimativa de populacao realmente veio (nem
-- sempre 2025 — stg_ibge__municipios usa o ano mais recente disponível
-- por município, achado real 23/08/2026). Transparência pra apresentação:
-- deixa claro que a população é estimativa, não censo do mesmo ano do
-- dado de vacinação.

with silver as (

    select distinct
        municipio_cobertura,
        uf_cobertura
    from {{ ref('stg_pni__doses_aplicadas') }}

),

ibge as (

    select * from {{ ref('stg_ibge__municipios') }}

)

select
    coalesce(s.municipio_cobertura, s.uf_cobertura) as chave_municipio,
    s.municipio_cobertura                            as codigo_ibge,
    s.uf_cobertura                                    as uf,
    i.nome_municipio,
    i.populacao,
    i.ano_populacao,
    case
        when s.uf_cobertura = 'SEM INFORMACAO' then 'Sem informação'
        when s.uf_cobertura = 'ESTRANGEIRO' then 'Estrangeiro'
        else 'Município válido'
    end as tipo_registro

from silver s
left join ibge i
    on s.municipio_cobertura = i.id_municipio
