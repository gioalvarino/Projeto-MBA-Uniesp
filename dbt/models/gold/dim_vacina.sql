-- Dimensão de vacina/dose (ADR 0008). nome_vacina/nome_dose resolvidos
-- direto da fonte em 23/08/2026 (achado real, ao conectar o Power BI): a
-- bronze já tinha ds_nome/ds_tipo_dose com o nome pronto por linha — mesmo
-- padrão de no_raca_cor_paciente, só que a coluna tinha passado batido na
-- confirmação de cabeçalho original. Validado 1-pra-1 contra os 7 meses
-- reais antes de aplicar (nenhum código com nome divergente) — ver adendo
-- do ADR 0008. Elimina a pendência de de-para externo pra vacina/dose.

with silver as (

    select distinct
        co_vacina,
        co_dose_vacina,
        nome_vacina_cobertura,
        nome_dose_cobertura
    from {{ ref('stg_pni__doses_aplicadas') }}

)

select
    concat(co_vacina, '-', co_dose_vacina) as chave_vacina,
    co_vacina,
    co_dose_vacina,
    nome_vacina_cobertura as nome_vacina,
    nome_dose_cobertura   as nome_dose
from silver
