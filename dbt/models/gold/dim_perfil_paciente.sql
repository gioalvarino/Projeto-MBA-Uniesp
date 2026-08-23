-- Dimensão de perfil demográfico do paciente (raça/cor + sexo) — adendo ao
-- ADR 0008 (23/08/2026), pra permitir analisar cobertura vacinal por
-- característica de quem foi vacinado (indicador comum de equidade em
-- vigilância em saúde pública).
--
-- Grão pequeno por natureza: no máximo 6 códigos de raça/cor x 3 categorias
-- de sexo padronizadas (F/M/SEM INFORMACAO) = até 18 combinações.
--
-- chave_perfil segue o mesmo padrão de dim_vacina (concat de dois códigos),
-- e nome_raca_cor/sexo já vêm prontos/padronizados da silver — sem de-para
-- externo pendente, diferente de dim_vacina.

with silver as (

    select distinct
        raca_cor_cobertura,
        nome_raca_cor_cobertura,
        sexo_cobertura
    from {{ ref('stg_pni__doses_aplicadas') }}

)

select
    concat(raca_cor_cobertura, '-', sexo_cobertura) as chave_perfil,
    raca_cor_cobertura                                as codigo_raca_cor,
    nome_raca_cor_cobertura                           as nome_raca_cor,
    sexo_cobertura                                     as sexo,
    case sexo_cobertura
        when 'F' then 'Feminino'
        when 'M' then 'Masculino'
        else 'Sem informação'
    end as nome_sexo
from silver
