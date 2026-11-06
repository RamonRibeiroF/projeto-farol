-- Conferência da bronze, antes da silver.
-- Uma linha por tabela: esperado (seed 42), obtido e se bateu. bronze.feriados fica de fora
-- (cresce a cada execução). Primeiro o raise_error() (derruba a tarefa dizendo qual tabela e onde olhar);
-- por último a tabela, porque a saída da sql_task mostra só o último SELECT.

SELECT CASE WHEN COUNT(*) > 0 THEN raise_error(concat(
           'Bronze diferente do esperado em: ', concat_ws(', ', collect_list(divergencia)),
           '. Olhe a saída da tarefa ingestao_data_lake (download do data lake e read_files).'))
       END AS conferencia
FROM (
    SELECT concat(tabela, ' (esperado ', esperado, ', obtido ', obtido, ')') AS divergencia
    FROM (
        SELECT 'projetos'            AS tabela, 60    AS esperado, (SELECT COUNT(*) FROM lakehouse_vertice.bronze.projetos)            AS obtido UNION ALL
        SELECT 'status_semanal',               3911,  (SELECT COUNT(*) FROM lakehouse_vertice.bronze.status_semanal)      UNION ALL
        SELECT 'excel_tarefas',                1663,  (SELECT COUNT(*) FROM lakehouse_vertice.bronze.excel_tarefas)       UNION ALL
        SELECT 'clickup_tarefas',              2119,  (SELECT COUNT(*) FROM lakehouse_vertice.bronze.clickup_tarefas)     UNION ALL
        SELECT 'msproject_tarefas',            1260,  (SELECT COUNT(*) FROM lakehouse_vertice.bronze.msproject_tarefas)   UNION ALL
        SELECT 'colaboradores',                523,   (SELECT COUNT(*) FROM lakehouse_vertice.bronze.colaboradores)       UNION ALL
        SELECT 'apontamentos',                 30883, (SELECT COUNT(*) FROM lakehouse_vertice.bronze.apontamentos)        UNION ALL
        SELECT 'custos',                       23640, (SELECT COUNT(*) FROM lakehouse_vertice.bronze.custos)              UNION ALL
        SELECT 'entregas_fornecedor',          640,   (SELECT COUNT(*) FROM lakehouse_vertice.bronze.entregas_fornecedor)
    )
    WHERE esperado <> obtido
);

SELECT tabela, esperado, obtido, CASE WHEN esperado = obtido THEN 'ok' ELSE 'DIVERGE' END AS status
FROM (
    SELECT 'projetos'            AS tabela, 60    AS esperado, (SELECT COUNT(*) FROM lakehouse_vertice.bronze.projetos)            AS obtido UNION ALL
    SELECT 'status_semanal',               3911,  (SELECT COUNT(*) FROM lakehouse_vertice.bronze.status_semanal)      UNION ALL
    SELECT 'excel_tarefas',                1663,  (SELECT COUNT(*) FROM lakehouse_vertice.bronze.excel_tarefas)       UNION ALL
    SELECT 'clickup_tarefas',              2119,  (SELECT COUNT(*) FROM lakehouse_vertice.bronze.clickup_tarefas)     UNION ALL
    SELECT 'msproject_tarefas',            1260,  (SELECT COUNT(*) FROM lakehouse_vertice.bronze.msproject_tarefas)   UNION ALL
    SELECT 'colaboradores',                523,   (SELECT COUNT(*) FROM lakehouse_vertice.bronze.colaboradores)       UNION ALL
    SELECT 'apontamentos',                 30883, (SELECT COUNT(*) FROM lakehouse_vertice.bronze.apontamentos)        UNION ALL
    SELECT 'custos',                       23640, (SELECT COUNT(*) FROM lakehouse_vertice.bronze.custos)              UNION ALL
    SELECT 'entregas_fornecedor',          640,   (SELECT COUNT(*) FROM lakehouse_vertice.bronze.entregas_fornecedor)
)
ORDER BY tabela;
