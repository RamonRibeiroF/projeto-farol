-- gold.projeto_situacao_atual e gold.utilizacao_pessoa_semana.
-- Não há dim_projeto: o cadastro já vem na projeto_situacao_atual.
-- Não há gold de fornecedor: lê-se direto silver.entregas_fornecedor.

-- projeto_situacao_atual: a fotografia de hoje (2026-10-16), uma linha por projeto.
-- Os KPIs saem do % das ferramentas (silver.tarefas), não do % que o gerente informa.
CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.projeto_situacao_atual (
    CONSTRAINT projeto_preenchido  EXPECT (projeto_id IS NOT NULL) ON VIOLATION FAIL UPDATE,
    CONSTRAINT situacao_calculada  EXPECT (situacao IS NOT NULL)   ON VIOLATION FAIL UPDATE
)
COMMENT 'Fotografia de 2026-10-16 dos 60 projetos: cadastro do PMO e os KPIs calculados sobre o cronograma das ferramentas (PV, EV, AC, SPI, CPI, EAC, estouro previsto, margem projetada, atraso e término projetados), a situação pela regra de corte (crítico < 0,8; atenção < 0,9), o farol do gerente, o farol calculado pelo SPI (verde >= 0,95; amarelo >= 0,90) e a flag melancia.'
AS
WITH cronograma AS (
    SELECT projeto_id,
           SUM(horas)                                   AS horas_totais,
           SUM(horas * pct_concluido / 100)             AS horas_agregadas,
           SUM(horas * greatest(0, least(1, datediff(DATE'2026-10-16', inicio_baseline)
                                            / datediff(fim_baseline, inicio_baseline)))) AS horas_planejadas
    FROM tarefas
    GROUP BY projeto_id
),
custo AS (
    SELECT projeto_id, SUM(valor) AS ac
    FROM custos
    WHERE data <= DATE'2026-10-16'
    GROUP BY projeto_id
),
farol_de_hoje AS (
    SELECT projeto_id, farol
    FROM status_semanal
    WHERE data_status = DATE'2026-10-16'
),
base AS (
    SELECT p.projeto_id,
           concat(p.projeto_id, ' · ', p.nome_projeto)        AS projeto,
           p.nome_projeto,
           p.cliente,
           p.segmento,
           p.tipo_projeto,
           p.ferramenta,
           p.gerente_projeto,
           p.valor_contrato,
           p.orcamento_custo                                  AS orcamento,
           p.data_inicio,
           p.data_fim_baseline,
           datediff(p.data_fim_baseline, p.data_inicio)       AS duracao_baseline_dias,
           p.status,
           p.orcamento_custo * c.horas_planejadas / c.horas_totais AS pv,
           p.orcamento_custo * c.horas_agregadas  / c.horas_totais AS ev,
           coalesce(cu.ac, 0)                                 AS ac,
           f.farol                                            AS farol_do_gerente
    FROM projetos p
    LEFT JOIN cronograma    c  ON c.projeto_id  = p.projeto_id
    LEFT JOIN custo         cu ON cu.projeto_id = p.projeto_id
    LEFT JOIN farol_de_hoje f  ON f.projeto_id  = p.projeto_id
),
indices AS (
    SELECT *,
           round(try_divide(ev, pv), 4) AS spi,
           round(try_divide(ev, ac), 4) AS cpi
    FROM base
),
projecoes AS (
    SELECT *,
           try_divide(orcamento, cpi)                                       AS eac_bruto,
           round(try_divide(duracao_baseline_dias, spi))                    AS duracao_projetada_dias
    FROM indices
)
SELECT projeto_id,
       projeto,
       nome_projeto,
       cliente,
       segmento,
       tipo_projeto,
       ferramenta,
       gerente_projeto,
       valor_contrato,
       orcamento,
       data_inicio,
       data_fim_baseline,
       duracao_baseline_dias,
       status,
       CAST(pv AS DECIMAL(18,2))                                            AS pv,
       CAST(ev AS DECIMAL(18,2))                                            AS ev,
       CAST(ac AS DECIMAL(18,2))                                            AS ac,
       spi,
       cpi,
       CAST(eac_bruto AS DECIMAL(18,2))                                     AS eac,
       CAST(greatest(eac_bruto - orcamento, 0) AS DECIMAL(18,2))            AS estouro_previsto,
       round(try_divide(valor_contrato - eac_bruto, valor_contrato), 4)     AS margem_projetada,
       CAST(duracao_projetada_dias - duracao_baseline_dias AS INT)          AS atraso_projetado_dias,
       date_add(data_inicio, CAST(duracao_projetada_dias AS INT))           AS termino_projetado,
       CASE WHEN status <> 'em_andamento'  THEN 'concluído'
            WHEN least(spi, cpi) < 0.8     THEN 'crítico'
            WHEN least(spi, cpi) < 0.9     THEN 'atenção'
            ELSE 'ok' END                                                   AS situacao,
       farol_do_gerente,
       CASE WHEN spi >= 0.95 THEN 'verde'
            WHEN spi >= 0.90 THEN 'amarelo'
            ELSE 'vermelho' END                                             AS farol_calculado,
       coalesce(status = 'em_andamento' AND farol_do_gerente = 'verde' AND spi < 0.9, false) AS melancia
FROM projecoes;

-- utilizacao_pessoa_semana: pessoa × projeto × semana, com o custo de quem ficou parado
-- e o SPI do projeto naquela semana (para ver gente ociosa em projeto que atrasa).
CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.utilizacao_pessoa_semana
COMMENT 'Timesheet por pessoa, projeto e semana (sexta): nome, papel, senioridade, horas disponíveis, apontadas e ociosas, utilização (apontadas ÷ disponíveis), custo ocioso (horas ociosas × custo/hora) e o SPI do projeto naquela semana.'
AS
SELECT a.colaborador_id,
       c.nome,
       c.papel,
       c.senioridade,
       a.projeto_id,
       a.semana,
       a.horas_disponiveis,
       a.horas_apontadas,
       greatest(a.horas_disponiveis - a.horas_apontadas, 0)                       AS horas_ociosas,
       round(try_divide(a.horas_apontadas, a.horas_disponiveis), 4)               AS utilizacao,
       c.custo_hora,
       CAST(greatest(a.horas_disponiveis - a.horas_apontadas, 0) * c.custo_hora AS DECIMAL(18,2)) AS custo_ocioso,
       f.spi                                                                      AS spi_do_projeto
FROM apontamentos a
LEFT JOIN colaboradores c ON c.colaborador_id = a.colaborador_id
LEFT JOIN lakehouse_vertice.gold.fato_projeto_semana f
  ON f.projeto_id = a.projeto_id AND f.semana = a.semana;
