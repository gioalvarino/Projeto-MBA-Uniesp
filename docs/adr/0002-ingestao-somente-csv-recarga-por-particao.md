# ADR 0002: Ingestão somente por CSV mensal, recarga por partição

- **Status:** aceita (substitui um plano híbrido anterior)
- **Data:** 2026-08-21
- **Responsável:** Giovanna

## Contexto

A fonte PNI expõe dois canais equivalentes: CSVs mensais (23 arquivos, 60
colunas, atualização semanal) e uma API REST
(`https://apidadosabertos.saude.gov.br/vacinacao/doses-aplicadas-pni-2026`,
49 campos). A API foi investigada e testada antes de decidir.

## Opções consideradas

1. **Ingestão via API REST com `MERGE` por `codigo_documento`** — permitiria
   carga incremental, mas a API **não garante ordenação**: os registros
   voltam com datas embaralhadas, então a paginação por `offset` não é
   estável entre requisições. Sem ordenação estável, a deduplicação exigiria
   `MERGE`, que consome a franquia de consulta e adiciona complexidade só
   para resolver um problema que a recarga mensal não tem. Uma versão desta
   abordagem foi construída (`docs/descartados/load_pni.py`) e depois
   aposentada — mantida como evidência do processo de decisão.
2. **CSV mensal com recarga completa por partição (escolhida).** Cada
   arquivo é carregado por *load job*, que no BigQuery é sempre gratuito e
   não consome a franquia de consulta. A tabela bronze é particionada por
   mês, e cada arquivo entra pelo decorador de partição (`tabela$AAAAMM`) em
   modo `WRITE_TRUNCATE` — recarregar um mês substitui só aquele mês.

## Decisão

Opção 2: somente CSV, recarga por partição mensal. Sem carga incremental,
sem `MERGE`, sem nenhuma consulta na etapa de ingestão.

## Consequências

- A idempotência vem da estrutura da tabela (partição + `WRITE_TRUNCATE`),
  não de código de deduplicação — menos superfície para erro.
- Custo da camada de ingestão: R$ 0, sempre.
- O dado não é near-real-time: a fonte é atualizada semanalmente e a recarga
  do mês corrente cobre isso — a defasagem máxima é o intervalo entre
  execuções, o que é adequado para uma análise de cobertura vacinal.
- A atualização mensal passa a ser uma operação manual (baixar o arquivo do
  mês novo e rodar o script de novo), a menos que se resolva a pendência da
  URL estável de download (ver seção de pendências no handoff).
