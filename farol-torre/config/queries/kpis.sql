-- KPIs da carteira em andamento em 2026-10-16 (gold.projeto_situacao_atual).
SELECT COUNT(*)                                                             AS em_andamento,
       SUM(CASE WHEN situacao IN ('atenção', 'crítico') THEN 1 ELSE 0 END)  AS em_risco,
       SUM(CASE WHEN situacao = 'crítico' THEN 1 ELSE 0 END)                AS criticos,
       SUM(CASE WHEN melancia THEN 1 ELSE 0 END)                            AS melancias,
       SUM(estouro_previsto)                                                AS estouro_previsto,
       SUM(valor_contrato)                                                  AS carteira
FROM lakehouse_vertice.gold.projeto_situacao_atual
WHERE status = 'em_andamento'
