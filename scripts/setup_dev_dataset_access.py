"""
Concede acesso do Ellen/Andressa aos datasets do BigQuery.

Por que este script existe (e não só comandos `bq add-iam-policy-binding`):
o `bq add-iam-policy-binding` em nível de DATASET (diferente do nível de
projeto, que funcionou normalmente) retornou:

    BigQuery error in add-iam-policy-binding operation: This feature
    requires allowlisting.

Isso é um comportamento conhecido do caminho "IAM policy" mais novo pra
datasets do BigQuery em alguns projetos/contas — a alternativa estável é a
API de ACL clássica de dataset (`Dataset.access_entries`), que é a mesma
coisa que a UI do console faz quando você clica em "Sharing > Permissions"
num dataset, só que sem passar pelo endpoint que exige allowlist. Rodar
este script tem o mesmo efeito prático dos comandos `bq` que tentamos
antes, só que por um caminho que já é GA pra qualquer projeto.

Uso: python scripts/setup_dev_dataset_access.py
Requer: `gcloud auth application-default login` já feito (mesma credencial
usada pelo dbt e pelo load_pni_csv.py) e `google-cloud-bigquery` instalado
(já está no requirements.txt).

Sem custo: mudar o controle de acesso de um dataset não gera cobrança.
"""

from google.cloud import bigquery

PROJECT = "projeto-mba-uniesp"

# (dataset, [(papel_classico, email), ...])
# WRITER  ~ roles/bigquery.dataEditor (pode criar/alterar tabelas e views)
# READER  ~ roles/bigquery.dataViewer (só leitura, necessário pro dbt ler os sources)
GRANTS = [
    ("dev_ellen", [("WRITER", "ellen.victorya@academico.ufpb.br")]),
    ("dev_andressa", [("WRITER", "abbsmendes@gmail.com")]),
    ("bronze", [
        ("READER", "ellen.victorya@academico.ufpb.br"),
        ("READER", "abbsmendes@gmail.com"),
    ]),
    ("silver", [
        ("READER", "ellen.victorya@academico.ufpb.br"),
        ("READER", "abbsmendes@gmail.com"),
    ]),
    ("gold", [
        ("READER", "ellen.victorya@academico.ufpb.br"),
        ("READER", "abbsmendes@gmail.com"),
    ]),
]


def main():
    client = bigquery.Client(project=PROJECT)

    for dataset_name, entries in GRANTS:
        dataset_ref = f"{PROJECT}.{dataset_name}"
        dataset = client.get_dataset(dataset_ref)

        existing = {(e.role, e.entity_type, e.entity_id) for e in dataset.access_entries}
        access_entries = list(dataset.access_entries)

        for role, email in entries:
            key = (role, "userByEmail", email)
            if key in existing:
                print(f"  já tinha: {dataset_name} — {role} — {email}")
                continue
            access_entries.append(
                bigquery.AccessEntry(role=role, entity_type="userByEmail", entity_id=email)
            )
            print(f"  adicionando: {dataset_name} — {role} — {email}")

        dataset.access_entries = access_entries
        client.update_dataset(dataset, ["access_entries"])
        print(f"OK: {dataset_name}\n")


if __name__ == "__main__":
    main()
