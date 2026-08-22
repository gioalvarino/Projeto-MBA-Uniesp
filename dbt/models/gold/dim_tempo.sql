-- Dimensão de calendário (ADR 0008). Não vem da fonte — é gerada,
-- cobrindo 2026 inteiro (o ano de referência dos dados do projeto, ver
-- ADR 0001). Grão diário. Nomes de mês/dia em português, montados na mão
-- porque FORMAT_DATE usa o locale padrão (inglês) do BigQuery.

with datas as (

    select data
    from unnest(generate_date_array('2026-01-01', '2026-12-31')) as data

)

select
    data,
    extract(year from data)    as ano,
    extract(month from data)   as mes,
    case extract(month from data)
        when 1 then 'Janeiro' when 2 then 'Fevereiro' when 3 then 'Março'
        when 4 then 'Abril' when 5 then 'Maio' when 6 then 'Junho'
        when 7 then 'Julho' when 8 then 'Agosto' when 9 then 'Setembro'
        when 10 then 'Outubro' when 11 then 'Novembro' when 12 then 'Dezembro'
    end                         as nome_mes,
    extract(quarter from data) as trimestre,
    -- BigQuery: 1 = domingo ... 7 = sábado
    extract(dayofweek from data) as dia_da_semana,
    case extract(dayofweek from data)
        when 1 then 'Domingo' when 2 then 'Segunda-feira' when 3 then 'Terça-feira'
        when 4 then 'Quarta-feira' when 5 then 'Quinta-feira' when 6 then 'Sexta-feira'
        when 7 then 'Sábado'
    end                          as nome_dia_semana
from datas
