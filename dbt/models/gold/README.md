# gold

Ainda vazio. Vai conter o modelo estrela: fato de doses aplicadas +
dimensões de tempo, município, vacina, estabelecimento e faixa etária.

A decisão de geografia de cobertura (município de aplicação vs. residência)
já foi tomada — ver
[`docs/adr/0007-geografia-de-cobertura-municipio-residencia.md`](../../docs/adr/0007-geografia-de-cobertura-municipio-residencia.md).
A fato de doses deve usar `municipio_cobertura`/`uf_cobertura` (já
resolvidos na silver, `stg_pni__doses_aplicadas`), nunca as colunas cruas de
paciente/estabelecimento diretamente. A dimensão de município ainda precisa
tratar o caso `municipio_cobertura is null` (estrangeiro/sem informação) —
ver "Consequências" no ADR 0007.

Falta ainda o enriquecimento com Base dos Dados/IBGE (população por
município, pra calcular a taxa de cobertura). Ver
[`docs/adr/0004-arquitetura-medalhao.md`](../../docs/adr/0004-arquitetura-medalhao.md).
