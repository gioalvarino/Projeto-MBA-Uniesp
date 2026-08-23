-- Dimensão de estratégia de vacinação (rotina, campanha, bloqueio etc.) —
-- adendo ao ADR 0008 (23/08/2026). Segue o mesmo padrão de dim_vacina:
-- sobe só o código por enquanto, nome oficial ainda pendente do de-para do
-- PNI (docs/dicionario_dados.md).
--
-- chave_estrategia já vem pronta da silver (estrategia_cobertura), com
-- nulo padronizado pra 'SEM INFORMACAO' (~0,6% dos registros reais).

with silver as (

    select distinct
        estrategia_cobertura
    from {{ ref('stg_pni__doses_aplicadas') }}

)

select
    estrategia_cobertura as chave_estrategia,
    cast(null as string)  as nome_estrategia  -- pendente: de-para oficial do PNI
from silver
