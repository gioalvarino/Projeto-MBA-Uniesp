-- Dimensão de estratégia de vacinação (rotina, campanha, bloqueio etc.) —
-- adendo ao ADR 0008 (23/08/2026). nome_estrategia resolvido direto da
-- fonte (no_estrategia) no mesmo dia — mesmo achado real de dim_vacina,
-- elimina a pendência de de-para externo pra estratégia também.
--
-- chave_estrategia já vem pronta da silver (estrategia_cobertura), com
-- nulo padronizado pra 'SEM INFORMACAO' (~0,6% dos registros reais). O
-- código '0' também não tem nome na fonte (mesmo padrão de nulo) — cai em
-- 'SEM INFORMACAO' junto, sem conflito de chave.

with silver as (

    select distinct
        estrategia_cobertura,
        nome_estrategia_cobertura
    from {{ ref('stg_pni__doses_aplicadas') }}

)

select
    estrategia_cobertura      as chave_estrategia,
    nome_estrategia_cobertura as nome_estrategia
from silver
