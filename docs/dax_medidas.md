# Medidas DAX — Plataforma de Cobertura Vacinal (PNI/DataSUS)

Organizadas pelos nomes reais de tabela/coluna do modelo gold (conferidos direto nos `.sql`/seeds do repositório em 24/08/2026). Cole cada bloco como uma medida nova, de preferência numa tabela só de medidas (crie uma "Consulta em branco" vazia chamada `_Medidas` no Power Query e mova as medidas pra lá — deixa o modelo mais organizado, mas é opcional).

## 0. Pré-requisitos no modelo antes de colar

- Relações fato → dimensão precisam existir por essas chaves: `fct_cobertura_vacinal[chave_municipio] → dim_municipio[chave_municipio]`, `[chave_vacina] → dim_vacina[chave_vacina]`, `[chave_faixa_etaria] → faixa_etaria[ordem]` (já criada, segundo você confirmou), `[chave_perfil] → dim_perfil_paciente[chave_perfil]`, `[chave_estrategia] → dim_estrategia_vacinacao[chave_estrategia]`.
- **Confira se `fct_cobertura_vacinal[mes_vacina] → dim_tempo[mes]` existe.** Os nomes são diferentes (`mes_vacina` vs. `mes`), então o autodetect do Power BI pode não ter criado — mesmo problema que aconteceu com `faixa_etaria`. Se não existir, crie manualmente no Model view.
- **Marque `dim_tempo` como tabela de datas:** clique na tabela → aba Table tools → "Mark as Date Table" → coluna `mes`. As medidas de inteligência de tempo (seção 3) não funcionam sem isso.
- `meta_vacinal` **não tem relação com a fato nem com `dim_vacina`** — é proposital (ver ADR 0010): os ~90 nomes reais de `dim_vacina.nome_vacina` ainda não têm de-para pras 19 vacinas oficiais do calendário. Trate `meta_vacinal` como tabela solta, útil só pra linha de referência/meta num gráfico, não pra filtrar cobertura real por vacina ainda.

## 1. Medidas base

```dax
Total de Doses Aplicadas = SUM(fct_cobertura_vacinal[qtd_doses])
```

```dax
População Coberta = SUM(dim_municipio[populacao])
```

> `populacao` mora em `dim_municipio`, uma linha por município — somar direto já dá o total correto no contexto de filtro, sem duplicar por causa das várias linhas da fato ligadas a cada município.

```dax
Total de Municípios (Cobertura Real) =
CALCULATE(
    DISTINCTCOUNT(dim_municipio[chave_municipio]),
    dim_municipio[tipo_registro] IN {"Município válido", "Região administrativa do DF (aprox. Brasília)"}
)
```

> Exclui de propósito `'Sem informação'`/`'Estrangeiro'` da contagem de municípios — eles são membros válidos da dimensão, mas não são município geográfico de verdade.

```dax
Total de Vacinas Distintas = DISTINCTCOUNT(dim_vacina[chave_vacina])
```

## 2. Cobertura e meta

```dax
Taxa de Cobertura = DIVIDE([Total de Doses Aplicadas], [População Coberta])
```

```dax
Cobertura por 100 mil Habitantes = DIVIDE([Total de Doses Aplicadas], [População Coberta]) * 100000
```

```dax
Meta Oficial de Cobertura (referência) = AVERAGE(meta_vacinal[meta_cobertura])
```

> Só funciona como **linha de referência solta** num gráfico (ex.: combo chart com um slicer de `meta_vacinal[vacina]` independente, filtrando só essa tabela) — não cruza com a cobertura real por vacina enquanto o de-para do ADR 0010 não for feito. Se usar sem nenhum filtro em `meta_vacinal`, essa medida retorna a média das 19 metas oficiais (não é o número certo pra comparar com uma vacina específica).

```dax
Gap para a Meta (p.p.) =
([Taxa de Cobertura] - [Meta Oficial de Cobertura (referência)]) * 100
```

> Mesma ressalva acima: só é uma comparação válida enquanto a meta selecionada corresponder de fato à vacina em análise — hoje isso exige conferência manual, não é automático.

## 3. Variação no tempo (mês a mês)

```dax
Doses Mês Anterior = CALCULATE([Total de Doses Aplicadas], DATEADD(dim_tempo[mes], -1, MONTH))
```

```dax
Variação MoM (%) = DIVIDE([Total de Doses Aplicadas] - [Doses Mês Anterior], [Doses Mês Anterior])
```

```dax
Doses Acumuladas no Ano (YTD) = TOTALYTD([Total de Doses Aplicadas], dim_tempo[mes])
```

## 4. Desigualdade regional — o insight central do projeto (ADR 0001)

```dax
Cobertura Média entre Municípios = AVERAGEX(VALUES(dim_municipio[chave_municipio]), [Taxa de Cobertura])
```

> Diferente de `[Taxa de Cobertura]` sozinha: essa é a média das taxas individuais de cada município (dá o mesmo peso pra município pequeno e grande), enquanto `[Taxa de Cobertura]` é a razão agregada (dominada pelos municípios com mais população/doses). As duas contam histórias diferentes — vale mostrar as duas lado a lado.

```dax
Desvio-Padrão da Cobertura entre Municípios = STDEVX.P(VALUES(dim_municipio[chave_municipio]), [Taxa de Cobertura])
```

```dax
Coeficiente de Variação da Cobertura =
DIVIDE([Desvio-Padrão da Cobertura entre Municípios], [Cobertura Média entre Municípios])
```

> Quanto maior, mais desigual a cobertura entre municípios — é literalmente uma medida de "desigualdade regional", o termo usado no próprio slide 3 da apresentação.

```dax
Ranking do Município por Cobertura (pior primeiro) =
RANKX(ALL(dim_municipio[chave_municipio]), [Taxa de Cobertura], , ASC)
```

> Ordem ascendente de propósito — rank 1 é o município com **menor** cobertura, útil pra uma tabela "top piores" sem precisar inverter nada na visualização.

```dax
% de Municípios Abaixo da Meta =
DIVIDE(
    CALCULATE(
        DISTINCTCOUNT(dim_municipio[chave_municipio]),
        FILTER(VALUES(dim_municipio[chave_municipio]), [Taxa de Cobertura] < [Meta Oficial de Cobertura (referência)])
    ),
    [Total de Municípios (Cobertura Real)]
)
```

> Herda a mesma ressalva do de-para de vacina (seção 2) — só é comparável de fato depois que a meta certa estiver ligada à vacina certa.

## 5. Diagnóstico e qualidade de dados

```dax
% de Doses em Registro Não-Município Válido =
DIVIDE(
    CALCULATE([Total de Doses Aplicadas], dim_municipio[tipo_registro] <> "Município válido"),
    [Total de Doses Aplicadas]
)
```

> Mede o peso real das exceções documentadas na ADR 0009 (Regiões Administrativas do DF, sentinelas "UF+0000", os 5 residuais, "Sem informação"/"Estrangeiro") sobre o total de doses — bom pra mostrar na apresentação que a limitação aceita é pequena em volume, não só em contagem de códigos.

## 6. Perfil demográfico e estratégia (participação % no total)

```dax
% de Doses por Faixa Etária = DIVIDE([Total de Doses Aplicadas], CALCULATE([Total de Doses Aplicadas], ALL(faixa_etaria)))
```

```dax
% de Doses por Estratégia = DIVIDE([Total de Doses Aplicadas], CALCULATE([Total de Doses Aplicadas], ALL(dim_estrategia_vacinacao)))
```

```dax
% de Doses por Perfil (Raça/Cor + Sexo) = DIVIDE([Total de Doses Aplicadas], CALCULATE([Total de Doses Aplicadas], ALL(dim_perfil_paciente)))
```

---

**Pendências que afetam estas medidas** (já registradas no projeto): o de-para entre `meta_vacinal` e `dim_vacina` (seção 2 e o item de "% Municípios Abaixo da Meta" na seção 4 ficam só parcialmente úteis até isso ser resolvido); e a migração de `fct_cobertura_vacinal` pra materialização incremental, que não afeta as medidas em si, mas reduz o custo de cada vez que o modelo for atualizado no Power BI.
