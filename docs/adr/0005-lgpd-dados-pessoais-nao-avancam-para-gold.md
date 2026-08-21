# ADR 0005: LGPD — dado pessoal não avança além da silver

- **Status:** aceita
- **Data:** 2026-08-21
- **Responsável:** trio

## Contexto

O payload do PNI traz dado pessoal sensível pseudonimizado (não anônimo):
`codigo_paciente` (hash), `numero_cep_paciente`, `numero_idade_paciente`,
`codigo_raca_cor_paciente`, `codigo_etnia_indigena_paciente`,
`tipo_sexo_paciente`.

## Decisão

CEP e código de paciente não avançam para a camada gold. Toda agregação de
consumo é feita por município e faixa etária, nunca por indivíduo.

## Consequências

- A gold não permite reidentificação por registro individual, mas ainda
  suporta o insight de cobertura vacinal por município.
- Um parágrafo específico sobre tratamento de LGPD entra no relatório final
  — projeto de saúde que ignora isso é o tipo de ponto que a banca cutuca.
