-- gold.mv_projetos: a fórmula de cada KPI da carteira num lugar só (metric view, YAML 1.1).
-- Fonte: gold.projeto_situacao_atual, só os projetos em andamento. "Hoje" = 2026-10-16.
-- Razão é sempre SUM/SUM (SPI, CPI, margem), nunca média de razão.
-- Atenção: NENHUM ponto e vírgula dentro do YAML (nem em comment). A sql_task corta o arquivo em todo
-- ponto e vírgula, inclusive dentro do bloco $$. Teste com tools/run_sql.py, que preserva a indentação.
-- O "nunca CREATE OR REPLACE" do projeto vale para as materialized views do pipeline, não para esta view.

CREATE OR REPLACE VIEW lakehouse_vertice.gold.mv_projetos
WITH METRICS
LANGUAGE YAML
AS $$
version: 1.1
comment: "KPIs da carteira de projetos em andamento da Vértice Tecnologia em 16/10/2026: SPI, CPI, EAC, estouro previsto, margem projetada e contagem de projetos em risco, críticos e melancia."
source: lakehouse_vertice.gold.projeto_situacao_atual
filter: status = 'em_andamento'

dimensions:
  - name: projeto_id
    expr: projeto_id
    comment: "Código do projeto, no formato PRJ-xxx"
    synonyms: [código do projeto, id do projeto]
  - name: projeto
    expr: projeto
    comment: "Código e nome do projeto juntos (PRJ-xxx · nome)"
    synonyms: [nome do projeto, obra]
  - name: cliente
    expr: cliente
    synonyms: [empresa cliente, conta]
  - name: segmento
    expr: segmento
    comment: "Segmento do cliente: varejo, financeiro, saude, logistica ou industria"
    synonyms: [setor, vertical, mercado]
  - name: ferramenta
    expr: ferramenta
    comment: "Onde o gerente controla o cronograma: excel, clickup ou msproject"
    synonyms: [sistema de gestão, planilha]
  - name: situacao
    expr: situacao
    comment: "Situação pela regra de corte: crítico se SPI ou CPI < 0,8, atenção se < 0,9, senão ok"
    synonyms: [status de risco, classificação, risco]
  - name: farol_do_gerente
    expr: farol_do_gerente
    comment: "Farol informado pelo gerente no status de 16/10/2026: verde, amarelo ou vermelho"
    synonyms: [farol informado, farol do status, semáforo do gerente]
  - name: farol_calculado
    expr: farol_calculado
    comment: "Farol pelo número: verde se SPI >= 0,95, amarelo se >= 0,90, senão vermelho"
    synonyms: [farol real, farol pelo SPI]
  - name: gerente_projeto
    expr: gerente_projeto
    synonyms: [gerente, gestor do projeto, GP]

measures:
  - name: projetos
    expr: COUNT(1)
    comment: "Quantidade de projetos em andamento"
    synonyms: [quantidade de projetos, número de projetos]
  - name: carteira
    expr: SUM(valor_contrato)
    comment: "Soma do valor de contrato, em reais"
    synonyms: [valor da carteira, receita contratada, valor de contrato]
    format:
      type: currency
      currency_code: BRL
  - name: spi
    expr: SUM(ev) / SUM(pv)
    comment: "Índice de desempenho de prazo: valor agregado sobre valor planejado (SUM/SUM). Abaixo de 1 é atraso"
    synonyms: [índice de prazo, desempenho de prazo, schedule performance index]
  - name: cpi
    expr: SUM(ev) / SUM(ac)
    comment: "Índice de desempenho de custo: valor agregado sobre custo real (SUM/SUM). Abaixo de 1 é gastar mais do que entrega"
    synonyms: [índice de custo, desempenho de custo, cost performance index]
  - name: eac
    expr: SUM(eac)
    comment: "Estimativa no término: orçamento dividido pelo CPI de cada projeto, somado"
    synonyms: [custo final previsto, estimativa no término, estimate at completion]
    format:
      type: currency
      currency_code: BRL
  - name: estouro_previsto
    expr: SUM(estouro_previsto)
    comment: "Quanto o custo final previsto passa do orçamento (EAC menos orçamento, nunca negativo), em reais"
    synonyms: [estouro, custo do atraso, quanto vai custar, sobrecusto, prejuízo previsto]
    format:
      type: currency
      currency_code: BRL
  - name: margem_projetada
    expr: (SUM(valor_contrato) - SUM(eac)) / SUM(valor_contrato)
    comment: "Margem prevista no término: valor de contrato menos EAC, sobre o valor de contrato"
    synonyms: [margem, margem prevista, rentabilidade]
    format:
      type: percentage
  - name: atraso_projetado_medio_dias
    expr: AVG(atraso_projetado_dias)
    comment: "Média, entre os projetos, dos dias de atraso projetados no término (duração dividida pelo SPI menos a duração do baseline)"
    synonyms: [atraso médio, dias de atraso, atraso projetado]
  - name: projetos_em_risco
    expr: COUNT(1) FILTER (WHERE situacao IN ('atenção', 'crítico'))
    comment: "Projetos em atenção ou crítico"
    synonyms: [projetos em risco, projetos atrasados, projetos com problema]
  - name: projetos_criticos
    expr: COUNT(1) FILTER (WHERE situacao = 'crítico')
    comment: "Projetos com SPI ou CPI abaixo de 0,8"
    synonyms: [críticos, projetos críticos, projetos no vermelho]
  - name: projetos_melancia
    expr: COUNT(1) FILTER (WHERE melancia)
    comment: "Projetos melancia: farol do gerente verde, mas SPI abaixo de 0,9 (verde por fora, vermelho por dentro)"
    synonyms: [melancias, verde por fora, farol verde atrasado]
$$;

-- leitura: a carteira de hoje
SELECT MEASURE(projetos)                    AS projetos,
       ROUND(MEASURE(spi), 2)               AS spi,
       ROUND(MEASURE(cpi), 2)               AS cpi,
       ROUND(MEASURE(estouro_previsto), 2)  AS estouro_previsto,
       MEASURE(projetos_em_risco)           AS em_risco,
       MEASURE(projetos_criticos)           AS criticos,
       MEASURE(projetos_melancia)           AS melancias
FROM lakehouse_vertice.gold.mv_projetos;
