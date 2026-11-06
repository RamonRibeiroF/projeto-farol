-- Pessoas com utilização < 20% nas últimas 12 semanas (semana > 2026-07-24, até 2026-10-16),
-- com horas paradas e custo ocioso médios por semana.
WITH periodo AS (
    SELECT colaborador_id,
           nome,
           papel,
           senioridade,
           custo_hora,
           SUM(horas_disponiveis)  AS horas_disponiveis,
           SUM(horas_apontadas)    AS horas_apontadas,
           SUM(horas_ociosas)      AS horas_ociosas,
           SUM(custo_ocioso)       AS custo_ocioso,
           COUNT(DISTINCT semana)  AS semanas
    FROM lakehouse_vertice.gold.utilizacao_pessoa_semana
    WHERE semana > DATE'2026-07-24'
    GROUP BY colaborador_id, nome, papel, senioridade, custo_hora
)
SELECT colaborador_id,
       nome,
       papel,
       senioridade,
       custo_hora,
       ROUND(horas_apontadas / horas_disponiveis, 4)  AS utilizacao,
       ROUND(horas_ociosas / semanas, 1)              AS horas_paradas_semana,
       ROUND(custo_ocioso / semanas, 2)               AS custo_ocioso_semana
FROM periodo
WHERE horas_apontadas / horas_disponiveis < 0.2
ORDER BY custo_ocioso_semana DESC
