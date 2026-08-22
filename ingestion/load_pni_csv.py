"""
Ingestão: CSVs mensais do PNI (doses aplicadas) -> BigQuery, camada BRONZE

Por que só CSV, sem API:
  - Load job no BigQuery é SEMPRE gratuito e não consome a franquia de consulta.
  - Sem carga incremental, não há MERGE. Sem MERGE, não há consulta nenhuma na
    ingestão. Custo da camada de ingestão: R$ 0, sempre.
  - A idempotência vem da estrutura, não de código: a tabela é particionada por
    MÊS e cada arquivo é carregado com o decorador de partição em modo
    WRITE_TRUNCATE. Recarregar agosto substitui agosto e não toca nos outros
    meses. Rodar duas vezes dá o mesmo resultado que rodar uma.

Princípios da camada bronze:
  - Dado cru. Todas as colunas do CSV entram como STRING, com o nome sanitizado
    para o BigQuery. Tipagem, limpeza e regra de negócio são da silver (dbt).
  - Rastreável. Cada carga registra uma linha em `_carga_log`: arquivo, mês,
    linhas no CSV, linhas carregadas, bytes e hash do arquivo. É a evidência de
    reconciliação, e o log também é gravado por load job (gratuito).

Uso:
    python load_pni_csv.py --arquivo "C:\\dados\\pni_2026_08.csv" --mes 2026-08
    python load_pni_csv.py --pasta "C:\\dados"        # processa todos os .csv
    python load_pni_csv.py --arquivo ... --mes ... --dry-run

Variáveis de ambiente:
    GCP_PROJECT   id do projeto no Google Cloud            (obrigatório)
    BQ_DATASET    dataset destino (ex.: bronze, dev_gio)   (default: bronze)
    BQ_LOCATION   região dos datasets                      (default: US)
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import logging
import os
import re
import sys
import unicodedata
from datetime import date, datetime, timezone
from pathlib import Path

from google.cloud import bigquery

# --------------------------------------------------------------------------- #

PROJECT = os.environ.get("GCP_PROJECT")
DATASET = os.environ.get("BQ_DATASET", "bronze")
LOCATION = os.environ.get("BQ_LOCATION", "US")

TABELA = "doses_aplicadas_pni"
TABELA_LOG = "_carga_log"

# Os CSVs do DataSUS costumam vir em ISO-8859-1 com ';'. O script detecta, mas
# estes são os candidatos testados, em ordem.
ENCODINGS = ["utf-8-sig", "utf-8", "ISO-8859-1"]
DELIMITADORES = [";", ",", "\t"]

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-7s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("pni-csv")


# --------------------------------------------------------------------------- #
# Inspeção do arquivo
# --------------------------------------------------------------------------- #

def detectar_formato(caminho: Path) -> tuple[str, str]:
    """Descobre encoding e delimitador lendo só o começo do arquivo."""
    for encoding in ENCODINGS:
        try:
            with caminho.open("r", encoding=encoding, newline="") as f:
                inicio = f.read(65536)
            if not inicio:
                raise SystemExit(f"Arquivo vazio: {caminho.name}")
            primeira = inicio.splitlines()[0]
            # o delimitador correto é o que mais aparece na linha de cabeçalho
            delimitador = max(DELIMITADORES, key=primeira.count)
            if primeira.count(delimitador) == 0:
                continue
            log.info(
                "%s | encoding=%s delimitador=%r | %s colunas no cabeçalho",
                caminho.name, encoding, delimitador,
                primeira.count(delimitador) + 1,
            )
            return encoding, delimitador
        except UnicodeDecodeError:
            continue
    raise SystemExit(
        f"Não consegui decodificar {caminho.name} com {ENCODINGS}. "
        "Abra o arquivo e confira o encoding."
    )


def sanitizar(nome: str, usados: set[str]) -> str:
    """Converte o nome da coluna para algo que o BigQuery aceita.

    Regras do BigQuery: começa com letra ou _, só letras, números e _, até 300
    caracteres. Acentos e espaços são removidos. O de-para completo vai para o
    log, para que a silver possa documentar a origem de cada coluna.
    """
    sem_acento = unicodedata.normalize("NFKD", nome).encode("ascii", "ignore").decode()
    limpo = re.sub(r"[^0-9a-zA-Z_]+", "_", sem_acento).strip("_").lower()
    limpo = re.sub(r"_+", "_", limpo) or "coluna"
    if limpo[0].isdigit():
        limpo = f"c_{limpo}"
    base, n = limpo, 2
    while limpo in usados:                      # colunas duplicadas no CSV
        limpo, n = f"{base}_{n}", n + 1
    usados.add(limpo)
    return limpo


def ler_cabecalho(caminho: Path, encoding: str, delimitador: str) -> list[tuple[str, str]]:
    """Devolve [(nome_original, nome_no_bigquery)] na ordem das colunas."""
    with caminho.open("r", encoding=encoding, newline="") as f:
        original = next(csv.reader(f, delimiter=delimitador))
    usados: set[str] = set()
    pares = [(nome, sanitizar(nome, usados)) for nome in original]
    renomeadas = [(o, n) for o, n in pares if o.strip().lower() != n]
    if renomeadas:
        log.info("Colunas renomeadas para o BigQuery (%s):", len(renomeadas))
        for original_nome, novo in renomeadas[:10]:
            log.info("   %-45s -> %s", original_nome, novo)
        if len(renomeadas) > 10:
            log.info("   ... e outras %s", len(renomeadas) - 10)
    return pares


def contar_linhas(caminho: Path, encoding: str) -> int:
    """Conta as linhas de dados (exclui o cabeçalho), em streaming.

    Precisa ser streaming: o arquivo pode ter vários GB e não cabe na memória.
    """
    total = 0
    with caminho.open("r", encoding=encoding, newline="", errors="replace") as f:
        for _ in f:
            total += 1
    return max(total - 1, 0)


def hash_arquivo(caminho: Path) -> str:
    h = hashlib.sha256()
    with caminho.open("rb") as f:
        for bloco in iter(lambda: f.read(1024 * 1024), b""):
            h.update(bloco)
    return h.hexdigest()


MESES_PT = {
    "jan": "01", "fev": "02", "mar": "03", "abr": "04",
    "mai": "05", "jun": "06", "jul": "07", "ago": "08",
    "set": "09", "out": "10", "nov": "11", "dez": "12",
}


def inferir_mes(caminho: Path) -> str | None:
    """Tenta achar AAAA-MM no nome do arquivo. Aceita numérico (2026_08,
    202608, 08-2026) e abreviação em português (vacinacao_fev_2026,
    2026_fev) — esse segundo formato é o nome real dos arquivos baixados
    manualmente do portal do PNI (achado em 22/08/2026: a inferência
    numérica sozinha falhava pros 7 meses reais, que vêm nomeados
    "vacinacao_<mês_abrev>_<ano>.csv")."""
    nome = caminho.stem.lower()

    for padrao, ordem in (
        (r"(20\d{2})[-_\.]?(0[1-9]|1[0-2])", "am"),
        (r"(0[1-9]|1[0-2])[-_\.](20\d{2})", "ma"),
    ):
        m = re.search(padrao, nome)
        if m:
            ano, mes = (m.group(1), m.group(2)) if ordem == "am" else (m.group(2), m.group(1))
            return f"{ano}-{mes}"

    abrevs = "|".join(MESES_PT)
    for padrao, ordem in (
        (rf"(20\d{{2}})[-_\.]?({abrevs})", "am"),
        (rf"({abrevs})[-_\.]?(20\d{{2}})", "ma"),
    ):
        m = re.search(padrao, nome)
        if m:
            ano, mes_abrev = (m.group(1), m.group(2)) if ordem == "am" else (m.group(2), m.group(1))
            return f"{ano}-{MESES_PT[mes_abrev]}"

    return None


# --------------------------------------------------------------------------- #
# BigQuery
# --------------------------------------------------------------------------- #

def garantir_tabelas(
    client: bigquery.Client, tabela_id: str, log_id: str, colunas: list[str]
) -> None:
    """Cria a bronze (particionada por mês) e a tabela de log, se não existirem."""
    try:
        destino = client.get_table(tabela_id)
        existentes = [c.name for c in destino.schema]
        faltando = [c for c in colunas if c not in existentes]
        se_sobra = [c for c in existentes if c not in colunas]
        if faltando or se_sobra:
            log.warning(
                "SCHEMA DIVERGENTE entre o CSV e a tabela. Faltando na tabela: %s | "
                "na tabela mas não no CSV: %s",
                faltando or "nenhuma", se_sobra or "nenhuma",
            )
            log.warning(
                "Divergência de schema costuma significar que a fonte mudou o layout. "
                "Investigue antes de carregar."
            )
    except Exception:
        tabela = bigquery.Table(
            tabela_id, schema=[bigquery.SchemaField(c, "STRING") for c in colunas]
        )
        # Particionamento por tempo de carga, granularidade MENSAL. É o que
        # permite carregar com o decorador `tabela$AAAAMM` e substituir um mês
        # inteiro sem tocar nos outros — a idempotência sai da estrutura.
        tabela.time_partitioning = bigquery.TimePartitioning(
            type_=bigquery.TimePartitioningType.MONTH
        )
        tabela.description = (
            "Bronze: doses aplicadas do PNI, cru dos CSVs mensais do portal de dados "
            "abertos do Ministério da Saúde. Todas as colunas são STRING; a tipagem "
            "acontece na silver. Uma partição por mês de referência."
        )
        client.create_table(tabela)
        log.info("Tabela criada: %s (particionada por MÊS)", tabela_id)

    try:
        client.get_table(log_id)
    except Exception:
        client.create_table(
            bigquery.Table(
                log_id,
                schema=[
                    bigquery.SchemaField("carregado_em", "TIMESTAMP"),
                    bigquery.SchemaField("mes_referencia", "DATE"),
                    bigquery.SchemaField("arquivo", "STRING"),
                    bigquery.SchemaField("arquivo_sha256", "STRING"),
                    bigquery.SchemaField("arquivo_bytes", "INTEGER"),
                    bigquery.SchemaField("encoding", "STRING"),
                    bigquery.SchemaField("delimitador", "STRING"),
                    bigquery.SchemaField("linhas_no_csv", "INTEGER"),
                    bigquery.SchemaField("linhas_carregadas", "INTEGER"),
                    bigquery.SchemaField("colunas", "INTEGER"),
                    bigquery.SchemaField("reconciliado", "BOOLEAN"),
                ],
            )
        )
        log.info("Tabela de log criada: %s", log_id)


def carregar_arquivo(
    client: bigquery.Client, caminho: Path, mes: str, dry_run: bool
) -> None:
    encoding, delimitador = detectar_formato(caminho)
    pares = ler_cabecalho(caminho, encoding, delimitador)
    colunas = [novo for _, novo in pares]

    bytes_arquivo = caminho.stat().st_size
    log.info("Contando linhas de %s (%.1f MB)...", caminho.name, bytes_arquivo / 1024**2)
    linhas_csv = contar_linhas(caminho, encoding)
    log.info("%s linhas de dados | %s colunas", f"{linhas_csv:,}", len(colunas))

    if dry_run:
        log.info("--dry-run: nada foi enviado ao BigQuery.")
        return

    tabela_id = f"{PROJECT}.{DATASET}.{TABELA}"
    log_id = f"{PROJECT}.{DATASET}.{TABELA_LOG}"
    garantir_tabelas(client, tabela_id, log_id, colunas)

    # Decorador de partição: `tabela$AAAAMM` + WRITE_TRUNCATE substitui SÓ este
    # mês. É daqui que vem a idempotência.
    particao = mes.replace("-", "")
    destino = f"{tabela_id}${particao}"

    config = bigquery.LoadJobConfig(
        schema=[bigquery.SchemaField(c, "STRING") for c in colunas],
        source_format=bigquery.SourceFormat.CSV,
        skip_leading_rows=1,                    # o cabeçalho do CSV é descartado
        field_delimiter=delimitador,
        encoding="ISO-8859-1" if encoding == "ISO-8859-1" else "UTF-8",
        allow_quoted_newlines=True,
        allow_jagged_rows=False,                # linha com colunas faltando = erro
        ignore_unknown_values=False,            # coluna extra = erro, não silêncio
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        max_bad_records=0,                      # zero tolerância: queremos saber
    )

    log.info("Carregando em %s ...", destino)
    with caminho.open("rb") as f:
        job = client.load_table_from_file(f, destino, job_config=config)
    try:
        job.result()
    except Exception:
        for erro in (job.errors or [])[:5]:
            log.error("Erro do BigQuery: %s", erro.get("message", erro))
        raise

    carregadas = job.output_rows or 0
    reconciliado = carregadas == linhas_csv

    log.info("--- reconciliação ---")
    log.info("linhas no CSV ......... %s", f"{linhas_csv:,}")
    log.info("linhas carregadas ..... %s", f"{carregadas:,}")
    log.info("diferença ............. %s", f"{carregadas - linhas_csv:,}")
    log.info("custo da carga ........ R$ 0 (load job é gratuito)")

    # O log é gravado mesmo quando a reconciliação falha: o registro da falha faz
    # parte da evidência de qualidade.
    client.load_table_from_json(
        [{
            "carregado_em": datetime.now(timezone.utc).isoformat(),
            "mes_referencia": f"{mes}-01",
            "arquivo": caminho.name,
            "arquivo_sha256": hash_arquivo(caminho),
            "arquivo_bytes": bytes_arquivo,
            "encoding": encoding,
            "delimitador": delimitador,
            "linhas_no_csv": linhas_csv,
            "linhas_carregadas": carregadas,
            "colunas": len(colunas),
            "reconciliado": reconciliado,
        }],
        log_id,
        job_config=bigquery.LoadJobConfig(
            write_disposition=bigquery.WriteDisposition.WRITE_APPEND
        ),
    ).result()

    if not reconciliado:
        raise SystemExit(
            f"FALHA DE RECONCILIAÇÃO em {caminho.name}: o CSV tem {linhas_csv:,} "
            f"linhas e foram carregadas {carregadas:,}. A partição {particao} está "
            "inconsistente — investigue antes de seguir para a silver."
        )
    log.info("OK: %s -> partição %s", caminho.name, particao)


# --------------------------------------------------------------------------- #

def main() -> None:
    p = argparse.ArgumentParser(description="Carga dos CSVs do PNI na bronze do BigQuery")
    p.add_argument("--arquivo", help="caminho de um CSV")
    p.add_argument("--pasta", help="pasta com vários CSVs (processa todos)")
    p.add_argument("--mes", help="mês de referência AAAA-MM (default: inferido do nome)")
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="inspeciona e conta linhas sem enviar nada ao BigQuery",
    )
    args = p.parse_args()

    if not args.arquivo and not args.pasta:
        p.error("informe --arquivo ou --pasta")
    if not args.dry_run and not PROJECT:
        raise SystemExit("Defina GCP_PROJECT antes de rodar.")

    if args.arquivo:
        arquivos = [Path(args.arquivo)]
    else:
        arquivos = sorted(Path(args.pasta).glob("*.csv"))
        if not arquivos:
            raise SystemExit(f"Nenhum .csv em {args.pasta}")

    client = None if args.dry_run else bigquery.Client(project=PROJECT, location=LOCATION)
    falhas = 0

    for caminho in arquivos:
        if not caminho.exists():
            log.error("Não encontrado: %s", caminho)
            falhas += 1
            continue

        mes = args.mes or inferir_mes(caminho)
        if not mes:
            log.error(
                "Não consegui inferir o mês de '%s'. Rode com --mes AAAA-MM.",
                caminho.name,
            )
            falhas += 1
            continue

        log.info("=" * 70)
        log.info("%s | mês de referência %s", caminho.name, mes)
        try:
            carregar_arquivo(client, caminho, mes, args.dry_run)
        except SystemExit as e:
            log.error("%s", e)
            falhas += 1

    if falhas:
        sys.exit(f"{falhas} arquivo(s) com problema.")
    log.info("Todos os arquivos carregados e reconciliados.")


if __name__ == "__main__":
    main()
