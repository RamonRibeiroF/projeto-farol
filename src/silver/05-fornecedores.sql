-- silver.entregas_fornecedor: o que cada consultoria prometeu e quando entregou.
-- A CodeForge vem de 4 jeitos; normalizamos e guardamos o original.
-- data_entrega vazia = entrega em aberto (não é sujeira). "Hoje" = 2026-10-16.

CREATE OR REFRESH MATERIALIZED VIEW entregas_fornecedor
COMMENT 'Entregas das consultorias contratadas: prometido x entregue, prazos em dias, atraso na entrega e as entregas em aberto já vencidas (em_atraso, com hoje = 2026-10-16).'
AS
WITH base AS (
    SELECT entrega_id,
           projeto_id,
           CASE WHEN replace(lower(fornecedor), ' ', '') LIKE '%codeforge%'
                THEN 'CodeForge Consultoria Ltda' ELSE fornecedor END AS fornecedor,
           fornecedor                                   AS fornecedor_como_veio,
           item,
           CAST(valor AS DECIMAL(18,2))                 AS valor,
           to_date(data_pedido)                         AS data_pedido,
           to_date(data_prometida)                      AS data_prometida,
           to_date(nullif(trim(data_entrega), ''))      AS data_entrega,
           CAST(prazo_contratado_dias AS INT)           AS prazo_contratado_dias,
           status
    FROM lakehouse_vertice.bronze.entregas_fornecedor
)
SELECT *,
       datediff(data_prometida, data_pedido)                       AS prazo_prometido_dias,
       datediff(data_entrega, data_pedido)                         AS prazo_real_dias,
       greatest(datediff(data_entrega, data_prometida), 0)         AS dias_de_atraso_na_entrega,
       data_entrega IS NULL                                        AS em_aberto,
       data_entrega IS NULL AND data_prometida < DATE'2026-10-16'  AS em_atraso
FROM base;
