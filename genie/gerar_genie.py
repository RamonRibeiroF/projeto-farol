#!/usr/bin/env python3
"""Gera o Genie Agent "Farol · Diretoria" como JSON versionado (serialized_space versão 2).

Uso:
    python3 genie/gerar_genie.py                      # escreve genie/diretoria.geniespace.json
    python3 genie/gerar_genie.py --com-score          # inclui gold.score_estouro_30d (só se a tabela existir)

O deploy é pelo bundle (resources/genie.genie_space.yml). Editar o espaço no workspace trava o próximo
deploy ("modified remotely"): a mudança vem para este script.

O score do modelo entra SÓ se a tabela existir:
    databricks tables exists lakehouse_vertice.gold.score_estouro_30d --profile SEU-PERFIL
Sem ela, nenhuma instrução nem exemplo fala de score.
"""
from __future__ import annotations

import argparse
import json
import pathlib

AQUI = pathlib.Path(__file__).resolve().parent
SAIDA = AQUI / "diretoria.geniespace.json"
C = "lakehouse_vertice"

TABELAS = [
    f"{C}.gold.fato_projeto_semana",
    f"{C}.gold.projeto_situacao_atual",
    f"{C}.gold.status_estruturado",
    f"{C}.gold.utilizacao_pessoa_semana",
    f"{C}.silver.entregas_fornecedor",
]
TABELA_SCORE = f"{C}.gold.score_estouro_30d"
METRIC_VIEW = f"{C}.gold.mv_projetos"

# as 4 perguntas do dono (README.md)
PERGUNTAS_DO_DONO = [
    "Quais projetos estão atrasados, e de quais clientes?",
    "Quanto esse atraso vai me custar?",
    "Tenho gente parada enquanto outro projeto pede gente?",
    "O que vai dar errado no próximo mês, e o que eu faço agora?",
]

# ---------------------------------------------------------------- instrução de texto

INSTRUCAO = """QUEM PERGUNTA
Quem usa este agente é o dono e a diretoria da Vértice Tecnologia (520 pessoas, 60 projetos de clientes). Eles não escrevem SQL. Responda em português, direto, com números em R$ e índices com 2 casas decimais (ROUND(x, 2)).

DATAS
- HOJE é 2026-10-16 (sexta-feira). NUNCA use current_date(), now() ou current_timestamp(): use DATE'2026-10-16'.
- "últimos 90 dias" = data_status >= DATE'2026-07-18' (até 2026-10-16).
- "últimas 12 semanas" = semana > DATE'2026-07-24' (as 12 sextas de 2026-07-31 a 2026-10-16).
- "próximo mês" = de 2026-10-17 a 2026-11-16.
- As semanas são sempre sextas-feiras (coluna semana do fato e data_status do status).

ONDE ESTÁ CADA COISA
- lakehouse_vertice.gold.mv_projetos (metric view, só projetos em andamento): use para TOTAIS de hoje da carteira, com MEASURE(): MEASURE(spi), MEASURE(cpi), MEASURE(estouro_previsto), MEASURE(carteira), MEASURE(eac), MEASURE(margem_projetada), MEASURE(projetos), MEASURE(projetos_em_risco), MEASURE(projetos_criticos), MEASURE(projetos_melancia), MEASURE(atraso_projetado_medio_dias). Ex.: SELECT ROUND(MEASURE(spi), 2) FROM lakehouse_vertice.gold.mv_projetos.
- lakehouse_vertice.gold.projeto_situacao_atual: uma linha por projeto (fotografia de hoje). Use para RANKING, listas, contagens por situação e o valor de UM projeto. Para a carteira atual filtre status = 'em_andamento'.
- lakehouse_vertice.gold.fato_projeto_semana: projeto x semana. PV, EV e AC já são ACUMULADOS até a semana: NUNCA some semanas. Para o valor numa semana, filtre a semana. SPI/CPI de uma semana = a coluna spi/cpi daquela linha.
- lakehouse_vertice.gold.status_estruturado: o texto do status semanal em colunas (causa_bloqueio, bloqueio, quem_destrava, dias_impacto).
- lakehouse_vertice.gold.utilizacao_pessoa_semana: pessoa x projeto x semana (papel, senioridade, horas, utilização, custo ocioso).
- lakehouse_vertice.silver.entregas_fornecedor: cada entrega das consultorias (prometido x entregue, em_atraso).

COMO NOMEAR PROJETOS
- projeto_id é o código (PRJ-011). projeto é o código e o nome juntos ("PRJ-011 · Checkout e meios de pagamento - Supermercados Bom Preço").
- Para filtrar UM projeto citado pelo código, use projeto_id = 'PRJ-011' (nunca projeto = 'PRJ-011').
- Sempre que a resposta listar ou apontar projetos, traga a coluna projeto (não só projeto_id).
- "Quais clientes" devolve cada cliente UMA vez (SELECT DISTINCT cliente).

FÓRMULAS E REGRAS DE CORTE
- SPI = SUM(ev) / SUM(pv): abaixo de 1 é atraso. CPI = SUM(ev) / SUM(ac): abaixo de 1 é gastar mais do que entrega. Razão de carteira é sempre SUM/SUM, nunca média de razão.
- EAC = orçamento / CPI. Estouro previsto = EAC - orçamento (nunca negativo). Margem projetada = (valor_contrato - EAC) / valor_contrato.
- situacao: 'crítico' se SPI ou CPI < 0,8. 'atenção' se < 0,9. Senão 'ok'. Projetos encerrados têm situacao 'concluído' e não contam na carteira.
- "em risco" ou "atrasados" = situacao IN ('atenção', 'crítico'), com status = 'em_andamento'.

FAROL E MELANCIA
- farol_do_gerente é o que o gerente informou no status de hoje. farol_calculado é pelo número: verde se SPI >= 0,95, amarelo se >= 0,90, senão vermelho.
- Melancia = farol do gerente verde mas SPI abaixo de 0,9 (verde por fora, vermelho por dentro). Use a coluna booleana melancia (WHERE melancia), que já considera só projetos em andamento.
- "farol verde mas atrasado" = melancia.

FERRAMENTA
- ferramenta vale 'excel', 'clickup' ou 'msproject' (minúsculas).

POR QUE O PROJETO X ATRASOU
Responda com lakehouse_vertice.gold.status_estruturado dos últimos 90 dias (data_status >= DATE'2026-07-18'), sem causa_bloqueio 'sem_bloqueio' e 'nao_reportado': a causa mais frequente (GROUP BY causa_bloqueio ORDER BY COUNT(*) DESC), o que está bloqueando, quem destrava e a soma de dias_impacto. Traga junto o SPI do projeto (projeto_situacao_atual). Se a causa for falta_sre, mostre também os SREs ociosos (regra de gente parada abaixo, com papel = 'sre').

GENTE PARADA
Pessoa parada = utilização abaixo de 20% nas últimas 12 semanas, calculada SUM(horas_apontadas) / SUM(horas_disponiveis) < 0.2 por pessoa (GROUP BY colaborador_id), com semana > DATE'2026-07-24'. Traga colaborador_id, nome, papel, horas paradas e custo ocioso. "Outro projeto pede gente" = projetos em atenção ou crítico com causa falta_sre ou rotatividade nos últimos 90 dias.

FORNECEDOR
Desempenho de fornecedor = prazo real / prazo prometido (prazo_real_dias / prazo_prometido_dias) em lakehouse_vertice.silver.entregas_fornecedor, por fornecedor (o nome já normalizado). Acima de 1 é atraso. "Qual fornecedor mais atrasa" devolve UM fornecedor, o de maior razão. Entrega em atraso hoje = em_atraso (em aberto com data prometida vencida em 2026-10-16).

O QUE VAI DAR ERRADO NO PRÓXIMO MÊS
Junte três riscos e diga o que fazer em cada um:
1. as entregas de consultoria em atraso hoje (silver.entregas_fornecedor WHERE em_atraso): cobrar o fornecedor, quase todas são da CodeForge.
2. o change freeze de varejo da Black Friday, de 01/11/2026 a 10/01/2027: trava deploy nos projetos de e-commerce em andamento. Projeto de e-commerce = tipo_projeto contendo 'commerce', 'checkout' ou 'marketplace' (lower(tipo_projeto) LIKE '%commerce%' OR '%checkout%' OR '%marketplace%'). Antecipar o que precisa ir para produção antes de 01/11.
3. os projetos críticos e em atenção de hoje, com a causa principal do status dos últimos 90 dias.
"""

INSTRUCAO_SCORE = """
SCORE DO MODELO (probabilidade de estouro em 30 dias)
- lakehouse_vertice.gold.score_estouro_30d: projeto_id, data_referencia, prob_estouro_30d (0 a 1), ranking, faixa_risco ('alto' >= 0,5, 'medio' >= 0,2, 'baixo') e principais_fatores. Use SEMPRE a data_referencia mais recente (data_referencia = (SELECT MAX(data_referencia) FROM lakehouse_vertice.gold.score_estouro_30d)).
- Em "o que vai dar errado no próximo mês", acrescente os projetos com situacao = 'ok' hoje mas faixa_risco 'alto' ou 'medio', com principais_fatores: são os que ainda parecem bem e o modelo diz que vão estourar.
"""

# ---------------------------------------------------------------- exemplos de SQL (um por pergunta do dono)

SQL_ATRASADOS = f"""SELECT projeto, cliente, situacao, ROUND(spi, 2) AS spi, ROUND(cpi, 2) AS cpi,
       farol_do_gerente, farol_calculado, melancia
FROM {C}.gold.projeto_situacao_atual
WHERE status = 'em_andamento' AND situacao IN ('atenção', 'crítico')
ORDER BY least(spi, cpi)"""

SQL_CUSTO = f"""SELECT situacao,
       MEASURE(projetos)                        AS projetos,
       ROUND(MEASURE(estouro_previsto), 2)      AS estouro_previsto,
       ROUND(MEASURE(eac), 2)                   AS eac,
       ROUND(MEASURE(margem_projetada), 4)      AS margem_projetada,
       ROUND(MEASURE(atraso_projetado_medio_dias), 0) AS atraso_medio_dias
FROM {C}.gold.mv_projetos
GROUP BY situacao
ORDER BY estouro_previsto DESC"""

SQL_GENTE_PARADA = f"""WITH parados AS (
    SELECT colaborador_id, nome, papel,
           ROUND(SUM(horas_apontadas) / SUM(horas_disponiveis), 2) AS utilizacao,
           SUM(horas_ociosas)                                      AS horas_paradas,
           SUM(custo_ocioso)                                       AS custo_ocioso
    FROM {C}.gold.utilizacao_pessoa_semana
    WHERE semana > DATE'2026-07-24'
    GROUP BY colaborador_id, nome, papel
    HAVING SUM(horas_apontadas) / SUM(horas_disponiveis) < 0.2
),
pedem_gente AS (
    SELECT s.projeto_id, s.causa_bloqueio, COUNT(*) AS semanas, SUM(s.dias_impacto) AS dias_impacto
    FROM {C}.gold.status_estruturado s
    JOIN {C}.gold.projeto_situacao_atual p ON p.projeto_id = s.projeto_id
    WHERE s.data_status >= DATE'2026-07-18'
      AND s.causa_bloqueio IN ('falta_sre', 'rotatividade')
      AND p.status = 'em_andamento' AND p.situacao IN ('atenção', 'crítico')
    GROUP BY s.projeto_id, s.causa_bloqueio
)
SELECT 'pessoa parada' AS tipo, colaborador_id AS codigo, nome AS descricao, papel AS detalhe,
       utilizacao AS indicador, custo_ocioso AS valor
FROM parados
UNION ALL
SELECT 'projeto pedindo gente', projeto_id, causa_bloqueio, CAST(semanas AS STRING), NULL, dias_impacto
FROM pedem_gente
ORDER BY tipo, valor DESC"""

SQL_PROXIMO_MES = f"""SELECT 'entrega de consultoria em atraso' AS risco, e.projeto_id, p.projeto,
       concat(e.fornecedor, ': ', e.item, ' (prometida em ', e.data_prometida, ')') AS detalhe,
       'cobrar o fornecedor e escalar' AS o_que_fazer
FROM {C}.silver.entregas_fornecedor e
JOIN {C}.gold.projeto_situacao_atual p ON p.projeto_id = e.projeto_id
WHERE e.em_atraso
UNION ALL
SELECT 'change freeze de varejo (01/11/2026 a 10/01/2027)', projeto_id, projeto,
       concat(tipo_projeto, ' · situação ', situacao),
       'antecipar o que precisa ir para produção antes de 01/11'
FROM {C}.gold.projeto_situacao_atual
WHERE status = 'em_andamento'
  AND (lower(tipo_projeto) LIKE '%commerce%' OR lower(tipo_projeto) LIKE '%checkout%'
       OR lower(tipo_projeto) LIKE '%marketplace%')
UNION ALL
SELECT concat('projeto ', situacao), projeto_id, projeto,
       concat('SPI ', ROUND(spi, 2), ' · CPI ', ROUND(cpi, 2)),
       'atacar a causa principal do status'
FROM {C}.gold.projeto_situacao_atual
WHERE status = 'em_andamento' AND situacao = 'crítico'"""

SQL_SCORE_PRJ024 = f"""SELECT s.projeto_id, p.projeto, ROUND(s.prob_estouro_30d, 2) AS prob_estouro_30d,
       s.faixa_risco, s.principais_fatores, s.data_referencia
FROM {C}.gold.score_estouro_30d s
JOIN {C}.gold.projeto_situacao_atual p ON p.projeto_id = s.projeto_id
WHERE s.projeto_id = 'PRJ-024'
  AND s.data_referencia = (SELECT MAX(data_referencia) FROM {C}.gold.score_estouro_30d)"""


def ids(prefixo: str):
    """IDs de 32 caracteres hexadecimais, únicos e em ordem crescente."""
    n = 0
    while True:
        n += 1
        yield f"{prefixo}{n:0{32 - len(prefixo)}x}"


def linhas(texto: str) -> list[str]:
    return [l + "\n" for l in texto.strip("\n").split("\n")]


def montar(com_score: bool) -> dict:
    id_pergunta, id_exemplo, id_instrucao = ids("a1"), ids("b1"), ids("c1")

    exemplos = list(zip(PERGUNTAS_DO_DONO, [SQL_ATRASADOS, SQL_CUSTO, SQL_GENTE_PARADA, SQL_PROXIMO_MES]))
    tabelas = list(TABELAS)
    instrucao = INSTRUCAO
    if com_score:
        tabelas.append(TABELA_SCORE)
        instrucao += INSTRUCAO_SCORE
        exemplos.append(("Qual a chance de o PRJ-024 estourar?", SQL_SCORE_PRJ024))

    return {
        "version": 2,
        "config": {"sample_questions": [{"id": next(id_pergunta), "question": [p]} for p in PERGUNTAS_DO_DONO]},
        "data_sources": {
            "tables": [{"identifier": t} for t in sorted(tabelas)],
            "metric_views": [{"identifier": METRIC_VIEW}],
        },
        "instructions": {
            "text_instructions": [{"id": next(id_instrucao), "content": linhas(instrucao)}],
            "example_question_sqls": [{"id": next(id_exemplo), "question": [p], "sql": linhas(s)} for p, s in exemplos],
        },
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--com-score", action="store_true",
                    help="inclui gold.score_estouro_30d (confira antes com databricks tables exists)")
    a = ap.parse_args()
    SAIDA.write_text(json.dumps(montar(a.com_score), ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"ok: {SAIDA.relative_to(AQUI.parent)}" + (" (com score)" if a.com_score else " (sem score)"))


if __name__ == "__main__":
    main()
