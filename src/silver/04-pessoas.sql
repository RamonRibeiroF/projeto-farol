-- silver.colaboradores e silver.apontamentos.

-- colaboradores: COL0102, COL0257 e COL0433 aparecem duas vezes (nome e papel em CAIXA ALTA).
-- Fica o cadastro com o papel em minúsculas.
CREATE OR REFRESH MATERIALIZED VIEW colaboradores
COMMENT 'As 520 pessoas da Vértice, uma linha por colaborador: papel, senioridade, custo por hora, admissão e desligamento.'
AS
WITH ordenado AS (
    SELECT *,
           row_number() OVER (PARTITION BY colaborador_id
                              ORDER BY CASE WHEN papel = lower(papel) THEN 0 ELSE 1 END) AS ordem
    FROM lakehouse_vertice.bronze.colaboradores
)
SELECT colaborador_id,
       nome,
       papel,
       senioridade,
       CAST(custo_hora AS DECIMAL(10,2)) AS custo_hora,
       to_date(data_admissao)            AS data_admissao,
       to_date(nullif(trim(data_desligamento), '')) AS data_desligamento
FROM ordenado
WHERE ordem = 1;

-- apontamentos: o timesheet semanal. semana = sexta (semana_inicio é a segunda).
CREATE OR REFRESH MATERIALIZED VIEW apontamentos
COMMENT 'Timesheet semanal: horas disponíveis e horas apontadas por colaborador e projeto. semana = sexta da semana.'
AS
SELECT colaborador_id,
       projeto_id,
       to_date(semana_inicio)                AS semana_inicio,
       date_add(to_date(semana_inicio), 4)   AS semana,
       CAST(horas_disponiveis AS DOUBLE)     AS horas_disponiveis,
       CAST(horas_apontadas   AS DOUBLE)     AS horas_apontadas
FROM lakehouse_vertice.bronze.apontamentos;
