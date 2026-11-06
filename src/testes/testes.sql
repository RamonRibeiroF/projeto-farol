-- Testes de qualidade da silver e da gold (sql_task, depois do medalhão).
-- Uma view temporária calcula os 10 testes (esperado × obtido); o raise_error derruba a tarefa
-- dizendo quais falharam; por último a tabela, porque a saída da sql_task mostra só o último SELECT.

CREATE OR REPLACE TEMPORARY VIEW resultado_testes AS
SELECT * FROM (

    -- 1 os 60 projetos têm cronograma na silver.tarefas
    SELECT 1 AS teste, 'os 60 projetos têm cronograma na silver.tarefas' AS descricao,
           '60' AS esperado,
           CAST((SELECT COUNT(DISTINCT t.projeto_id)
                 FROM lakehouse_vertice.silver.tarefas t
                 JOIN lakehouse_vertice.silver.projetos p USING (projeto_id)) AS STRING) AS obtido

    UNION ALL
    -- 2 cada projeto veio de UMA ferramenta, a do cadastro do PMO
    SELECT 2, 'cada projeto veio de uma ferramenta, a do cadastro do PMO',
           '0 projetos fora da regra',
           CAST((SELECT COUNT(*) FROM (
                     SELECT t.projeto_id
                     FROM lakehouse_vertice.silver.tarefas t
                     JOIN lakehouse_vertice.silver.projetos p USING (projeto_id)
                     GROUP BY t.projeto_id
                     HAVING COUNT(DISTINCT t.ferramenta) > 1
                         OR max(t.ferramenta) <> max(p.ferramenta))) AS STRING) || ' projetos fora da regra'

    UNION ALL
    -- 3 as horas do Excel na silver = a soma das linhas de TOTAL das planilhas
    SELECT 3, 'horas do Excel na silver = soma das linhas de TOTAL',
           CAST((SELECT round(SUM(CAST(replace(horas_previstas, 'h', '') AS DOUBLE)), 2)
                 FROM lakehouse_vertice.bronze.excel_tarefas WHERE tarefa = 'TOTAL') AS STRING),
           CAST((SELECT round(SUM(horas), 2)
                 FROM lakehouse_vertice.silver.tarefas WHERE ferramenta = 'excel') AS STRING)

    UNION ALL
    -- 4 uma linha por pessoa na silver
    SELECT 4, 'uma linha por pessoa na silver.colaboradores',
           CAST((SELECT COUNT(DISTINCT colaborador_id) FROM lakehouse_vertice.silver.colaboradores) AS STRING),
           CAST((SELECT COUNT(*) FROM lakehouse_vertice.silver.colaboradores) AS STRING)

    UNION ALL
    -- 5 a CodeForge virou um fornecedor só
    SELECT 5, 'a CodeForge virou um fornecedor só',
           '1',
           CAST((SELECT COUNT(DISTINCT fornecedor) FROM lakehouse_vertice.silver.entregas_fornecedor
                 WHERE replace(lower(fornecedor), ' ', '') LIKE '%codeforge%') AS STRING)

    UNION ALL
    -- 6 a limpeza não mudou o custo total (bronze com replace = silver)
    SELECT 6, 'custo total: bronze (com replace) = silver',
           CAST((SELECT SUM(CAST(replace(valor, ',', '.') AS DECIMAL(18,2)))
                 FROM lakehouse_vertice.bronze.custos) AS STRING),
           CAST((SELECT SUM(valor) FROM lakehouse_vertice.silver.custos) AS STRING)

    UNION ALL
    -- 7 os 60 projetos têm fotografia de hoje
    SELECT 7, 'os 60 projetos têm fotografia de hoje (uma linha cada)',
           '60 linhas, 60 projetos',
           (SELECT COUNT(*) || ' linhas, ' || COUNT(DISTINCT projeto_id) || ' projetos'
            FROM lakehouse_vertice.gold.projeto_situacao_atual)

    UNION ALL
    -- 8 todo projeto em andamento tem SPI e CPI
    SELECT 8, 'todo projeto em andamento tem SPI e CPI',
           '0 sem SPI ou CPI',
           CAST((SELECT COUNT(*) FROM lakehouse_vertice.gold.projeto_situacao_atual
                 WHERE status = 'em_andamento' AND (spi IS NULL OR cpi IS NULL)) AS STRING) || ' sem SPI ou CPI'

    UNION ALL
    -- 9 o EV total da carteira em andamento, hoje: status semanal (fato) × ferramentas (situação atual),
    --   diferença < 1%. A comparação é na soma, não projeto a projeto: o PRJ-013 diverge sozinho
    --   porque 3 tarefas do Excel vieram com % acima de 100 e ainda não iniciadas; a silver corta em
    --   100 (least(...,100), com flag) e a regra fica como está.
    SELECT 9, 'EV total em andamento hoje: status semanal × ferramentas (diferença < 1%)',
           'diferença < 1%',
           (SELECT CASE WHEN abs(SUM(f.ev) - SUM(s.ev)) / SUM(s.ev) < 0.01 THEN 'diferença < 1%'
                        ELSE 'diferença de ' || round(100 * abs(SUM(f.ev) - SUM(s.ev)) / SUM(s.ev), 2) || '%'
                   END
            FROM lakehouse_vertice.gold.fato_projeto_semana f
            JOIN lakehouse_vertice.gold.projeto_situacao_atual s USING (projeto_id)
            WHERE f.semana = DATE'2026-10-16'
              AND s.status = 'em_andamento')

    UNION ALL
    -- 10 AC de hoje no fato = soma dos lançamentos até hoje
    SELECT 10, 'AC de hoje no fato = soma dos lançamentos até hoje',
           '0 projetos divergentes',
           CAST((SELECT COUNT(*)
                 FROM lakehouse_vertice.gold.fato_projeto_semana f
                 LEFT JOIN (SELECT projeto_id, SUM(valor) AS total
                            FROM lakehouse_vertice.silver.custos
                            WHERE data <= DATE'2026-10-16'
                            GROUP BY projeto_id) c USING (projeto_id)
                 WHERE f.semana = DATE'2026-10-16'
                   AND f.ac <> coalesce(c.total, 0)) AS STRING) || ' projetos divergentes'
);

SELECT CASE WHEN COUNT(*) > 0 THEN raise_error(concat(
           'Testes de qualidade falharam: ',
           concat_ws(' | ', collect_list(concat(teste, ' ', descricao, ' (esperado ', esperado, ', obtido ', obtido, ')')))))
       END AS testes
FROM resultado_testes
WHERE esperado IS DISTINCT FROM obtido;

SELECT teste, descricao, esperado, obtido,
       CASE WHEN esperado IS NOT DISTINCT FROM obtido THEN 'ok' ELSE 'FALHOU' END AS status
FROM resultado_testes
ORDER BY teste;
