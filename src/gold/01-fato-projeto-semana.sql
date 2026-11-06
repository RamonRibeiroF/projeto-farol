-- gold.fato_projeto_semana: a série semanal de cada projeto, base do gráfico de tendência.
-- Uma linha por projeto e sexta-feira, da semana do início até hoje (2026-10-16).
-- PV pelo baseline das tarefas; EV pelo % que o gerente publica no status; AC pelos lançamentos acumulados.
-- Janela num CTE, agregação no seguinte.

CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.fato_projeto_semana (
    CONSTRAINT pv_nao_negativo        EXPECT (pv >= 0)         ON VIOLATION FAIL UPDATE,
    CONSTRAINT ev_ate_o_orcamento     EXPECT (ev <= orcamento) ON VIOLATION FAIL UPDATE
)
COMMENT 'Uma linha por projeto e semana (sexta-feira), do início até 2026-10-16: PV, EV, AC, SPI, CPI, EAC, o último farol publicado pelo gerente e as horas disponíveis, apontadas e ociosas da semana.'
AS
WITH semanas AS (
    SELECT p.projeto_id,
           p.orcamento_custo AS orcamento,
           explode(sequence(date_add(date_trunc('WEEK', p.data_inicio), 4),
                            DATE'2026-10-16', INTERVAL 1 WEEK)) AS semana
    FROM projetos p
),
semanas_dia AS (
    SELECT projeto_id, orcamento, to_date(semana) AS semana FROM semanas
),
-- PV: fração do baseline decorrida até a semana, ponderada pelas horas de cada tarefa
planejado AS (
    SELECT s.projeto_id,
           s.semana,
           SUM(t.horas * greatest(0, least(1, datediff(s.semana, t.inicio_baseline)
                                              / datediff(t.fim_baseline, t.inicio_baseline)))) AS horas_planejadas,
           SUM(t.horas) AS horas_totais
    FROM semanas_dia s
    JOIN tarefas t ON t.projeto_id = s.projeto_id
    GROUP BY s.projeto_id, s.semana
),
-- EV e farol: o status daquela sexta; projeto concluído não publica mais, fica o último.
-- Antes do primeiro status o % é 0: nada foi agregado ainda (NULL violaria o EXPECT).
status_da_semana AS (
    SELECT s.projeto_id,
           s.semana,
           coalesce(last_value(st.pct_concluido, true) OVER (PARTITION BY s.projeto_id ORDER BY s.semana), 0) AS pct_concluido,
           last_value(st.farol, true)         OVER (PARTITION BY s.projeto_id ORDER BY s.semana) AS farol_do_gerente
    FROM semanas_dia s
    LEFT JOIN status_semanal st
      ON st.projeto_id = s.projeto_id AND st.data_status = s.semana
),
-- AC: custo líquido acumulado até a semana (estornos inclusos)
custo_por_semana AS (
    SELECT projeto_id, semana, SUM(valor) AS valor
    FROM custos
    GROUP BY projeto_id, semana
),
acumulado AS (
    SELECT s.projeto_id, s.semana, coalesce(SUM(c.valor), 0) AS ac
    FROM semanas_dia s
    LEFT JOIN custo_por_semana c
      ON c.projeto_id = s.projeto_id AND c.semana <= s.semana
    GROUP BY s.projeto_id, s.semana
),
horas AS (
    SELECT projeto_id, semana,
           SUM(horas_disponiveis) AS horas_disponiveis,
           SUM(horas_apontadas)   AS horas_apontadas
    FROM apontamentos
    GROUP BY projeto_id, semana
),
indicadores AS (
    SELECT s.projeto_id,
           s.semana,
           s.orcamento,
           s.orcamento * pl.horas_planejadas / pl.horas_totais   AS pv,
           s.orcamento * st.pct_concluido / 100                  AS ev,
           a.ac,
           st.farol_do_gerente,
           coalesce(h.horas_disponiveis, 0)                      AS horas_disponiveis,
           coalesce(h.horas_apontadas, 0)                        AS horas_apontadas
    FROM semanas_dia s
    JOIN planejado        pl ON pl.projeto_id = s.projeto_id AND pl.semana = s.semana
    JOIN status_da_semana st ON st.projeto_id = s.projeto_id AND st.semana = s.semana
    JOIN acumulado        a  ON a.projeto_id  = s.projeto_id AND a.semana  = s.semana
    LEFT JOIN horas       h  ON h.projeto_id  = s.projeto_id AND h.semana  = s.semana
)
SELECT projeto_id,
       semana,
       orcamento,
       CAST(pv AS DECIMAL(18,2))                             AS pv,
       CAST(ev AS DECIMAL(18,2))                             AS ev,
       CAST(ac AS DECIMAL(18,2))                             AS ac,
       round(try_divide(ev, pv), 4)                          AS spi,
       round(try_divide(ev, ac), 4)                          AS cpi,
       CAST(try_divide(orcamento, round(try_divide(ev, ac), 4)) AS DECIMAL(18,2)) AS eac,
       farol_do_gerente,
       horas_disponiveis,
       horas_apontadas,
       horas_disponiveis - horas_apontadas                   AS horas_ociosas
FROM indicadores;
