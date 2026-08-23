-- Dimensão de calendário (ADR 0008 + adendo 23/08/2026 — mudança de grão
-- diário pra mensal). Não vem da fonte — é gerada, cobrindo 2026 inteiro (o
-- ano de referência dos dados do projeto, ver ADR 0001).
--
-- Grão mensal: a fato (fct_cobertura_vacinal) mudou de grão diário pra
-- mensal em 23/08/2026 (ver "Adendo: grão mensal" no ADR 0008) — cobertura
-- vacinal é analisada/reportada quase sempre por mês/ano, nunca por dia; o
-- grão diário só inflava o tamanho da fato (chegou a 49M linhas) sem uso
-- real. `mes` é sempre o primeiro dia do mês (ex. 2026-04-01), e é a chave
-- que casa com `mes_vacina` na fato.
--
-- Nomes de mês em português, montados na mão porque FORMAT_DATE usa o
-- locale padrão (inglês) do BigQuery.

with meses as (

    select data as mes
    from unnest(generate_date_array('2026-01-01', '2026-12-01', interval 1 month)) as data

)

select
    mes,
    extract(year from mes)   as ano,
    extract(month from mes)  as mes_numero,
    case extract(month from mes)
        when 1 then 'Janeiro' when 2 then 'Fevereiro' when 3 then 'Março'
        when 4 then 'Abril' when 5 then 'Maio' when 6 then 'Junho'
        when 7 then 'Julho' when 8 then 'Agosto' when 9 then 'Setembro'
        when 10 then 'Outubro' when 11 then 'Novembro' when 12 then 'Dezembro'
    end                        as nome_mes,
    extract(quarter from mes) as trimestre
from meses
