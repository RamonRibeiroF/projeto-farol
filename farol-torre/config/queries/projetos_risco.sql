-- Projetos em andamento do pior para o melhor, com a causa de bloqueio mais frequente
-- nos últimos 90 dias (data_status >= 2026-07-18) e os dias de impacto por falta de SRE e por rotatividade.
WITH causas AS (
    SELECT projeto_id,
           causa_bloqueio,
           COUNT(*) AS semanas
    FROM lakehouse_vertice.gold.status_estruturado
    WHERE data_status >= DATE'2026-07-18'
      AND causa_bloqueio NOT IN ('sem_bloqueio', 'nao_reportado', 'nao_classificado')
    GROUP BY projeto_id, causa_bloqueio
),
ranking AS (
    SELECT projeto_id,
           causa_bloqueio,
           row_number() OVER (PARTITION BY projeto_id ORDER BY semanas DESC, causa_bloqueio) AS posicao
    FROM causas
),
impacto AS (
    SELECT projeto_id,
           coalesce(SUM(CASE WHEN causa_bloqueio = 'falta_sre'    THEN dias_impacto END), 0) AS dias_falta_sre,
           coalesce(SUM(CASE WHEN causa_bloqueio = 'rotatividade' THEN dias_impacto END), 0) AS dias_rotatividade
    FROM lakehouse_vertice.gold.status_estruturado
    WHERE data_status >= DATE'2026-07-18'
    GROUP BY projeto_id
)
SELECT p.projeto_id,
       p.projeto,
       p.cliente,
       p.situacao,
       p.spi,
       p.cpi,
       p.estouro_previsto,
       p.atraso_projetado_dias,
       p.farol_do_gerente,
       p.farol_calculado,
       p.melancia,
       r.causa_bloqueio                       AS causa_principal,
       coalesce(i.dias_falta_sre, 0)          AS dias_falta_sre,
       coalesce(i.dias_rotatividade, 0)       AS dias_rotatividade
FROM lakehouse_vertice.gold.projeto_situacao_atual p
LEFT JOIN ranking r ON r.projeto_id = p.projeto_id AND r.posicao = 1
LEFT JOIN impacto i ON i.projeto_id = p.projeto_id
WHERE p.status = 'em_andamento'
ORDER BY least(p.spi, p.cpi)
