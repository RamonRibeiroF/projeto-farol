#!/usr/bin/env python3
"""Gera o dashboard AI/BI de portfólio (sobre a GOLD) como JSON versionado.

Uso:
    python3 dashboards/gold/gerar_dashboard.py      # escreve portfolio.lvdash.json

O deploy é pelo bundle (resources/dashboard.dashboard.yml): `databricks bundle deploy --profile SEU-PERFIL`.
As queries da gold usam o nome puro da tabela; catálogo e schema (gold) vêm do bundle.
A silver.entregas_fornecedor vai com o nome completo. "Hoje" = 2026-10-16.
"""
from __future__ import annotations

import json
import pathlib

AQUI = pathlib.Path(__file__).resolve().parent
SAIDA = AQUI / "portfolio.lvdash.json"

# ---------------------------------------------------------------- datasets

SQL_KPIS = """-- KPIs da carteira em andamento. Razão é SUM/SUM, nunca média de razão.
SELECT SUM(valor_contrato)                                        AS carteira,
       ROUND(SUM(ev) / SUM(pv), 2)                                AS spi,
       ROUND(SUM(ev) / SUM(ac), 2)                                AS cpi,
       SUM(estouro_previsto)                                      AS estouro_previsto,
       SUM(CASE WHEN situacao IN ('atenção', 'crítico') THEN 1 ELSE 0 END) AS em_risco,
       SUM(CASE WHEN situacao = 'crítico' THEN 1 ELSE 0 END)      AS criticos,
       SUM(CASE WHEN melancia THEN 1 ELSE 0 END)                  AS melancias
FROM projeto_situacao_atual
WHERE status = 'em_andamento'"""

SQL_PROJETOS = """-- Um projeto em andamento por linha, do pior (menor entre SPI e CPI) para o melhor.
SELECT projeto_id,
       projeto,
       cliente,
       gerente_projeto,
       spi,
       cpi,
       situacao,
       estouro_previsto,
       margem_projetada,
       atraso_projetado_dias,
       farol_do_gerente,
       farol_calculado,
       CASE WHEN melancia THEN 'sim' ELSE '' END AS melancia
FROM projeto_situacao_atual
WHERE status = 'em_andamento'
ORDER BY least(spi, cpi)"""

SQL_TENDENCIA = """-- SPI e CPI semanais da carteira (SUM/SUM por semana), em formato longo para a linha colorir por indicador.
WITH semana AS (
    SELECT semana,
           SUM(ev) / SUM(pv) AS spi,
           SUM(ev) / SUM(ac) AS cpi
    FROM fato_projeto_semana
    WHERE semana >= DATE'2025-03-07'
    GROUP BY semana
)
SELECT semana, 'SPI' AS indicador, ROUND(spi, 3) AS valor FROM semana
UNION ALL
SELECT semana, 'CPI' AS indicador, ROUND(cpi, 3) AS valor FROM semana
ORDER BY semana, indicador"""

SQL_TOP_OCIOSOS = """-- As 15 pessoas com maior custo de hora parada nas últimas 12 semanas (até 2026-10-16).
SELECT nome,
       papel,
       SUM(horas_ociosas) AS horas_ociosas,
       SUM(custo_ocioso)  AS custo_ocioso
FROM utilizacao_pessoa_semana
WHERE semana > DATE'2026-07-24'
GROUP BY nome, papel
ORDER BY custo_ocioso DESC
LIMIT 15"""

SQL_UTILIZACAO = """-- Utilização por pessoa e projeto nas últimas 12 semanas, da mais parada à mais ocupada.
SELECT nome,
       papel,
       senioridade,
       projeto_id,
       SUM(horas_disponiveis)                                  AS horas_disponiveis,
       SUM(horas_apontadas)                                    AS horas_apontadas,
       SUM(horas_ociosas)                                      AS horas_ociosas,
       ROUND(SUM(horas_apontadas) / SUM(horas_disponiveis), 4) AS utilizacao,
       SUM(custo_ocioso)                                       AS custo_ocioso
FROM utilizacao_pessoa_semana
WHERE semana > DATE'2026-07-24'
GROUP BY nome, papel, senioridade, projeto_id
ORDER BY utilizacao, custo_ocioso DESC"""

SQL_BLOQUEIOS = """-- Causas de bloqueio lidas do texto do status, desde 2026-07-18.
SELECT projeto_id,
       causa_bloqueio,
       COUNT(*) AS status
FROM status_estruturado
WHERE data_status >= DATE'2026-07-18'
  AND causa_bloqueio NOT IN ('sem_bloqueio', 'nao_reportado')
GROUP BY projeto_id, causa_bloqueio
ORDER BY projeto_id"""

SQL_FORNECEDORES = """-- Desempenho por fornecedor (já normalizado). Prazo real ÷ prometido é SUM/SUM das entregas feitas.
SELECT fornecedor,
       COUNT(DISTINCT fornecedor_como_veio)                                      AS grafias,
       COUNT(*)                                                                  AS entregas,
       ROUND(SUM(CASE WHEN NOT em_aberto THEN prazo_real_dias END)
             / SUM(CASE WHEN NOT em_aberto THEN prazo_prometido_dias END), 2)    AS prazo_real_sobre_prometido,
       ROUND(SUM(CASE WHEN NOT em_aberto AND dias_de_atraso_na_entrega = 0 THEN 1 ELSE 0 END)
             / SUM(CASE WHEN NOT em_aberto THEN 1 ELSE 0 END), 4)                AS pct_no_prazo,
       SUM(CASE WHEN em_atraso THEN 1 ELSE 0 END)                                AS em_atraso_hoje
FROM lakehouse_vertice.silver.entregas_fornecedor
GROUP BY fornecedor
ORDER BY prazo_real_sobre_prometido DESC"""

SQL_ATRASOS = """-- Entregas em aberto com a data prometida já vencida em 2026-10-16.
SELECT entrega_id,
       projeto_id,
       fornecedor,
       fornecedor_como_veio,
       item,
       valor,
       data_prometida,
       datediff(DATE'2026-10-16', data_prometida) AS dias_vencida
FROM lakehouse_vertice.silver.entregas_fornecedor
WHERE em_atraso
ORDER BY dias_vencida DESC"""

DATASETS = [
    ("ds_kpis", "KPIs da carteira", SQL_KPIS),
    ("ds_projetos", "Projetos em andamento", SQL_PROJETOS),
    ("ds_tendencia", "SPI e CPI semanais", SQL_TENDENCIA),
    ("ds_top_ociosos", "Top 15 hora parada", SQL_TOP_OCIOSOS),
    ("ds_utilizacao", "Utilização por pessoa e projeto", SQL_UTILIZACAO),
    ("ds_bloqueios", "Causas de bloqueio", SQL_BLOQUEIOS),
    ("ds_fornecedores", "Fornecedores", SQL_FORNECEDORES),
    ("ds_atrasos", "Entregas em atraso", SQL_ATRASOS),
]

# ---------------------------------------------------------------- helpers (mesmo formato da bronze)


def ds(nome: str, titulo: str, sql: str) -> dict:
    return {"name": nome, "displayName": titulo, "queryLines": [l + "\n" for l in sql.split("\n")]}


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
BRL_INTEIRO = {"type": "number-currency", "currencyCode": "BRL", "decimalPlaces": {"type": "max", "places": 0}}
PCT = {"type": "number-percent", "decimalPlaces": {"type": "max", "places": 1}}
PLANO = {"type": "number-plain"}
DECIMAL2 = {"type": "number", "decimalPlaces": {"type": "exact", "places": 2}}

COR_SITUACAO = {"type": "categorical", "mappings": [
    {"value": "crítico", "color": "#FF5F46"}, {"value": "atenção", "color": "#F6C344"},
    {"value": "ok", "color": "#22C2F4"}]}


def kpi(nome, campo, titulo, fmt, pos):
    # ds_kpis tem uma linha só: desagregado, sem agregação no widget
    return widget(nome, "ds_kpis", [(campo, f"`{campo}`")],
                  {"version": 2, "widgetType": "counter",
                   "encodings": {"value": {"fieldName": campo, "displayName": titulo, "format": fmt}},
                   "frame": {"showTitle": True, "title": titulo}}, pos, desagregado=True)


def tabela(nome, dataset, colunas, titulo, pos):
    """colunas: (campo, rótulo, formato ou None)"""
    cols = []
    for campo, rotulo, fmt in colunas:
        c = {"fieldName": campo, "displayName": rotulo}
        if fmt:
            c["format"] = fmt
        cols.append(c)
    return widget(nome, dataset, [(c, f"`{c}`") for c, _, _ in colunas],
                  {"version": 2, "widgetType": "table", "encodings": {"columns": cols},
                   "frame": {"showTitle": True, "title": titulo}}, pos, desagregado=True)


def pagina(nome, titulo, layout):
    return {"name": nome, "displayName": titulo, "pageType": "PAGE_TYPE_CANVAS",
            "layoutVersion": "GRID_V1", "layout": layout}

# ---------------------------------------------------------------- páginas


def pagina_portfolio() -> dict:
    return pagina("portfolio", "Portfólio", [
        texto("titulo-portfolio", "# Quais projetos estão atrasando e quanto isso vai custar?\n\n"
              "Carteira em andamento em 16/10/2026, lida da camada **gold**. SPI < 1 é atraso; CPI < 1 é cada real "
              "entregando menos do que custa. Crítico: SPI ou CPI < 0,8; atenção: < 0,9.", (0, 0, 12, 2)),
        kpi("kpi-carteira", "carteira", "Carteira em andamento", BRL, (0, 2, 3, 3)),
        kpi("kpi-spi", "spi", "SPI da carteira", DECIMAL2, (3, 2, 3, 3)),
        kpi("kpi-cpi", "cpi", "CPI da carteira", DECIMAL2, (6, 2, 3, 3)),
        kpi("kpi-estouro", "estouro_previsto", "Estouro previsto", BRL, (9, 2, 3, 3)),
        kpi("kpi-risco", "em_risco", "Projetos em risco (atenção + crítico)", PLANO, (0, 5, 4, 3)),
        kpi("kpi-criticos", "criticos", "Projetos críticos", PLANO, (4, 5, 4, 3)),
        kpi("kpi-melancias", "melancias", "Melancias (verde por fora, SPI < 0,9)", PLANO, (8, 5, 4, 3)),
        widget("estouro-projeto", "ds_projetos",
               [("projeto", "`projeto`"), ("sum(estouro_previsto)", "SUM(`estouro_previsto`)"),
                ("situacao", "`situacao`")],
               {"version": 3, "widgetType": "bar",
                "encodings": {"y": {"fieldName": "projeto", "scale": {"type": "categorical", "sort": {"by": "x-reversed"}},
                                    "displayName": "Projeto"},
                              "x": {"fieldName": "sum(estouro_previsto)", "scale": {"type": "quantitative"},
                                    "displayName": "Estouro previsto", "format": BRL},
                              "color": {"fieldName": "situacao", "scale": COR_SITUACAO, "displayName": "Situação"}},
                "frame": {"showTitle": True, "title": "Estouro previsto por projeto"}}, (0, 8, 6, 10)),
        widget("spi-cpi", "ds_projetos",
               [("spi", "`spi`"), ("cpi", "`cpi`"), ("situacao", "`situacao`"), ("projeto", "`projeto`")],
               {"version": 3, "widgetType": "scatter",
                "encodings": {"x": {"fieldName": "spi", "scale": {"type": "quantitative"}, "displayName": "SPI"},
                              "y": {"fieldName": "cpi", "scale": {"type": "quantitative"}, "displayName": "CPI"},
                              "color": {"fieldName": "situacao", "scale": COR_SITUACAO, "displayName": "Situação"},
                              "tooltip": {"fieldName": "projeto", "displayName": "Projeto"}},
                "frame": {"showTitle": True, "title": "SPI × CPI (um ponto por projeto)"}}, (6, 8, 6, 10),
               desagregado=True),
        widget("tendencia", "ds_tendencia",
               [("semana", "`semana`"), ("indicador", "`indicador`"), ("valor", "`valor`")],
               {"version": 3, "widgetType": "line",
                "encodings": {"x": {"fieldName": "semana", "scale": {"type": "temporal"}, "displayName": "Semana"},
                              "y": {"fieldName": "valor", "scale": {"type": "quantitative"}, "displayName": "Índice"},
                              "color": {"fieldName": "indicador", "scale": {"type": "categorical", "mappings": [
                                  {"value": "SPI", "color": "#0059DB"}, {"value": "CPI", "color": "#22C2F4"}]},
                                  "displayName": "Indicador"}},
                "frame": {"showTitle": True, "title": "SPI e CPI semanais da carteira"}}, (0, 18, 12, 6),
               desagregado=True),
        tabela("tabela-projetos", "ds_projetos", [
            ("projeto", "Projeto", None), ("cliente", "Cliente", None), ("gerente_projeto", "Gerente", None),
            ("spi", "SPI", DECIMAL2), ("cpi", "CPI", DECIMAL2), ("situacao", "Situação", None),
            ("farol_do_gerente", "Farol do gerente", None), ("farol_calculado", "Farol pelo número", None),
            ("melancia", "Melancia", None), ("estouro_previsto", "Estouro previsto", BRL_INTEIRO),
            ("margem_projetada", "Margem projetada", PCT), ("atraso_projetado_dias", "Atraso projetado (dias)", None)],
            "Projetos em andamento (do pior para o melhor)", (0, 24, 12, 10)),
    ])


def pagina_pessoas() -> dict:
    return pagina("pessoas", "Pessoas", [
        texto("titulo-pessoas", "# Quem está parado, quanto isso custa e o que está travando?\n\n"
              "Últimas 12 semanas (até 16/10/2026). Hora parada = disponível − apontada, a preço de custo/hora. "
              "As causas de bloqueio são lidas do texto do status semanal.", (0, 0, 12, 2)),
        widget("top-ociosos", "ds_top_ociosos",
               [("nome", "`nome`"), ("sum(custo_ocioso)", "SUM(`custo_ocioso`)")],
               {"version": 3, "widgetType": "bar",
                "encodings": {"y": {"fieldName": "nome", "scale": {"type": "categorical", "sort": {"by": "x-reversed"}},
                                    "displayName": "Pessoa"},
                              "x": {"fieldName": "sum(custo_ocioso)", "scale": {"type": "quantitative"},
                                    "displayName": "Custo da hora parada", "format": BRL}},
                "frame": {"showTitle": True, "title": "Top 15 pessoas por custo da hora parada"}}, (0, 2, 6, 9)),
        widget("bloqueios", "ds_bloqueios",
               [("projeto_id", "`projeto_id`"), ("causa_bloqueio", "`causa_bloqueio`"), ("sum(status)", "SUM(`status`)")],
               {"version": 3, "widgetType": "bar",
                "encodings": {"y": {"fieldName": "projeto_id", "scale": {"type": "categorical"}, "displayName": "Projeto"},
                              "x": {"fieldName": "sum(status)", "scale": {"type": "quantitative"},
                                    "displayName": "Semanas com o bloqueio"},
                              "color": {"fieldName": "causa_bloqueio", "scale": {"type": "categorical"},
                                        "displayName": "Causa"}},
                "frame": {"showTitle": True, "title": "Causas de bloqueio por projeto (desde 18/07/2026)"}},
               (6, 2, 6, 9)),
        tabela("tabela-utilizacao", "ds_utilizacao", [
            ("nome", "Pessoa", None), ("papel", "Papel", None), ("senioridade", "Senioridade", None),
            ("projeto_id", "Projeto", None), ("horas_disponiveis", "Horas disponíveis", None),
            ("horas_apontadas", "Horas apontadas", None), ("horas_ociosas", "Horas paradas", None),
            ("utilizacao", "Utilização", PCT), ("custo_ocioso", "Custo da hora parada", BRL_INTEIRO)],
            "Utilização por pessoa e projeto (da mais parada à mais ocupada)", (0, 11, 12, 10)),
    ])


def pagina_fornecedores() -> dict:
    return pagina("fornecedores", "Fornecedores", [
        texto("titulo-fornecedores", "# Qual consultoria atrasa e o que está vencido hoje?\n\n"
              "Prazo real ÷ prometido acima de 1 é atraso. Grafias: de quantos jeitos o nome aparece no cadastro "
              "antes da normalização.", (0, 0, 12, 2)),
        tabela("tabela-fornecedores", "ds_fornecedores", [
            ("fornecedor", "Fornecedor", None), ("grafias", "Grafias no cadastro", None),
            ("entregas", "Entregas", None), ("prazo_real_sobre_prometido", "Prazo real ÷ prometido", DECIMAL2),
            ("pct_no_prazo", "% no prazo", PCT), ("em_atraso_hoje", "Em atraso hoje", None)],
            "Desempenho por fornecedor", (0, 2, 12, 6)),
        tabela("tabela-atrasos", "ds_atrasos", [
            ("entrega_id", "Entrega", None), ("projeto_id", "Projeto", None), ("fornecedor", "Fornecedor", None),
            ("fornecedor_como_veio", "Como veio no cadastro", None), ("item", "Item", None),
            ("valor", "Valor", BRL_INTEIRO), ("data_prometida", "Prometida para", None),
            ("dias_vencida", "Dias vencida", None)],
            "Entregas em atraso em 16/10/2026", (0, 8, 12, 6)),
    ])


def montar() -> dict:
    return {
        "datasets": [ds(n, t, s) for n, t, s in DATASETS],
        "pages": [pagina_portfolio(), pagina_pessoas(), pagina_fornecedores()],
        "uiSettings": {"theme": {
            "canvasBackgroundColor": {"light": "#F5F6FC", "dark": "#14141A"},
            "widgetBackgroundColor": {"light": "#FFFFFF", "dark": "#1E1E24"},
            "fontColor": {"light": "#14141A", "dark": "#F5F6FC"},
            "selectionColor": {"light": "#0059DB", "dark": "#22C2F4"},
            "visualizationColors": ["#0059DB", "#22C2F4", "#F6C344", "#FF8A4C", "#9B6BDB", "#3ECF8E", "#6E7180"],
            "widgetHeaderAlignment": "LEFT", "widgetCornerRadius": 12}},
    }


def main() -> None:
    SAIDA.write_text(json.dumps(montar(), ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"ok: {SAIDA.relative_to(AQUI.parent.parent)}")


if __name__ == "__main__":
    main()
