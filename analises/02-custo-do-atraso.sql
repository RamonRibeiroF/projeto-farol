-- Databricks notebook source

-- ============================================
-- CUSTO DO ATRASO: quanto custa? O estouro e o farol do gerente
-- ============================================
-- Conceito: juntar várias consultas com WITH e fazer conta de KPI
-- Pergunta de negócio: SE NADA MUDAR, QUANTO A VÉRTICE VAI PERDER? E O FAROL MOSTRA ISSO?
-- Usa o rascunho da parte 5 de 01-sql-na-bronze.sql (bronze.rascunho_tarefas): execute-a antes.
--
-- As contas (todas sobre o orçamento de custo do projeto):
--   valor agregado (EV) = orçamento × fração pronta          (quanto vale o que já foi entregue)
--   CPI = EV ÷ custo real                                    abaixo de 1 é estouro: cada R$ 1
--                                                            gasto entregou menos de R$ 1
--   EAC = orçamento ÷ CPI                                    quanto o projeto vai custar no fim,
--                                                            se o ritmo continuar
--   estouro previsto = EAC − orçamento
--
-- A consulta tem 3 pedaços (WITH), cada um uma pergunta simples:
--   valor   quanto de cada projeto está pronto, e quanto devia estar (parte 5 de 01-sql-na-bronze.sql)
--   custo   quanto cada projeto já gastou (parte 4 de 01-sql-na-bronze.sql, por projeto)
--   farol   a cor que o gerente publicou nesta sexta, 16/10

-- 1. Projeto a projeto: prazo, custo, estouro, e o farol do gerente.
--    Resultado esperado: 41 projetos, do pior para o melhor. Repare na coluna farol_do_gerente:
--    PRJ-012, 028, 034 e 042 estão VERDES com SPI abaixo de 0,9. São os "melancias":
--    verdes por fora, vermelhos por dentro.
WITH valor AS (
    SELECT projeto_id,
           SUM(horas)                       AS horas_totais,
           SUM(horas * pct_concluido / 100) AS horas_agregadas,
           SUM(horas * GREATEST(0, LEAST(1,
               datediff(DATE'2026-10-16', inicio_baseline) / datediff(fim_baseline, inicio_baseline)
           )))                               AS horas_planejadas
    FROM lakehouse_vertice.bronze.rascunho_tarefas
    GROUP BY projeto_id
),
custo AS (
    SELECT projeto_id,
           SUM(CAST(replace(valor, ',', '.') AS DECIMAL(18,2))) AS custo_real
    FROM lakehouse_vertice.bronze.custos
    GROUP BY projeto_id
),
farol AS (
    SELECT projeto_id, lower(farol) AS farol
    FROM lakehouse_vertice.bronze.status_semanal
    WHERE data_status = '2026-10-16'
)
SELECT p.projeto_id,
       p.cliente,
       ROUND(v.horas_agregadas / v.horas_planejadas, 2)                          AS spi,
       ROUND(CAST(p.orcamento_custo AS DECIMAL(18,2))
             * v.horas_agregadas / v.horas_totais / c.custo_real, 2)              AS cpi,
       f.farol                                                                   AS farol_do_gerente,
       -- estouro = EAC − orçamento = orçamento ÷ CPI − orçamento
       ROUND((c.custo_real * v.horas_totais / v.horas_agregadas
              - CAST(p.orcamento_custo AS DECIMAL(18,2))) / 1000000, 2)           AS estouro_milhoes
FROM lakehouse_vertice.bronze.projetos p
JOIN valor v USING (projeto_id)
JOIN custo c USING (projeto_id)
JOIN farol f USING (projeto_id)
WHERE p.status = 'em_andamento'
ORDER BY spi;

-- COMMAND ----------

-- 2. O número para o dono: quanto a carteira vai estourar, somando só quem estoura.
--    (Projeto que está gastando menos que o previsto não "compensa" o que outro queima.)
--    Nada novo: as mesmas contas do bloco 1, agora somadas. GREATEST(0, x) zera quem não estoura.
--    Resultado esperado: R$ 6,47 mi. A resposta da pergunta 2.
WITH valor AS (
    SELECT projeto_id,
           SUM(horas)                       AS horas_totais,
           SUM(horas * pct_concluido / 100) AS horas_agregadas
    FROM lakehouse_vertice.bronze.rascunho_tarefas
    GROUP BY projeto_id
),
custo AS (
    SELECT projeto_id,
           SUM(CAST(replace(valor, ',', '.') AS DECIMAL(18,2))) AS custo_real
    FROM lakehouse_vertice.bronze.custos
    GROUP BY projeto_id
)
SELECT ROUND(SUM(GREATEST(0,
           c.custo_real * v.horas_totais / v.horas_agregadas
           - CAST(p.orcamento_custo AS DECIMAL(18,2)))) / 1000000, 2) AS estouro_previsto_milhoes
FROM lakehouse_vertice.bronze.projetos p
JOIN valor v USING (projeto_id)
JOIN custo c USING (projeto_id)
WHERE p.status = 'em_andamento';
