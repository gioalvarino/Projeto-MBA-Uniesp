# ADR 0001: Escolha da fonte de dados — PNI (doses aplicadas)

- **Status:** aceita
- **Data:** 2026-08-21
- **Responsável:** trio

## Contexto

O enunciado exige uma fonte real ou pública transformada em informação
consumível. O trio buscava um tema com volume real, atualização frequente,
dado "sujo" de verdade (para dar função de fato à camada de qualidade) e uma
pergunta de negócio óbvia para sustentar o insight final.

## Opções consideradas

1. **PNI — doses aplicadas (Programa Nacional de Imunizações)**, portal de
   dados abertos do Ministério da Saúde. Tema de cobertura vacinal.
2. Outras fontes públicas não foram aprofundadas com o mesmo nível de
   investigação — o PNI já atendia todos os critérios e casa com a área de
   dispositivos médicos da Giovanna.

## Decisão

Fonte: doses aplicadas do PNI, `dadosabertos.saude.gov.br`.

**Insight alvo:** cobertura vacinal por município contra a meta, cruzando com
população do IBGE — onde há queda de cobertura e desigualdade regional.

## Consequências

- O dado contém informação pessoal sensível pseudonimizada (não anônima) —
  exige tratamento explícito de LGPD (ver ADR 0005).
- É dado aberto governamental com qualidade real de produção: nomes de
  município inconsistentes, nulos, códigos sem de-para — ver
  `docs/dicionario_dados.md` e a suíte de testes do dbt.
