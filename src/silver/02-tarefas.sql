-- silver.tarefas: AS TRÊS FERRAMENTAS VIRAM UMA.
-- Uma visão temporária por ferramenta, todas com as MESMAS 13 colunas, e um UNION ALL no fim.
-- O projeto vem sempre do de-para (silver.projetos.codigo_ferramenta).

-- ---------- EXCEL ----------
-- Datas: com '/' é dd/MM/yyyy; sem '/' é o número de série do Excel (dias desde 30/12/1899).
-- %: '45%' ou '10,5%' → tira o % e troca a vírgula; 0.45 → fração, × 100.
CREATE TEMPORARY VIEW tarefas_excel AS
SELECT coalesce(p.projeto_id, regexp_extract(e.arquivo, 'PRJ-[0-9]{3}', 0)) AS projeto_id,
       'excel'                                    AS ferramenta,
       CAST(e.id AS STRING)                       AS id_na_ferramenta,
       e.fase,
       e.tarefa,
       e.responsavel,
       CASE WHEN e.inicio_previsto  LIKE '%/%' THEN to_date(e.inicio_previsto, 'dd/MM/yyyy')
            ELSE date_add(DATE'1899-12-30', CAST(e.inicio_previsto AS INT)) END  AS inicio_baseline,
       CASE WHEN e.termino_previsto LIKE '%/%' THEN to_date(e.termino_previsto, 'dd/MM/yyyy')
            ELSE date_add(DATE'1899-12-30', CAST(e.termino_previsto AS INT)) END AS fim_baseline,
       CASE WHEN e.inicio_real      LIKE '%/%' THEN to_date(e.inicio_real, 'dd/MM/yyyy')
            ELSE date_add(DATE'1899-12-30', CAST(e.inicio_real AS INT)) END      AS inicio_real,
       CASE WHEN e.termino_real     LIKE '%/%' THEN to_date(e.termino_real, 'dd/MM/yyyy')
            ELSE date_add(DATE'1899-12-30', CAST(e.termino_real AS INT)) END     AS fim_real,
       CASE WHEN e.pct_concluido LIKE '%\%%'
            THEN CAST(replace(replace(e.pct_concluido, '%', ''), ',', '.') AS DOUBLE)
            ELSE CAST(e.pct_concluido AS DOUBLE) * 100 END                       AS pct_como_veio,
       CAST(replace(e.horas_previstas, 'h', '') AS DOUBLE)                        AS horas,
       CAST(NULL AS STRING)                       AS status_na_ferramenta
FROM lakehouse_vertice.bronze.excel_tarefas e
LEFT JOIN projetos p
  ON p.ferramenta = 'excel' AND p.codigo_ferramenta = e.arquivo
WHERE e.tarefa <> 'TOTAL';   -- a linha de TOTAL soma as de cima: contaria duas vezes

-- ---------- CLICKUP ----------
-- O projeto pelo list_id; se o código faltar no cadastro, pelo nome da lista.
-- Datas em milissegundos; %, fase e baseline dentro de custom_fields; horas em ms.
CREATE TEMPORARY VIEW tarefas_clickup AS
SELECT coalesce(pc.projeto_id, pn.projeto_id)  AS projeto_id,
       'clickup'                               AS ferramenta,
       c.id                                    AS id_na_ferramenta,
       filter(c.custom_fields, f -> f.name = 'Fase')[0].value AS fase,
       c.name                                  AS tarefa,
       c.assignees[0].username                 AS responsavel,
       to_date(timestamp_millis(CAST(filter(c.custom_fields, f -> f.name = 'Início baseline')[0].value AS BIGINT))) AS inicio_baseline,
       to_date(timestamp_millis(CAST(filter(c.custom_fields, f -> f.name = 'Fim baseline')[0].value AS BIGINT)))    AS fim_baseline,
       to_date(timestamp_millis(CAST(c.start_date AS BIGINT))) AS inicio_real,
       to_date(timestamp_millis(CAST(c.date_done  AS BIGINT))) AS fim_real,
       CAST(filter(c.custom_fields, f -> f.name = 'Progresso (%)')[0].value AS DOUBLE) AS pct_como_veio,
       c.time_estimate / 3600000               AS horas,
       -- o status chega de 12 jeitos (Done, closed, concluído, to do, backlog, doing, review...)
       CASE WHEN lower(c.status.status) IN ('done', 'closed', 'concluído')        THEN 'concluida'
            WHEN lower(c.status.status) IN ('to do', 'a fazer', 'backlog')         THEN 'a_fazer'
            WHEN lower(c.status.status) IN ('in progress', 'doing', 'em andamento', 'review') THEN 'em_andamento'
       END                                     AS status_na_ferramenta
FROM lakehouse_vertice.bronze.clickup_tarefas c
LEFT JOIN projetos pc
  ON pc.ferramenta = 'clickup' AND pc.codigo_ferramenta = c.list_id
LEFT JOIN projetos pn
  ON pn.ferramenta = 'clickup' AND pn.codigo_ferramenta IS NULL AND pn.nome_projeto = c.list_name;

-- ---------- MS PROJECT ----------
-- Só Summary = 0: as tarefas-resumo (fases e o projeto) somam as de baixo.
-- A fase é a última tarefa-resumo de OutlineLevel 1 antes da tarefa (janela num CTE, filtro depois).
CREATE TEMPORARY VIEW tarefas_msproject AS
WITH com_fase AS (
    SELECT m.*,
           last_value(CASE WHEN m.OutlineLevel = 1 THEN m.Name END, true)
               OVER (PARTITION BY m.arquivo ORDER BY m.UID) AS fase
    FROM lakehouse_vertice.bronze.msproject_tarefas m
)
SELECT coalesce(p.projeto_id, regexp_extract(m.arquivo, 'PRJ-[0-9]{3}', 0)) AS projeto_id,
       'msproject'                             AS ferramenta,
       CAST(m.UID AS STRING)                   AS id_na_ferramenta,
       m.fase,
       m.Name                                  AS tarefa,
       CAST(NULL AS STRING)                    AS responsavel,
       to_date(m.Baseline.Start)               AS inicio_baseline,
       to_date(m.Baseline.Finish)              AS fim_baseline,
       to_date(m.ActualStart)                  AS inicio_real,
       to_date(m.ActualFinish)                 AS fim_real,
       CAST(m.PercentComplete AS DOUBLE)       AS pct_como_veio,
       CAST(regexp_extract(m.Work, 'PT([0-9]+)H', 1) AS DOUBLE) AS horas,
       CAST(NULL AS STRING)                    AS status_na_ferramenta
FROM com_fase m
LEFT JOIN projetos p
  ON p.ferramenta = 'msproject' AND p.codigo_ferramenta = m.arquivo
WHERE m.Summary = 0;

-- ---------- AS TRÊS NUMA SÓ ----------
CREATE OR REFRESH MATERIALIZED VIEW tarefas (
    CONSTRAINT achou_o_projeto  EXPECT (projeto_id IS NOT NULL)            ON VIOLATION FAIL UPDATE,
    CONSTRAINT pct_entre_0_e_100 EXPECT (pct_concluido BETWEEN 0 AND 100)  ON VIOLATION FAIL UPDATE,
    CONSTRAINT horas_positivas  EXPECT (horas > 0)                         ON VIOLATION FAIL UPDATE
)
COMMENT 'Todas as tarefas dos 60 projetos num modelo só: Excel, ClickUp e MS Project integrados pelo de-para do PMO. Baseline, datas reais, % concluído (limitado a 100) e horas previstas por tarefa. Base do SPI e do CPI.'
AS
SELECT concat_ws('-', projeto_id, ferramenta, id_na_ferramenta) AS tarefa_id,
       projeto_id,
       ferramenta,
       id_na_ferramenta,
       fase,
       tarefa,
       responsavel,
       inicio_baseline,
       fim_baseline,
       inicio_real,
       fim_real,
       least(pct_como_veio, 100)  AS pct_concluido,
       pct_como_veio > 100        AS pct_veio_acima_de_100,
       pct_como_veio,
       horas,
       status_na_ferramenta
FROM (
    SELECT * FROM tarefas_excel
    UNION ALL
    SELECT * FROM tarefas_clickup
    UNION ALL
    SELECT * FROM tarefas_msproject
);
