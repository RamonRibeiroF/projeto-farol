-- Dashboard de portfólio · dataset 1: "Projetos em andamento"
-- Cole em Dashboards → seu dashboard → aba Data → + Create from SQL.
-- Precisa da parte 5 de analises/01-sql-na-bronze.sql executada antes (ela cria a view bronze.rascunho_tarefas).

-- Tudo na bronze é texto e cada ferramenta tem seu formato: este painel lê o
-- rascunho_tarefas (parte 5 de analises/01-sql-na-bronze.sql), que empilha Excel, ClickUp e MS Project à mão.
-- É o imposto que a camada silver vai eliminar.
WITH v AS (
  SELECT projeto_id, max(ferramenta) AS ferramenta,
         SUM(horas) AS horas_totais,
         SUM(horas * pct_concluido / 100) AS horas_agregadas,
         SUM(horas * GREATEST(0, LEAST(1, datediff(DATE'2026-10-16', inicio_baseline)
                  / datediff(fim_baseline, inicio_baseline)))) AS horas_planejadas
  FROM lakehouse_vertice.bronze.rascunho_tarefas
  GROUP BY projeto_id
),
c AS (SELECT projeto_id, SUM(CAST(replace(valor, ',', '.') AS DECIMAL(18,2))) AS ac FROM lakehouse_vertice.bronze.custos GROUP BY projeto_id),
f AS (SELECT projeto_id, lower(farol) AS farol FROM lakehouse_vertice.bronze.status_semanal WHERE data_status = '2026-10-16'),
o AS (
  SELECT p.projeto_id, concat(p.projeto_id, ' · ', p.nome_projeto) AS projeto, p.cliente, p.segmento,
         v.ferramenta, f.farol,
         CAST(p.valor_contrato AS DECIMAL(18,2)) AS valor_contrato,
         CAST(p.orcamento_custo AS DECIMAL(18,2)) AS orcamento,
         datediff(CAST(p.data_fim_baseline AS DATE),
                  coalesce(try_to_date(p.data_inicio, 'yyyy-MM-dd'), try_to_date(p.data_inicio, 'dd/MM/yyyy'))) AS duracao,
         v.horas_agregadas / v.horas_planejadas AS spi,
         CAST(p.orcamento_custo AS DECIMAL(18,2)) * v.horas_agregadas / v.horas_totais / c.ac AS cpi
  FROM lakehouse_vertice.bronze.projetos p JOIN v USING (projeto_id) JOIN c USING (projeto_id) LEFT JOIN f USING (projeto_id)
  WHERE p.status = 'em_andamento'
)
SELECT projeto_id, projeto, cliente, segmento, ferramenta, farol, valor_contrato, orcamento,
       ROUND(spi, 2) AS spi,
       ROUND(cpi, 2) AS cpi,
       CASE WHEN LEAST(spi, cpi) < 0.8 THEN 'crítico'
            WHEN LEAST(spi, cpi) < 0.9 THEN 'atenção' ELSE 'ok' END AS situacao,
       CASE WHEN LEAST(spi, cpi) < 0.8 THEN 1 ELSE 0 END AS critico,
       CASE WHEN LEAST(spi, cpi) < 0.9 THEN 1 ELSE 0 END AS em_risco,
       CASE WHEN farol = 'verde' AND spi < 0.9 THEN 1 ELSE 0 END AS melancia,
       GREATEST(0, orcamento / cpi - orcamento) AS estouro_previsto,
       (valor_contrato - orcamento / cpi) / valor_contrato AS margem_projetada,
       ROUND(duracao / spi - duracao) AS atraso_projetado_dias
FROM o
ORDER BY LEAST(spi, cpi)
