# Databricks notebook source
# MAGIC %md
# MAGIC # Ingestão de uma API: feriados nacionais de 2026
# MAGIC
# MAGIC Quando a fonte não tem conector, entra o Python, sempre em três passos: **extrair** (pedir à API),
# MAGIC **pousar** (guardar o arquivo no raw, do jeito que veio) e **carregar** (o `read_files` transforma o arquivo
# MAGIC em tabela).
# MAGIC
# MAGIC **Pergunta de negócio:** quantos dias úteis a Vértice perde em novembro, bem quando começa o change freeze
# MAGIC da Black Friday (01/11)?
# MAGIC
# MAGIC **Sobre a fonte.** O Databricks Free Edition só libera a saída para a internet para uma lista de sites
# MAGIC confiáveis, e a BrasilAPI não está nela (erro `NameResolutionError`). Para manter o exercício com uma chamada
# MAGIC HTTP de verdade, o mesmo JSON dos feriados de 2026, no formato da BrasilAPI (`date`, `name`, `type`), fica
# MAGIC publicado neste repositório (`data/feriados-2026.json`) e a API consultada é a do GitHub (`raw.githubusercontent.com`).
# MAGIC
# MAGIC ## Passo 1 · Extrair: pedir os feriados à API

# COMMAND ----------

import requests                # conversa com a API (HTTP)

url = "https://raw.githubusercontent.com/RamonRibeiroF/projeto-farol/main/data/feriados-2026.json"
resposta = requests.get(url, timeout=30)
resposta.raise_for_status()    # se a fonte cair, para aqui com o erro, em vez de seguir com nada

feriados = resposta.json()     # o JSON vira uma lista do Python: um dicionário por feriado
print(len(feriados), "feriados")
feriados[:3]

# COMMAND ----------

# MAGIC %md
# MAGIC ## Passo 2 · Pousar: o JSON numa pasta nova do raw
# MAGIC
# MAGIC Cada execução grava um arquivo **novo**, com a data e a hora no nome. O raw guarda o histórico de tudo o que
# MAGIC chegou: dá para saber o que a fonte respondia em cada momento.

# COMMAND ----------

import json, os
from datetime import datetime

pasta = "/Volumes/lakehouse_vertice/bronze/raw/feriados"
os.makedirs(pasta, exist_ok=True)                        # a pasta nova precisa existir

agora = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")     # ex.: 2026-10-20_19-40-00 (horário UTC)
with open(f"{pasta}/feriados_{agora}.json", "w") as arquivo:
    json.dump(feriados, arquivo, ensure_ascii=False)

sorted(os.listdir(pasta))                                # um arquivo por execução

# COMMAND ----------

# MAGIC %md
# MAGIC ## Passo 3 · Carregar: o raw vira a bronze
# MAGIC
# MAGIC O mesmo `read_files` da ingestão em lote, lendo **todos** os arquivos da pasta. As colunas `arquivo` e
# MAGIC `coletado_em` contam de onde e de quando veio cada linha. O dia da semana é calculado a partir da data.

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE OR REPLACE TABLE lakehouse_vertice.bronze.feriados
# MAGIC COMMENT 'Feriados nacionais de 2026. Uma captura por execução do job.'
# MAGIC AS SELECT date AS data, name AS feriado, type AS tipo,
# MAGIC           element_at(array('domingo', 'segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira',
# MAGIC                            'sexta-feira', 'sábado'), dayofweek(to_date(date))) AS dia_da_semana,
# MAGIC           _metadata.file_name              AS arquivo,
# MAGIC           _metadata.file_modification_time AS coletado_em
# MAGIC FROM read_files('/Volumes/lakehouse_vertice/bronze/raw/feriados/', format => 'json', multiLine => true)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Passo 4 · Conferir

# COMMAND ----------

# MAGIC %sql
# MAGIC -- uma linha por captura: 14 feriados em cada uma
# MAGIC SELECT arquivo, coletado_em, COUNT(*) AS feriados
# MAGIC FROM lakehouse_vertice.bronze.feriados
# MAGIC GROUP BY arquivo, coletado_em
# MAGIC ORDER BY coletado_em DESC

# COMMAND ----------

# MAGIC %sql
# MAGIC -- a resposta para o negócio, na captura mais recente:
# MAGIC -- 02/11 (segunda), 15/11 (domingo) e 20/11 (sexta): 2 dias úteis a menos em novembro
# MAGIC SELECT data, feriado, dia_da_semana
# MAGIC FROM lakehouse_vertice.bronze.feriados
# MAGIC WHERE arquivo = (SELECT MAX(arquivo) FROM lakehouse_vertice.bronze.feriados)
# MAGIC   AND data BETWEEN '2026-11-01' AND '2026-11-30'
# MAGIC ORDER BY data
