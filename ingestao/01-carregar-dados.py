# Databricks notebook source
# MAGIC %md
# MAGIC # Carga inicial dos dados da Vértice Tecnologia
# MAGIC
# MAGIC Ponto de partida: a diretoria da Vértice faz a primeira pergunta:
# MAGIC *quais projetos estão mais atrasados?* Ninguém sabe responder, porque cada gerente usa uma ferramenta.
# MAGIC
# MAGIC Rode este notebook **uma vez**, de cima para baixo (botão **Run all**). Ele:
# MAGIC
# MAGIC 1. cria o catálogo `lakehouse_vertice`, os schemas `bronze`, `silver`, `gold` e o volume `bronze.raw`
# MAGIC 2. gera os arquivos **direto no volume**: 20 planilhas Excel, 25 exports do ClickUp, 15 arquivos do MS Project,
# MAGIC    os CSVs do PMO, RH, timesheet, financeiro e compras, e os contratos em PDF
# MAGIC 3. confere que os 5 padrões da história estão lá
# MAGIC
# MAGIC Nada para baixar nem subir: o gerador está neste repositório (`data/gerar_dataset.py`) e a seed é fixa,
# MAGIC então o dado é **reproduzível**: toda execução gera os mesmos arquivos.
# MAGIC
# MAGIC > Para abrir este notebook, clone o repositório como **Git folder**
# MAGIC > (Workspace → Create → Git folder → `https://github.com/RamonRibeiroF/projeto-farol`).

# COMMAND ----------

dbutils.widgets.text("catalogo", "lakehouse_vertice")
CATALOGO = dbutils.widgets.get("catalogo")

import os, pathlib, sys

AQUI = pathlib.Path(os.getcwd())                 # a pasta deste notebook dentro do Git folder
RAIZ = AQUI.parent
print("repositório em", RAIZ)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1. O catálogo
# MAGIC Roda o `00-setup-catalogo.sql`, o mesmo arquivo que dá para rodar no SQL Editor.

# COMMAND ----------

sql = (AQUI / "00-setup-catalogo.sql").read_text(encoding="utf-8").replace("lakehouse_vertice", CATALOGO)
comandos = [c.strip() for c in sql.split(";")
            if any(l.strip() and not l.strip().startswith("--") for l in c.splitlines())]
for c in comandos:
    spark.sql(c)
    print("ok:", next(l for l in c.splitlines() if l.strip() and not l.strip().startswith("--"))[:80])

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2. Os arquivos das ferramentas, direto no volume

# COMMAND ----------

sys.path.insert(0, str(RAIZ / "data"))
import gerar_dataset

destino = pathlib.Path(f"/Volumes/{CATALOGO}/bronze/raw")
for pasta in gerar_dataset.PASTAS_GERADAS:
    if (destino / pasta).exists():
        import shutil
        shutil.rmtree(destino / pasta)
contagens = gerar_dataset.gerar(destino, seed=42)
for k, v in contagens.items():
    print(f"{k:<20} {v:>9,}".replace(",", "."))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3. Conferência: a história está no dado?
# MAGIC Junta as três ferramentas em Python, recalcula SPI e CPI e checa os 5 padrões
# MAGIC (CPI caindo, freeze da Black Friday, consultoria atrasada, SREs ociosos, squad com rotatividade).

# COMMAND ----------

import subprocess
r = subprocess.run([sys.executable, str(RAIZ / "data" / "validar_padroes.py"), "--dados", str(destino)],
                   capture_output=True, text=True)
print(r.stdout[-3000:])
assert r.returncode == 0, r.stderr or "algum padrão falhou"

# COMMAND ----------

# MAGIC %md
# MAGIC ## Pronto
# MAGIC Agora abra o **`01-ingestao-bronze.sql`** no SQL Editor e rode tudo: os arquivos viram as 9 tabelas da bronze.
