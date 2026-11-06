"""Tira as chaves do data lake do YAML do job e guarda o valor fora do Git.

Rode depois do `databricks bundle generate job` e ANTES do primeiro `git add`:
o generate escreve as chaves do Supabase em texto, e o repositório é público.

    python tools/tirar_chaves_do_job.py

Cada chave vira `${var.<nome>}` no YAML. O valor vai para
.databricks/bundle/dev/variable-overrides.json, que o .gitignore não deixa subir.
O script nunca imprime o valor das chaves.
"""
import json
import pathlib
import re
import sys

CHAVES = {
    "s3_access_key_id": "AWS_ACCESS_KEY_ID",
    "s3_secret_access_key": "AWS_SECRET_ACCESS_KEY",
}

arquivos = sorted(pathlib.Path("resources").glob("*.job.yml"))
if not arquivos:
    sys.exit("Não achei resources/*.job.yml. Rode na raiz do repositório, depois do bundle generate job.")

valores = {}
for arquivo in arquivos:
    yml = arquivo.read_text(encoding="utf-8")
    for variavel, parametro in CHAVES.items():
        achou = re.search(rf"{parametro}: (.+)", yml)
        if not achou:
            continue
        valor = achou.group(1).strip().strip("\"'")
        if valor.startswith("${var."):  # já foi trocada numa rodada anterior
            continue
        valores[variavel] = valor
        yml = re.sub(rf"{parametro}: .+", f"{parametro}: ${{var.{variavel}}}", yml)
    arquivo.write_text(yml, encoding="utf-8")

if not valores:
    sys.exit("Nenhuma chave em texto encontrada (talvez já tenham sido trocadas). Nada foi alterado.")

pasta = pathlib.Path(".databricks/bundle/dev")
pasta.mkdir(parents=True, exist_ok=True)
destino = pasta / "variable-overrides.json"
if destino.exists():
    valores = {**json.loads(destino.read_text(encoding="utf-8")), **valores}
destino.write_text(json.dumps(valores), encoding="utf-8")
print("ok: as chaves saíram do YAML e foram para", destino)
