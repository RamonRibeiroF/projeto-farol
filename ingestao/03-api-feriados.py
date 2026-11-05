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
# MAGIC **Atenção ao ambiente.** O Databricks Free Edition só libera a saída para a internet para uma lista de sites
# MAGIC confiáveis, e a BrasilAPI não está nela (o erro é `NameResolutionError`). Por isso o Passo 1 tenta a API e,
# MAGIC se a rede bloquear, calcula os mesmos feriados em Python. A origem de cada captura fica registrada na coluna
# MAGIC `fonte` da tabela.
# MAGIC
# MAGIC ## Passo 1 · Extrair: pedir os feriados à API

# COMMAND ----------

from datetime import date, timedelta

import requests                # conversa com a API (HTTP)

ANO = 2026
URL = f"https://brasilapi.com.br/api/feriados/v1/{ANO}"


def pascoa(ano: int) -> date:
    """Domingo de Páscoa (algoritmo de Meeus/Jones/Butcher)."""
    a, b, c = ano % 19, ano // 100, ano % 100
    d, e = b // 4, b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = c // 4, c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    mes = (h + l - 7 * m + 114) // 31
    dia = (h + l - 7 * m + 114) % 31 + 1
    return date(ano, mes, dia)


def feriados_nacionais(ano: int) -> list[dict]:
    """Os feriados nacionais no mesmo formato da BrasilAPI: date, name, type."""
    p = pascoa(ano)
    fixos = [
        (date(ano, 1, 1), "Confraternização mundial"),
        (date(ano, 4, 21), "Tiradentes"),
        (date(ano, 5, 1), "Dia do trabalho"),
        (date(ano, 9, 7), "Independência do Brasil"),
        (date(ano, 10, 12), "Nossa Senhora Aparecida"),
        (date(ano, 11, 2), "Finados"),
        (date(ano, 11, 15), "Proclamação da República"),
        (date(ano, 11, 20), "Consciência Negra"),
        (date(ano, 12, 25), "Natal"),
    ]
    moveis = [
        (p - timedelta(days=48), "Carnaval"),
        (p - timedelta(days=47), "Carnaval"),
        (p - timedelta(days=2), "Sexta-feira Santa"),
        (p, "Páscoa"),
        (p + timedelta(days=60), "Corpus Christi"),
    ]
    todos = sorted(fixos + moveis)
    return [{"date": d.isoformat(), "name": n, "type": "national"} for d, n in todos]


try:
    resposta = requests.get(URL, timeout=30)
    resposta.raise_for_status()         # se a API responder com erro, cai no calculado em vez de seguir com nada
    feriados, fonte = resposta.json(), "api"
except requests.exceptions.RequestException as erro:
    print(f"API inacessível neste ambiente ({type(erro).__name__}). Usando o cálculo local.")
    feriados, fonte = feriados_nacionais(ANO), "calculado"

print(len(feriados), "feriados · fonte:", fonte)
feriados[:3]

# COMMAND ----------

# MAGIC %md
# MAGIC ## Passo 2 · Pousar: o JSON numa pasta nova do raw
# MAGIC
# MAGIC Cada execução grava um arquivo **novo**, com a data e a hora no nome. O raw guarda o histórico de tudo o que
# MAGIC chegou. O fim do nome do arquivo (`_api` ou `_calculado`) diz de onde o dado veio.

# COMMAND ----------

import json, os
from datetime import datetime

pasta = "/Volumes/lakehouse_vertice/bronze/raw/feriados"
os.makedirs(pasta, exist_ok=True)                        # a pasta nova precisa existir

agora = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")     # ex.: 2026-10-20_19-40-00 (horário UTC)
with open(f"{pasta}/feriados_{agora}_{fonte}.json", "w") as arquivo:
    json.dump(feriados, arquivo, ensure_ascii=False)

sorted(os.listdir(pasta))                                # um arquivo por execução

# COMMAND ----------

# MAGIC %md
# MAGIC ## Passo 3 · Carregar: o raw vira a bronze
# MAGIC
# MAGIC O mesmo `read_files` da ingestão em lote, lendo **todos** os arquivos da pasta. As colunas `arquivo`,
# MAGIC `coletado_em` e `fonte` contam de onde e de quando veio cada linha. O dia da semana é calculado a partir da
# MAGIC data, para a tabela ficar igual venha o arquivo da API ou do cálculo.

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE OR REPLACE TABLE lakehouse_vertice.bronze.feriados
# MAGIC COMMENT 'Feriados nacionais de 2026. Uma captura por execução; a coluna fonte diz se veio da BrasilAPI ou do cálculo local.'
# MAGIC AS SELECT date AS data, name AS feriado, type AS tipo,
# MAGIC           element_at(array('domingo', 'segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira',
# MAGIC                            'sexta-feira', 'sábado'), dayofweek(to_date(date))) AS dia_da_semana,
# MAGIC           _metadata.file_name              AS arquivo,
# MAGIC           _metadata.file_modification_time AS coletado_em,
# MAGIC           CASE WHEN endswith(_metadata.file_name, '_calculado.json') THEN 'calculado' ELSE 'api' END AS fonte
# MAGIC FROM read_files('/Volumes/lakehouse_vertice/bronze/raw/feriados/', format => 'json', multiLine => true)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Passo 4 · Conferir

# COMMAND ----------

# MAGIC %sql
# MAGIC -- uma linha por captura: 14 feriados em cada uma
# MAGIC SELECT arquivo, fonte, coletado_em, COUNT(*) AS feriados
# MAGIC FROM lakehouse_vertice.bronze.feriados
# MAGIC GROUP BY arquivo, fonte, coletado_em
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
