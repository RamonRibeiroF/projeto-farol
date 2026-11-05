#!/usr/bin/env python3
"""Gera o dashboard AI/BI de portfólio (sobre a BRONZE) como JSON versionado.

Uso:
    python3 dashboards/bronze/gerar_dashboard.py            # só escreve o JSON
    python3 dashboards/bronze/gerar_dashboard.py --deploy --profile SEU-PERFIL

O JSON é o dashboard: nada aqui foi montado clicando. As queries usam o nome
da tabela sem catálogo; catálogo e schema entram no deploy.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import subprocess

AQUI = pathlib.Path(__file__).resolve().parent
SAIDA = AQUI / "portfolio-bronze.lvdash.json"
NOME = "Projeto Farol · Portfólio (bronze)"

SQL_PROJETOS = """-- Tudo na bronze é texto e cada ferramenta tem seu formato: este painel lê o
-- rascunho_tarefas (parte 5 de analises/01-sql-na-bronze.sql), que empilha Excel, ClickUp e MS Project à mão.
-- É o imposto que a camada silver vai eliminar.
WITH v AS (
  SELECT projeto_id, max(ferramenta) AS ferramenta,
         SUM(horas) AS horas_totais,
         SUM(horas * pct_concluido / 100) AS horas_agregadas,
         SUM(horas * GREATEST(0, LEAST(1, datediff(DATE'2026-10-16', inicio_baseline)
                  / datediff(fim_baseline, inicio_baseline)))) AS horas_planejadas
  FROM rascunho_tarefas
  GROUP BY projeto_id
),
c AS (SELECT projeto_id, SUM(CAST(replace(valor, ',', '.') AS DECIMAL(18,2))) AS ac FROM custos GROUP BY projeto_id),
f AS (SELECT projeto_id, lower(farol) AS farol FROM status_semanal WHERE data_status = '2026-10-16'),
o AS (
  SELECT p.projeto_id, concat(p.projeto_id, ' · ', p.nome_projeto) AS projeto, p.cliente, p.segmento,
         v.ferramenta, f.farol,
         CAST(p.valor_contrato AS DECIMAL(18,2)) AS valor_contrato,
         CAST(p.orcamento_custo AS DECIMAL(18,2)) AS orcamento,
         datediff(CAST(p.data_fim_baseline AS DATE),
                  coalesce(try_to_date(p.data_inicio, 'yyyy-MM-dd'), try_to_date(p.data_inicio, 'dd/MM/yyyy'))) AS duracao,
         v.horas_agregadas / v.horas_planejadas AS spi,
         CAST(p.orcamento_custo AS DECIMAL(18,2)) * v.horas_agregadas / v.horas_totais / c.ac AS cpi
  FROM projetos p JOIN v USING (projeto_id) JOIN c USING (projeto_id) LEFT JOIN f USING (projeto_id)
  WHERE p.status = 'em_andamento'
)
SELECT projeto_id, projeto, cliente, segmento, ferramenta, farol, valor_contrato, orcamento,
       ROUND(spi, 2) AS spi,
       ROUND(cpi, 2) AS cpi,
       CASE WHEN LEAST(spi, cpi) < 0.8 THEN 'crítico'
            WHEN LEAST(spi, cpi) < 0.9 THEN 'atenção' ELSE 'ok' END AS situacao,
       CASE WHEN LEAST(spi, cpi) < 0.8 THEN 1 ELSE 0 END AS critico,
       CASE WHEN LEAST(spi, cpi) < 0.9 THEN 1 ELSE 0 END AS em_risco,
       CASE WHEN farol = 'verde' AND spi < 0.9 THEN 1 ELSE 0 END AS melancia,
       GREATEST(0, orcamento / cpi - orcamento) AS estouro_previsto,
       (valor_contrato - orcamento / cpi) / valor_contrato AS margem_projetada,
       ROUND(duracao / spi - duracao) AS atraso_projetado_dias
FROM o
ORDER BY LEAST(spi, cpi)"""

SQL_CUSTOS = """SELECT date_trunc('MONTH', CAST(data AS DATE)) AS mes,
       categoria,
       CAST(replace(valor, ',', '.') AS DECIMAL(18,2)) AS valor
FROM custos"""


def ds(nome: str, titulo: str, sql: str) -> dict:
    linhas = sql.split("\n")
    return {"name": nome, "displayName": titulo, "queryLines": [l + "\n" for l in linhas]}


def texto(nome: str, md: str, pos: tuple[int, int, int, int]) -> dict:
    x, y, w, h = pos
    return {"widget": {"name": nome, "textbox_spec": md}, "position": {"x": x, "y": y, "width": w, "height": h}}


def widget(nome, dataset, campos, spec, pos, desagregado=False):
    x, y, w, h = pos
    return {"widget": {"name": nome,
                       "queries": [{"name": "main_query", "query": {
                           "datasetName": dataset,
                           "fields": [{"name": n, "expression": e} for n, e in campos],
                           "disaggregated": desagregado}}],
                       "spec": spec},
            "position": {"x": x, "y": y, "width": w, "height": h}}


BRL = {"type": "number-currency", "currencyCode": "BRL", "abbreviation": "compact",
       "decimalPlaces": {"type": "max", "places": 1}}
BRL_KPI = {"type": "number-currency", "currencyCode": "BRL", "abbreviation": "compact",
           "decimalPlaces": {"type": "max", "places": 0}}


def contador(nome, campo, expr, titulo, fmt, pos):
    return widget(nome, "ds_projetos", [(campo, expr)],
                  {"version": 2, "widgetType": "counter",
                   "encodings": {"value": {"fieldName": campo, "displayName": titulo, "format": fmt}},
                   "frame": {"showTitle": True, "title": titulo}}, pos)


def montar() -> dict:
    cor_situacao = {"type": "categorical", "mappings": [
        {"value": "crítico", "color": "#FF5F46"}, {"value": "atenção", "color": "#F6C344"},
        {"value": "ok", "color": "#22C2F4"}]}
    layout = [
        texto("titulo", "# Projeto Farol · Torre de Controle da Vértice Tecnologia\n\n"
              "**Quais projetos estão mais atrasados e quanto isso custa?** Primeira versão do painel: "
              "lê a camada **bronze**, com as tarefas do Excel, do ClickUp e do MS Project empilhadas à mão. "
              "Repare no SQL dos datasets: `CAST`, `replace` e `try_to_date` em toda coluna. Hoje do dataset: 16/10/2026.",
              (0, 0, 12, 3)),
        contador("kpi-carteira", "sum(valor_contrato)", "SUM(`valor_contrato`)", "Carteira em andamento", BRL_KPI, (0, 3, 3, 4)),
        contador("kpi-risco", "sum(em_risco)", "SUM(`em_risco`)", "Projetos com SPI ou CPI < 0,9",
                 {"type": "number-plain"}, (3, 3, 3, 4)),
        contador("kpi-criticos", "sum(critico)", "SUM(`critico`)", "Projetos críticos (< 0,8)",
                 {"type": "number-plain"}, (6, 3, 3, 4)),
        contador("kpi-melancia", "sum(melancia)", "SUM(`melancia`)", "Farol verde com SPI < 0,9",
                 {"type": "number-plain"}, (9, 3, 3, 4)),
        texto("secao-risco", "## Onde está o problema\n\nSPI < 1 é atraso; CPI < 1 é cada real gastando mais do que entrega. "
              "Clique numa barra para filtrar a tabela.", (0, 7, 12, 2)),
        widget("spi-projeto", "ds_projetos", [("projeto", "`projeto`"), ("min(spi)", "MIN(`spi`)"), ("situacao", "`situacao`")],
               {"version": 3, "widgetType": "bar",
                "encodings": {"y": {"fieldName": "projeto", "scale": {"type": "categorical",
                                    "sort": {"by": "x"}}, "displayName": "Projeto"},
                              "x": {"fieldName": "min(spi)", "scale": {"type": "quantitative"}, "displayName": "SPI"},
                              "color": {"fieldName": "situacao", "scale": cor_situacao, "displayName": "Situação"}},
                "frame": {"showTitle": True, "title": "SPI por projeto (do mais atrasado ao mais adiantado)"}}, (0, 9, 7, 9)),
        widget("situacao-ferramenta", "ds_projetos",
               [("ferramenta", "`ferramenta`"), ("situacao", "`situacao`"), ("count(projeto_id)", "COUNT(`projeto_id`)")],
               {"version": 3, "widgetType": "bar",
                "encodings": {"x": {"fieldName": "ferramenta", "scale": {"type": "categorical"}, "displayName": "Ferramenta"},
                              "y": {"fieldName": "count(projeto_id)", "scale": {"type": "quantitative"}, "displayName": "Projetos"},
                              "color": {"fieldName": "situacao", "scale": cor_situacao, "displayName": "Situação"}},
                "frame": {"showTitle": True, "title": "Projetos em andamento por ferramenta e situação"}}, (7, 9, 5, 9)),
        texto("secao-custo", "## Para onde vai o dinheiro\n\nCusto real por mês e categoria. Sem trocar a vírgula "
              "decimal por ponto, 671 lançamentos somem do total em silêncio.", (0, 18, 12, 2)),
        widget("custo-mes", "ds_custos", [("monthly(mes)", "DATE_TRUNC(\"MONTH\", `mes`)"), ("categoria", "`categoria`"),
                                         ("sum(valor)", "SUM(`valor`)")],
               {"version": 3, "widgetType": "bar",
                "encodings": {"x": {"fieldName": "monthly(mes)", "scale": {"type": "temporal"}, "displayName": "Mês"},
                              "y": {"fieldName": "sum(valor)", "scale": {"type": "quantitative"},
                                    "displayName": "Custo real", "format": BRL},
                              "color": {"fieldName": "categoria", "scale": {"type": "categorical"},
                                        "displayName": "Categoria"}},
                "frame": {"showTitle": True, "title": "Custo real por mês"}}, (0, 20, 12, 6)),
        texto("secao-tabela", "## Todos os projetos em andamento\n\nOrdenados do pior para o melhor. "
              "Compare o **farol do gerente** com a situação calculada: o manual diz que verde é só com SPI ≥ 0,95.",
              (0, 26, 12, 2)),
        widget("tabela-projetos", "ds_projetos",
               [(c, f"`{c}`") for c in ("projeto", "cliente", "ferramenta", "spi", "cpi", "situacao", "farol",
                                         "estouro_previsto", "margem_projetada", "atraso_projetado_dias")],
               {"version": 2, "widgetType": "table",
                "encodings": {"columns": [
                    {"fieldName": "projeto", "displayName": "Projeto"},
                    {"fieldName": "cliente", "displayName": "Cliente"},
                    {"fieldName": "ferramenta", "displayName": "Ferramenta"},
                    {"fieldName": "spi", "displayName": "SPI"},
                    {"fieldName": "cpi", "displayName": "CPI"},
                    {"fieldName": "situacao", "displayName": "Situação"},
                    {"fieldName": "farol", "displayName": "Farol do gerente"},
                    {"fieldName": "estouro_previsto", "displayName": "Estouro previsto",
                     "format": {"type": "number-currency", "currencyCode": "BRL",
                                "decimalPlaces": {"type": "max", "places": 0}}},
                    {"fieldName": "margem_projetada", "displayName": "Margem projetada",
                     "format": {"type": "number-percent", "decimalPlaces": {"type": "max", "places": 1}}},
                    {"fieldName": "atraso_projetado_dias", "displayName": "Atraso projetado (dias)"}]},
                "frame": {"showTitle": True, "title": "Projetos em andamento"}}, (0, 28, 12, 9), desagregado=True),
    ]
    return {
        "datasets": [ds("ds_projetos", "Projetos em andamento (bronze)", SQL_PROJETOS),
                     ds("ds_custos", "Custos (bronze)", SQL_CUSTOS)],
        "pages": [{"name": "portfolio", "displayName": "Portfólio (bronze)", "pageType": "PAGE_TYPE_CANVAS",
                   "layoutVersion": "GRID_V1", "layout": layout}],
        "uiSettings": {"theme": {
            "canvasBackgroundColor": {"light": "#F5F6FC", "dark": "#14141A"},
            "widgetBackgroundColor": {"light": "#FFFFFF", "dark": "#1E1E24"},
            "fontColor": {"light": "#14141A", "dark": "#F5F6FC"},
            "selectionColor": {"light": "#0059DB", "dark": "#22C2F4"},
            "visualizationColors": ["#0059DB", "#22C2F4", "#F6C344", "#FF8A4C", "#9B6BDB", "#3ECF8E", "#6E7180"],
            "widgetHeaderAlignment": "LEFT", "widgetCornerRadius": 12}},
    }


def cli(args: list[str], profile: str) -> dict:
    r = subprocess.run(["databricks", *args, "--profile", profile, "-o", "json"], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(r.stderr)
    return json.loads(r.stdout or "{}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--deploy", action="store_true")
    ap.add_argument("--profile")
    ap.add_argument("--catalog", default="lakehouse_vertice")
    a = ap.parse_args()
    painel = montar()
    SAIDA.write_text(json.dumps(painel, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"ok: {SAIDA.name}")
    if not a.deploy:
        return
    if not a.profile:
        raise SystemExit("passe --profile")
    eu = cli(["current-user", "me"], a.profile)["userName"]
    wh = cli(["warehouses", "list"], a.profile)[0]["id"]
    pasta = f"/Workspace/Users/{eu}/projeto-farol"
    subprocess.run(["databricks", "workspace", "mkdirs", pasta, "--profile", a.profile], check=True)
    existentes = [d for d in cli(["lakeview", "list"], a.profile) if d.get("display_name") == NOME]
    base = ["--dataset-catalog", a.catalog, "--dataset-schema", "bronze",
            "--serialized-dashboard", json.dumps(painel, ensure_ascii=False)]
    if existentes:
        did = existentes[0]["dashboard_id"]
        cli(["lakeview", "update", did, *base], a.profile)
    else:
        did = cli(["lakeview", "create", "--display-name", NOME, "--warehouse-id", wh, *base,
                   "--json", json.dumps({"parent_path": pasta})], a.profile)["dashboard_id"]
    cli(["lakeview", "publish", did, "--warehouse-id", wh], a.profile)
    host = subprocess.run(["databricks", "auth", "env", "--profile", a.profile, "-o", "json"],
                          capture_output=True, text=True).stdout
    host = json.loads(host)["env"]["DATABRICKS_HOST"].rstrip("/")
    print(f"publicado: {host}/dashboardsv3/{did}/published")


if __name__ == "__main__":
    main()
