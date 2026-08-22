-- Staging: primeira parada da bronze na silver. Só tipagem básica e as
-- regras de qualidade já conhecidas (docs/dicionario_dados.md) — nenhuma
-- agregação, nenhum enriquecimento (isso fica pros próximos models da
-- silver/gold, ex.: join por código IBGE com a Base dos Dados).
--
-- Nomes de coluna vêm de _silver__sources.yml — ainda não confirmados
-- contra o CSV real (pendência aberta, ver comentário lá).

with bronze as (

    select *
    from {{ source('bronze', 'doses_aplicadas_pni') }}

),

tipado as (

    select
        codigo_documento,
        safe_cast(data_vacina as date)             as data_vacina,
        safe_cast(data_entrada_rnds as timestamp)   as data_entrada_rnds,
        data_deletado_rnds,
        codigo_municipio_estabelecimento,
        codigo_municipio_paciente,
        codigo_vacina,
        codigo_dose_vacina,
        status_documento,
        -- "0" é bebê com menos de 1 ano, não idade faltante — ver dicionário.
        safe_cast(numero_idade_paciente as int64)   as idade_paciente,
        codigo_raca_cor_paciente

    from bronze

),

deduplicado as (

    select *
    from tipado
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
