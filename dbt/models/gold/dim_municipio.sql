-- Dimensão de município de cobertura (ADR 0007 + ADR 0008). Derivada das
-- combinações observadas em municipio_cobertura/uf_cobertura na silver,
-- enriquecida com nome e população reais via Base dos Dados/IBGE
-- (stg_ibge__municipios — ADR 0004 + ADR 0009, implementado em 23/08/2026).
--
-- chave_municipio: municipio_cobertura quando existe, senão uf_cobertura
-- ('ESTRANGEIRO'/'SEM INFORMACAO') — cobre os casos especiais como
-- membros próprios da dimensão, sem sentinela numérico arbitrário.
--
-- Join por id_municipio_6d, NÃO id_municipio (achado real, 23/08/2026 —
-- ver 2º refinamento do ADR 0009): municipio_cobertura é o código legado
-- de 6 dígitos do DATASUS/SUS, não o código de 7 dígitos do IBGE — o join
-- direto por id_municipio não batia com NENHUM município real (100% da
-- dimensão ficava sem nome/população, achado ao conectar o Power BI).
--
-- nome_regiao: macro-região do Brasil (Norte/Nordeste/Centro-Oeste/
-- Sudeste/Sul) — já vem pronta da Base dos Dados, sem seed novo (adendo
-- ADR 0009, 24/08/2026).
--
-- nome_municipio e populacao ficam nulos pros membros especiais
-- ('ESTRANGEIRO'/'SEM INFORMACAO' não têm código IBGE de verdade pra
-- casar com a Base dos Dados) — pra município real, agora vêm
-- preenchidos. Se algum município real não casar (código descontinuado,
-- por exemplo), também fica nulo — checar após o build.
--
-- nome_regiao NÃO fica nulo pros membros especiais (achado real,
-- pedido da Giovanna — 6º refinamento ADR 0009): 'ESTRANGEIRO' e 'SEM
-- INFORMACAO' não têm região de verdade pra preencher, mas deixar nulo
-- lia como join quebrado no Power BI. Repetimos o próprio valor de uf
-- (que já é 'ESTRANGEIRO'/'SEM INFORMACAO' nesses casos) em nome_regiao,
-- deixando explícito que a região é a mesma categoria especial, não uma
-- macro-região real do Brasil.
--
-- ano_populacao: qual ano a estimativa de populacao realmente veio (nem
-- sempre 2025 — stg_ibge__municipios usa o ano mais recente disponível
-- por município, achado real 23/08/2026). Transparência pra apresentação:
-- deixa claro que a população é estimativa, não censo do mesmo ano do
-- dado de vacinação.
--
-- 5º refinamento (achado real, 24/08/2026 — 1º build contra os 7 meses
-- completos): 45 códigos "Município válido" ficaram sem nome/região.
-- Dois padrões claros, tratados abaixo (ver ADR 0009):
--   1. 31 códigos são Regiões Administrativas do Distrito Federal (DATASUS
--      tem código próprio pra cada uma — Taguatinga, Ceilândia etc.), mas
--      pro IBGE o DF é 1 único município (Brasília, 5300108). Aproximamos
--      nome/região/população pela de Brasília — não distingue as RAs entre
--      si, mas evita perder as doses aplicadas nelas.
--   2. 9 códigos terminam em '0000' (ex. 210000 = Maranhão): sentinela do
--      DATASUS pra "UF conhecida, município não informado". Não existe
--      município real pra dar nome, mas dá pra preencher nome_regiao só
--      pela UF (a região não depende do município específico).
-- Os 5 códigos restantes (430145/RS, 520100+520210+520900+520950/GO) não
-- batem em nenhum padrão identificado — ficam como limitação aceita
-- (mesmo tratamento do caso isolado de Boa Esperança do Norte/MT),
-- teste de not_null rebaixado pra warn.

with silver as (

    select distinct
        municipio_cobertura,
        uf_cobertura
    from {{ ref('stg_pni__doses_aplicadas') }}

),

ibge as (

    select * from {{ ref('stg_ibge__municipios') }}

),

brasilia as (

    select
        nome_municipio,
        nome_regiao,
        populacao,
        ano_populacao
    from ibge
    where id_municipio_6d = '530010'

),

uf_regiao as (

    select distinct sigla_uf, nome_regiao
    from ibge

)

select
    coalesce(s.municipio_cobertura, s.uf_cobertura)   as chave_municipio,
    s.municipio_cobertura                              as codigo_ibge,
    s.uf_cobertura                                      as uf,
    coalesce(i.nome_municipio, b.nome_municipio)        as nome_municipio,
    coalesce(
        i.nome_regiao,
        b.nome_regiao,
        ur.nome_regiao,
        case
            when s.uf_cobertura in ('SEM INFORMACAO', 'ESTRANGEIRO')
                then s.uf_cobertura
        end
    )                                                    as nome_regiao,
    coalesce(i.populacao, b.populacao)                  as populacao,
    coalesce(i.ano_populacao, b.ano_populacao)          as ano_populacao,
    case
        when s.uf_cobertura = 'SEM INFORMACAO' then 'Sem informação'
        when s.uf_cobertura = 'ESTRANGEIRO' then 'Estrangeiro'
        when i.nome_municipio is null and s.municipio_cobertura like '53%'
            and b.nome_municipio is not null
            then 'Região administrativa do DF (aprox. Brasília)'
        when i.nome_municipio is null and s.municipio_cobertura like '%0000'
            and ur.nome_regiao is not null
            then 'UF sem município específico'
        else 'Município válido'
    end as tipo_registro

from silver s
left join ibge i
    on s.municipio_cobertura = i.id_municipio_6d
left join brasilia b
    on s.municipio_cobertura like '53%' and i.nome_municipio is null
left join uf_regiao ur
    on ur.sigla_uf = s.uf_cobertura and i.nome_municipio is null
