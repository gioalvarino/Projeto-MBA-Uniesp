# Dicionário de dados — PNI (doses aplicadas)

> Os nomes de coluna abaixo vêm da API do PNI (49 campos). O CSV tem 60
> colunas e provavelmente usa rótulos diferentes (com acento e espaço) —
> `ingestion/load_pni_csv.py` lê o cabeçalho do próprio arquivo e sanitiza os
> nomes automaticamente, então não é preciso adivinhar. Confirmar os
> equivalentes reais do CSV é pendência: rodar `--dry-run` num arquivo e
> conferir o de-para impresso no log.

## Campos-chave

| Campo | Papel |
|---|---|
| `codigo_documento` | UUID por dose → chave única para deduplicação na silver |
| `data_entrada_rnds` | Data de entrada no RNDS → mede a defasagem da fonte |
| `data_deletado_rnds` | Exclusão lógica na origem → filtrar na silver |
| `data_vacina` | Data do evento (vem com hora `00:00:00-03`; é DATE, não timestamp) |
| `codigo_municipio_estabelecimento` / `codigo_municipio_paciente` | Códigos IBGE — as duas geografias possíveis (ver ADR 0001 sobre qual usar no cálculo de cobertura) |
| `codigo_vacina`, `codigo_dose_vacina` | Códigos numéricos; precisam de de-para do dicionário oficial do PNI (pendente) |
| `status_documento` | Observado sempre `"final"` na amostra; verificar se existem outros valores |

## Códigos pendentes de de-para

- `codigo_vacina`
- `codigo_dose_vacina`
- `codigo_estrategia_vacinacao`

## Regras de qualidade conhecidas

- Nomes de município inconsistentes entre estabelecimento e paciente (ex.:
  "AREZ" no estabelecimento e "ARES" no paciente, mesmo código IBGE
  `240120`). **Regra: juntar sempre pelo código, nunca pelo nome.**
- `numero_idade_paciente = "0"` é bebê de menos de 1 ano, não idade
  faltante — cuidado ao montar faixas etárias.
- `codigo_municipio_paciente` vem nulo em parte dos registros — esses não
  entram no cálculo de cobertura por residência; contar e expor na tela de
  qualidade.
- CEP sujo — nulos e valores genéricos como `55000000`.
- `codigo_raca_cor_paciente = 99` ("SEM INFORMACAO") é muito frequente.
- `descricao_vacina_fabricante` nulo em parte dos registros.
- `nome_fantasia_estalecimento` — o typo é da própria API/fonte. Mantido cru
  na bronze (fidelidade ao dado original), renomear só na silver.
