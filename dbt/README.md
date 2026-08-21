# Projeto dbt

Ainda não criado. Vai conter os modelos silver (tipagem, deduplicação por
`codigo_documento`, padronização, enriquecimento com Base dos Dados/IBGE) e
gold (modelo estrela: fato de doses aplicadas + dimensões de tempo,
município, vacina, estabelecimento e faixa etária), além da suíte de testes
(`not_null`, `unique`, `relationships`, `accepted_values`, faixas plausíveis
e o teste de reconciliação bronze × gold).

Ver [`docs/adr/0004-arquitetura-medalhao.md`](../docs/adr/0004-arquitetura-medalhao.md)
para a justificativa da separação em camadas.

`profiles.yml` **não** é versionado (está no `.gitignore`) — cada pessoa
mantém o seu, apontando para o próprio dataset `dev_<nome>`, com
`maximum_bytes_billed: 10000000000` (proteção de custo).
