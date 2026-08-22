-- Staging: primeira parada da bronze na silver. Só tipagem básica e as
-- regras de qualidade já conhecidas (docs/dicionario_dados.md) — nenhuma
-- agregação, nenhum enriquecimento (isso fica pros próximos models da
-- silver/gold, ex.: join por código IBGE com a Base dos Dados).
--
-- Nomes de coluna confirmados contra o CSV real em 22/08/2026 (ver
-- _silver__sources.yml) — o CSV usa prefixos abreviados (co_/no_/dt_/st_),
-- diferente do dicionário da API do PNI.
--
-- municipio_cobertura / uf_cobertura: geografia resolvida pro cálculo de
-- cobertura vacinal (ADR 0007) — residência como principal, com fallback
-- pra aplicação quando a residência não vem preenchida, categorias
-- explícitas pra estrangeiro/sem informação, e derivação da UF a partir do
-- código do município (seed uf_ibge) quando a sigla vem vazia na fonte
-- mesmo com o município preenchido (achado real, 22/08/2026: 1.162 de
-- 8,9M linhas).

with bronze as (

    select *
    from {{ source('bronze', 'doses_aplicadas_pni') }}

),

uf_ibge as (

    select *
    from {{ ref('uf_ibge') }}

),

tipado as (

    select
        co_documento                as codigo_documento,
        safe_cast(dt_vacina as date)           as data_vacina,
        safe_cast(dt_entrada_rnds as timestamp) as data_entrada_rnds,
        dt_deletado_rnds            as data_deletado_rnds,
        co_municipio_estabelecimento,
        co_municipio_paciente,
        co_pais_paciente,
        co_vacina,
        co_dose_vacina,
        co_estrategia_vacinacao,
        st_documento                as status_documento,
        sg_uf_paciente,
        sg_uf_estabelecimento,
        -- "0" é bebê com menos de 1 ano, não idade faltante — ver dicionário.
        safe_cast(nu_idade_paciente as int64)   as idade_paciente,
        co_raca_cor_paciente,

        -- Município de cobertura (ADR 0007): residência como principal,
        -- fallback pra aplicação quando a residência não vem preenchida. A
        -- ordem dos CASE importa: país vazio é checado antes de município
        -- vazio, porque no dado real todo país vazio já vem com município
        -- vazio também — sem essa ordem os dois casos se confundiriam.
        case
            when co_pais_paciente is null or co_pais_paciente = '' then null
            when co_pais_paciente != '10' then null
            when co_municipio_paciente is null or co_municipio_paciente = '' then co_municipio_estabelecimento
            else co_municipio_paciente
        end as municipio_cobertura,

        -- UF "direta": a sigla que já vem pronta no CSV pro município
        -- escolhido acima (antes de qualquer derivação).
        case
            when co_pais_paciente is null or co_pais_paciente = '' then null
            when co_pais_paciente != '10' then null
            when co_municipio_paciente is null or co_municipio_paciente = '' then sg_uf_estabelecimento
            else sg_uf_paciente
        end as uf_direta

    from bronze

),

com_uf_derivada as (

    select
        t.*,
        u.sg_uf as uf_derivada_do_municipio

    from tipado t
    left join uf_ibge u
        on substr(t.municipio_cobertura, 1, 2) = cast(u.co_uf as string)

),

com_cobertura as (

    select
        * except (uf_direta, uf_derivada_do_municipio),

        case
            when co_pais_paciente is null or co_pais_paciente = '' then 'SEM INFORMACAO'
            when co_pais_paciente != '10' then 'ESTRANGEIRO'
            -- Achado real (22/08/2026): a sigla às vezes vem vazia mesmo com
            -- o município preenchido — nesse caso, deriva da própria
            -- prefixo do código IBGE em vez de descartar a informação.
            else coalesce(uf_direta, uf_derivada_do_municipio, 'SEM INFORMACAO')
        end as uf_cobertura

    from com_uf_derivada

),

deduplicado as (

    select *
    from com_cobertura
    -- Exclusão lógica na origem não avança para a silver.
    where data_deletado_rnds is null
    -- codigo_documento é a chave de deduplicação (docs/dicionario_dados.md);
    -- em empate, fica a entrada mais recente no RNDS.
    qualify row_number() over (
        partition by codigo_documento
        order by data_entrada_rnds desc
    ) = 1

)

select * from deduplicado
