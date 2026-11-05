-- Dashboard de portfólio · dataset 2: "Custos por mês"
-- Cole em Dashboards → seu dashboard → aba Data → + Create from SQL.

SELECT date_trunc('MONTH', CAST(data AS DATE)) AS mes,
       categoria,
       CAST(replace(valor, ',', '.') AS DECIMAL(18,2)) AS valor
FROM lakehouse_vertice.bronze.custos
