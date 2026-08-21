# Caminhos avaliados e descartados

Esta pasta guarda código e evidências de alternativas que foram
construídas e/ou avaliadas e não escolhidas. Isso fortalece os ADRs
(`docs/adr/`) ao mostrar que a decisão não foi por falta de tentativa — é um
dos critérios que a banca mais valoriza.

- **`load_pni.py`** (a mover para cá): versão que ingeria pela API REST do
  PNI com `MERGE` por `codigo_documento`, incluindo dry run de custo e
  `maximum_bytes_billed`. Substituída pela ingestão somente-CSV — ver
  [ADR 0002](../adr/0002-ingestao-somente-csv-recarga-por-particao.md).
