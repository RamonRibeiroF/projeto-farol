-- silver.status_semanal e silver.custos.

-- status_semanal: o farol que o gerente publica toda sexta.
-- O texto vazio ('', 'N/A', 'ver ata da reunião') NÃO sai: vira a flag status_vazio.
CREATE OR REFRESH MATERIALIZED VIEW status_semanal (
    CONSTRAINT farol_conhecido EXPECT (farol IN ('verde', 'amarelo', 'vermelho')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Status semanal de cada projeto (toda sexta): % concluído informado, farol do gerente (verde, amarelo, vermelho) e o texto livre com entregas e bloqueios. status_vazio marca o status sem conteúdo.'
AS
SELECT projeto_id,
       to_date(data_status)          AS data_status,
       gerente,
       lower(trim(farol))            AS farol,
       CAST(pct_concluido AS INT)    AS pct_concluido,
       texto_status,
       coalesce(trim(texto_status), '') IN ('', 'N/A', 'ver ata da reunião') AS status_vazio
FROM lakehouse_vertice.bronze.status_semanal;

-- custos: cada lançamento de custo real.
-- 671 valores com vírgula decimal: replace ANTES do CAST (try_cast jogaria R$ 5,4 mi fora em silêncio).
-- Estorno (valor negativo) FICA: o custo é líquido.
CREATE OR REFRESH MATERIALIZED VIEW custos
COMMENT 'Lançamentos de custo real por projeto (pessoal, consultoria, cloud, licenças, despesas), em reais. Estornos ficam como valor negativo (flag estorno). semana = sexta da semana do lançamento.'
AS
SELECT lancamento_id,
       projeto_id,
       to_date(data)                                        AS data,
       to_date(date_add(date_trunc('WEEK', to_date(data)), 4)) AS semana,
       categoria,
       descricao,
       CAST(replace(valor, ',', '.') AS DECIMAL(18,2))      AS valor,
       CAST(replace(valor, ',', '.') AS DECIMAL(18,2)) < 0  AS estorno,
       centro_custo
FROM lakehouse_vertice.bronze.custos;
