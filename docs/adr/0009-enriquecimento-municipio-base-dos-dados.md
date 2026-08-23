# ADR 0009: Enriquecimento de município — nome e população via Base dos Dados/IBGE

- **Status:** aceita
- **Data:** 2026-08-23
- **Responsável:** Giovanna

## Contexto

O ADR 0004 já previa esse enriquecimento acontecendo na silver, e o ADR 0001
registra o insight alvo do projeto: cobertura vacinal por município cruzando
com população do IBGE. Sem nome e população reais, `dim_municipio` (ADR
0007 + ADR 0008) só permitia contar doses, não calcular a taxa de cobertura
(doses ÷ população) — o indicador central do produto. Com o modelo estrela
inteiro já validado contra os 7 meses reais, esse era o próximo bloqueio
real.

## Opções consideradas

1. **Baixar uma planilha/CSV oficial do IBGE (população estimada) e
   versionar como seed**, igual `uf_ibge.csv`/`faixa_etaria.csv`. Simples e
   sem dependência externa em tempo de consulta, mas exige atualização
   manual a cada nova estimativa do IBGE, e nome de município já é uma
   tabela maior (5.570 linhas) que não muda com frequência suficiente pra
   justificar reprocessar/versionar à mão.
2. **Consultar o dataset público da Base dos Dados diretamente no
   BigQuery** (`basedosdados.br_bd_diretorios_brasil.municipio` e
   `basedosdados.br_ibge_populacao.municipio`), via `source()` do dbt. Sem
   cópia de dado, sem custo de armazenamento nosso, mesma fonte (IBGE) já
   tratada e num formato que casa direto com o código de município que já
   usamos (`id_municipio`, 7 dígitos). Dependência de um projeto público de
   terceiros permanecer disponível — aceitável pro escopo do projeto.

## Decisão

Consultar a Base dos Dados diretamente como `source` do dbt, num novo model
de silver (`stg_ibge__municipios`) — schema confirmado contra o dado real
em 23/08/2026. `dim_municipio` (gold) passa a fazer `left join` desse model
por `id_municipio = municipio_cobertura`.

**População:** estimativa de **2025** por padrão (ano mais recente
disponível), com fallback pro ano anterior mais recente que tiver valor
preenchido, por município — ver "Refinamento" abaixo. É estimativa, não
censo, e não é o mesmo ano dos dados de vacinação (2026) — melhor
aproximação disponível. `dim_municipio` expõe `ano_populacao` pra deixar
explícito de qual ano veio a estimativa usada em cada linha.

**Refinamento (achado real, 23/08/2026):** o primeiro `dbt build` acusou 1
`warn` — `Boa Esperança do Norte/MT` (`5101837`), município antigo e já
estabelecido (não é criação recente por desmembramento), com `populacao`
nula pra `ano=2025`. Ajustei `stg_ibge__municipios` pra usar a estimativa
mais recente disponível **com valor preenchido** (`populacao is not null`)
até 2025, em vez de exigir exatamente 2025 — pensado pra autocorrigir
lacunas pontuais de um ano específico. O `warn` persistiu depois do
ajuste; não deu pra confirmar por consulta direta se esse município tem
valor preenchido em algum ano anterior na Base dos Dados (consulta travou
sem retornar), então fica registrado como **limitação aceita**: 1 de 5.570
municípios (0,018%) sem população disponível na fonte, por motivo não
totalmente investigado. O ajuste de "ano mais recente com valor" continua
correto e é mantido (resolve o caso geral e qualquer lacuna de só-um-ano
que apareça no futuro); esse caso específico só não tem dado nenhum pra
usar.

## Consequências

- `dim_municipio.nome_municipio`/`populacao`/`ano_populacao` passam a vir
  preenchidos pra município real; continuam nulos só pros membros
  especiais ('ESTRANGEIRO'/'SEM INFORMACAO', sem código IBGE de verdade
  pra casar).
- Município real que não casar com a Base dos Dados (código descontinuado,
  por exemplo), ou que não tenha NENHUM ano com população preenchida (1
  caso conhecido, Boa Esperança do Norte/MT), também fica com
  nome/população nulos — teste `not_null` em `populacao` fica como `warn`
  em `stg_ibge__municipios` de propósito, pra sinalizar sem travar o
  pipeline por 1 caso isolado e não solucionável do nosso lado.
- A taxa de cobertura (doses ÷ população) já pode ser calculada no Power BI
  a partir daqui — desbloqueia o insight alvo do ADR 0001.
- Consulta a dataset público não copia dado pro nosso projeto (sem custo de
  armazenamento) e o volume consultado é pequeno (~5,6 mil municípios) —
  custo de processamento irrisório, dentro do free tier de 1 TB/mês.
- Diferente de `co_vacina`/`co_dose_vacina`/`co_estrategia_vacinacao`, esse
  de-para não depende de uma tabela oficial pendente do PNI — a Base dos
  Dados já resolve nome e população de município de forma completa.
