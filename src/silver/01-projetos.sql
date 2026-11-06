-- silver.projetos: o cadastro do PMO, limpo e tipado.
-- É o de-para da integração: diz em qual ferramenta cada projeto vive (ferramenta) e com qual
-- código ele aparece lá (codigo_ferramenta: nome do arquivo no Excel e no MS Project, list_id no ClickUp).

CREATE OR REFRESH MATERIALIZED VIEW projetos (
    CONSTRAINT data_inicio_preenchida EXPECT (data_inicio IS NOT NULL) ON VIOLATION FAIL UPDATE,
    CONSTRAINT ferramenta_conhecida   EXPECT (ferramenta IN ('excel', 'clickup', 'msproject')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Cadastro dos 60 projetos do PMO: cliente, segmento, contrato, orçamento, prazo, gerente e a ferramenta onde o cronograma vive (excel, clickup ou msproject) com o código do projeto nela.'
AS
SELECT projeto_id,
       nome_projeto,
       cliente,
       segmento,
       tipo_projeto,
       -- a ferramenta chega escrita de 8 jeitos ('ClickUp', 'Clickup', 'MS Project', 'Project', 'Planilha'...)
       CASE WHEN lower(ferramenta) LIKE '%click%'   THEN 'clickup'
            WHEN lower(ferramenta) LIKE '%project%' THEN 'msproject'
            WHEN lower(ferramenta) LIKE '%excel%' OR lower(ferramenta) LIKE '%planilha%' THEN 'excel'
       END                                            AS ferramenta,
       ferramenta                                     AS ferramenta_como_veio,
       nullif(trim(codigo_ferramenta), '')            AS codigo_ferramenta,
       CAST(valor_contrato  AS DECIMAL(18,2))         AS valor_contrato,
       CAST(orcamento_custo AS DECIMAL(18,2))         AS orcamento_custo,
       -- data em dois formatos: 2025-02-10 e 09/01/2025
       coalesce(try_to_date(data_inicio, 'yyyy-MM-dd'),
                try_to_date(data_inicio, 'dd/MM/yyyy')) AS data_inicio,
       to_date(data_fim_baseline)                     AS data_fim_baseline,
       status,
       gerente_projeto
FROM lakehouse_vertice.bronze.projetos;
