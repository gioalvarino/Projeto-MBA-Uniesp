-- Enriquecimento com Base dos Dados/IBGE (ADR 0004, implementado em
-- 23/08/2026 — ver ADR 0009): nome e população de município, pra completar
-- a taxa de cobertura vacinal (doses ÷ população) que a gold ainda não
-- conseguia calcular sem isso.
--
-- População: usa a estimativa mais recente disponível até 2025 (que é o
-- ano mais recente com cobertura quase completa, 5.569 de 5.570
-- municípios) em vez de exigir exatamente 2025 — achado real (23/08/2026):
-- Boa Esperança do Norte/MT (5101837), município antigo e já estabelecido,
-- não tinha estimativa publicada especificamente pra 2025. Usar o ano mais
-- recente disponível por município evita perder população por causa de uma
-- lacuna pontual como essa, sem descartar a informação.
--
-- id_municipio_6d (achado real, 23/08/2026 — ver adendo ADR 0009):
-- municipio_cobertura NÃO é o código de 7 dígitos do IBGE — é o código
-- legado de 6 dígitos que o DATASUS/SUS usa historicamente (o código de 7
-- dígitos = código de 6 dígitos + 1 dígito verificador calculado). O join
-- direto por id_municipio (7 dígitos) contra municipio_cobertura (6
-- dígitos) não batia NUNCA: 100% dos municípios reais ficavam sem
-- nome/população no Power BI, não só o 1 caso de população nula encontrado
-- antes (esse era um problema diferente, isolado, da Base dos Dados em si
-- — ver comentário abaixo). id_municipio_6d trunca o 7º dígito
-- (verificador) da Base dos Dados pra casar com o formato do PNI.
--
-- nome_regiao (adendo ADR 0009, 24/08/2026, CORRIGIDO em 24/08/2026): a
-- própria Base dos Dados já traz a macro-região (Norte/Nordeste/Centro-
-- Oeste/Sudeste/Sul) na tabela de diretório de município — não precisou de
-- seed novo. Achado real: o nome da coluna na fonte já É `nome_regiao`
-- (confirmado via INFORMATION_SCHEMA.COLUMNS, 24/08/2026) — a hipótese
-- inicial (baseada num tutorial externo da Base dos Dados) era de que a
-- coluna se chamava `regiao`, o que causou um erro real de "Unrecognized
-- name: regiao" no primeiro dbt build após essa mudança. Lição: confirmar
-- schema real via INFORMATION_SCHEMA antes de confiar em documentação/
-- tutorial de terceiros, mesmo que pareça autoritativo.

with diretorio as (

    select
        id_municipio,
        substr(id_municipio, 1, 6) as id_municipio_6d,
        nome     as nome_municipio,
        sigla_uf,
        nome_regiao
    from {{ source('bd_diretorios_brasil', 'municipio') }}

),

populacao_mais_recente as (

    select
        id_municipio,
        populacao,
        ano
    from {{ source('bd_ibge_populacao', 'municipio') }}
    -- populacao is not null aqui é o que importa: Boa Esperança do
    -- Norte/MT tem uma linha pra ano=2025, mas com populacao nula (a
    -- COUNT(DISTINCT id_municipio) por ano conta a linha, não o valor) —
    -- sem esse filtro, o qualify abaixo escolheria essa mesma linha nula
    -- por ela ser "a mais recente", e o problema continuaria.
    where ano <= 2025 and populacao is not null
    qualify row_number() over (partition by id_municipio order by ano desc) = 1

)

select
    d.id_municipio,
    d.id_municipio_6d,
    d.nome_municipio,
    d.sigla_uf,
    d.nome_regiao,
    p.populacao,
    p.ano as ano_populacao

from diretorio d
left join populacao_mais_recente p
    using (id_municipio)
