#!/usr/bin/env python3
"""Dá ao service principal de um Databricks App acesso de leitura à gold e à silver.

O app roda como o próprio service principal: sem estes GRANT, o build e as queries falham com
INSUFFICIENT_PERMISSIONS. Lê o service_principal_client_id com `databricks apps get` e roda os
GRANT pelo tools/run_sql.py (uma statement por vez).

Uso (funciona no Windows):
  python tools/conceder_acesso.py --profile <perfil> --app farol-torre
"""
import argparse
import json
import pathlib
import subprocess
import sys
import tempfile

AQUI = pathlib.Path(__file__).resolve().parent
CATALOGO = "lakehouse_vertice"
SCHEMAS = ["gold", "silver"]


def client_id_do_app(app: str, profile: str) -> str:
    r = subprocess.run(["databricks", "apps", "get", app, "--profile", profile, "-o", "json"],
                       capture_output=True, text=True, encoding="utf-8")
    if r.returncode != 0:
        sys.exit(f"não achei o app {app}: {r.stderr.strip()}")
    sp = json.loads(r.stdout).get("service_principal_client_id")
    if not sp:
        sys.exit(f"o app {app} ainda não tem service principal (faça o bundle deploy antes)")
    return sp


def grants(sp: str) -> str:
    linhas = [f"GRANT USE CATALOG ON CATALOG {CATALOGO} TO `{sp}`;"]
    for schema in SCHEMAS:
        linhas.append(f"GRANT USE SCHEMA ON SCHEMA {CATALOGO}.{schema} TO `{sp}`;")
        linhas.append(f"GRANT SELECT ON SCHEMA {CATALOGO}.{schema} TO `{sp}`;")
    return "\n".join(linhas) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", required=True, help="profile do ~/.databrickscfg (sempre explícito)")
    ap.add_argument("--app", required=True, help="nome do Databricks App")
    a = ap.parse_args()

    sp = client_id_do_app(a.app, a.profile)
    print(f"service principal do {a.app}: {sp}")
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False, encoding="utf-8") as f:
        f.write(grants(sp))
        arquivo = f.name
    try:
        return subprocess.run([sys.executable, str(AQUI / "run_sql.py"), arquivo, "--profile", a.profile]).returncode
    finally:
        pathlib.Path(arquivo).unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main())
