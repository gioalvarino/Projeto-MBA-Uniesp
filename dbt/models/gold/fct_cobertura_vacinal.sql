-- Fato de cobertura vacinal (ADR 0008). Grão agregado — uma linha por
-- combinação de (data_vacina, chave_municipio, chave_vacina,
-- chave_faixa_etaria, chave_perfil), com qtd_doses como métrica. Não é uma
-- linha por dose: essa decisão mantém a gold pequena/rápida no Power BI e
-- reforça o ADR 0005 (nenhum dado pessoal identificável avança pra gold).
--
-- As chaves aqui têm que bater exatamente com a lógica de chave usada em
-- dim_municipio.sql, dim_vacina.sql e dim_perfil_paciente.sql — ver
-- _gold__models.yml pros testes de relationships que garantem isso.
--
-- chave_perfil (raça/cor + sexo) foi adicionada em 23/08/2026, adendo ao
-- ADR 0008 — ver docs/adr/0008-modelo-estrela-gold.md.

with silver as (

    select * from {{ ref('stg_pni__doses_aplicadas') }}

),

faixa_etaria as (

    select * from {{ ref('faixa_etaria') }}

),

com_chaves as (

    select
        s.data_vacina,
        coalesce(s.municipio_cobertura, s.uf_cobertura) as chave_municipio,
        concat(s.co_vacina, '-', s.co_dose_vacina)        as chave_vacina,
        -- idade_paciente nulo não bate em nenhuma faixa (BETWEEN com NULL
        -- é NULL) — cai no coalesce pra faixa "sem informação" (ordem 0).
        coalesce(f.ordem, 0)                               as chave_faixa_etaria,
        concat(s.raca_cor_cobertura, '-', s.sexo_cobertura) as chave_perfil

    from silver s
    left join faixa_etaria f
        on s.idade_paciente between f.idade_min and f.idade_max

)

select
    data_vacina,
    chave_municipio,
    chave_vacina,
    chave_faixa_etaria,
    chave_perfil,
    count(*) as qtd_doses

from com_chaves
group by data_vacina, chave_municipio, chave_vacina, chave_faixa_etaria, chave_perfil
