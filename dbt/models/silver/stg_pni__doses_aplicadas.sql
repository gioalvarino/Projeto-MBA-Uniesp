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
--
-- raca_cor_cobertura / nome_raca_cor_cobertura / sexo_cobertura: perfil
-- demográfico padronizado — adendo ao ADR 0008 (23/08/2026), pra permitir
-- cobertura vacinal por característica do vacinado. Validado contra os 7
-- meses reais: sexo vem só como F/M/I/N (I="Ignorado", N=2 casos — erro de
-- digitação da fonte), sem nulo de verdade; raça/cor vem quase sempre
-- preenchida (só 4 linhas nulas em ~115M) e o nome já vem pronto da fonte
-- (no_raca_cor_paciente), sem precisar de de-para externo como vacina/dose.

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
        sg_uf_paciente,
        sg_uf_estabelecimento,
        -- "0" é bebê com menos de 1 ano, não idade faltante — ver dicionário.
        safe_cast(nu_idade_paciente as int64)   as idade_paciente,
        co_raca_cor_paciente,
        no_raca_cor_paciente,
        tp_sexo_paciente,

        -- Município de cobertura (ADR 0007): residência como principal,
        -- fallback pra aplicação quando a residência não vem preenchida. A
        -- ordem dos CASE importa: país vazio é checado antes de município
        -- vazio, porque no dado real todo país vazio já vem com município
        -- vazio também — sem essa ordem os dois casos se confundiriam.
        --
        -- '999999' (achado real, 23/08/2026, teste unique de dim_municipio
        -- falhou nos 7 meses completos): sentinela de "município ignorado"
        -- usado pela fonte, não um código IBGE de verdade (código real tem
        -- 7 dígitos com prefixo de UF 11-53; '999999' tem prefixo '99', que
        -- não existe). Tratado como vazio (nullif), senão vira um
        -- "município" falso na dimensão, e o mesmo código real podia
        -- aparecer com UF divergente entre registros e quebrar a chave
        -- única.
        case
            when co_pais_paciente is null or co_pais_paciente = '' then null
            when co_pais_paciente != '10' then null
            when nullif(co_municipio_paciente, '999999') is null or nullif(co_municipio_paciente, '999999') = ''
                then nullif(co_municipio_estabelecimento, '999999')
            else nullif(co_municipio_paciente, '999999')
        end as municipio_cobertura,

        -- UF "direta": a sigla que já vem pronta no CSV pro município
        -- escolhido acima (antes de qualquer derivação). 'XX' (mesmo
        -- achado, 23/08/2026): sentinela de "UF ignorada" — não é sigla de
        -- UF brasileira de verdade — tratado como vazio pelo mesmo motivo.
        case
            when co_pais_paciente is null or co_pais_paciente = '' then null
            when co_pais_paciente != '10' then null
            when nullif(co_municipio_paciente, '999999') is null or nullif(co_municipio_paciente, '999999') = ''
                then nullif(sg_uf_estabelecimento, 'XX')
            else nullif(sg_uf_paciente, 'XX')
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

com_perfil as (

    select
        *,

        -- Nulo é raríssimo (4 de ~115M linhas nos 7 meses reais) mas
        -- acontece — cai no mesmo '99'/'SEM INFORMACAO' que a fonte já usa
        -- pra "sem informação" explícito, em vez de sentinela novo.
        coalesce(co_raca_cor_paciente, '99')          as raca_cor_cobertura,
        coalesce(no_raca_cor_paciente, 'SEM INFORMACAO') as nome_raca_cor_cobertura,

        -- F/M direto da fonte; 'I' (Ignorado) e 'N' (2 casos, provável erro
        -- de digitação — volume irrisório) caem em 'SEM INFORMACAO'.
        case
            when tp_sexo_paciente in ('F', 'M') then tp_sexo_paciente
            else 'SEM INFORMACAO'
        end as sexo_cobertura

    from com_cobertura

),

deduplicado as (

    select *
    from com_perfil
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
