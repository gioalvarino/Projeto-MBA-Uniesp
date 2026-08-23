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
-- id_municipio (Base dos Dados) é o mesmo código IBGE de 7 dígitos usado em
-- municipio_cobertura na silver — join direto, sem de-para.

with diretorio as (

    select
        id_municipio,
        nome     as nome_municipio,
        sigla_uf
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
    d.nome_municipio,
    d.sigla_uf,
    p.populacao,
    p.ano as ano_populacao

from diretorio d
left join populacao_mais_recente p
    using (id_municipio)
