-- gold.status_estruturado: o texto livre do status semanal vira coluna (sql_task, depois do medalhão).
-- A tabela ACUMULA: CREATE TABLE IF NOT EXISTS + MERGE só com os status que ainda não estão nela,
-- para a IA nunca ser refeita. Cada status cai num de três métodos:
--   regra         status vazio ou "sem bloqueios": não precisa ler nada
--   ia            últimos 90 dias (data_status >= 2026-07-18) com bloqueio: ai_classify + ai_extract (versão 2.0)
--   palavra_chave o histórico com bloqueio: RLIKE por causa e regex no impacto
-- Por último um SELECT de leitura, porque a saída da sql_task mostra só o último SELECT.

CREATE TABLE IF NOT EXISTS lakehouse_vertice.gold.status_estruturado (
    projeto_id       STRING    COMMENT 'Projeto (PRJ-xxx)',
    data_status      DATE      COMMENT 'Sexta do status semanal',
    farol            STRING    COMMENT 'Farol informado pelo gerente: verde, amarelo ou vermelho',
    causa_bloqueio   STRING    COMMENT 'Causa do bloqueio: change_freeze, falta_sre, dependencia_fornecedor, rotatividade, mudanca_escopo, bug_retrabalho, aprovacao_cliente, sem_bloqueio, nao_reportado (status vazio) ou nao_classificado',
    bloqueio         STRING    COMMENT 'O bloqueio em poucas palavras (só no método ia)',
    quem_destrava    STRING    COMMENT 'Quem pode destravar o bloqueio, se o texto disser (só no método ia)',
    dias_impacto     DOUBLE    COMMENT 'Dias de impacto estimado no cronograma (1 semana = 7); nulo se o texto não estima',
    metodo           STRING    COMMENT 'Como a linha foi classificada: regra, ia ou palavra_chave',
    texto_status     STRING    COMMENT 'Texto livre do status, como o gerente escreveu',
    _classificado_em TIMESTAMP COMMENT 'Quando a linha foi classificada e inserida'
)
COMMENT 'Status semanal estruturado: causa do bloqueio, quem destrava e dias de impacto, lidos do texto livre. Incremental (MERGE): só status novos entram; IA só nos últimos 90 dias com bloqueio.';

-- os status que ainda não estão na tabela, já com o método decidido
CREATE OR REPLACE TEMPORARY VIEW status_novos AS
SELECT s.projeto_id,
       s.data_status,
       s.farol,
       s.texto_status,
       s.status_vazio,
       lower(coalesce(s.texto_status, '')) AS txt,
       CASE
           WHEN s.status_vazio
             OR lower(s.texto_status) LIKE '%bloqueios: nenhum%'
             OR lower(s.texto_status) LIKE '%sem bloqueios%'
             OR lower(s.texto_status) LIKE '%nada relevante%' THEN 'regra'
           WHEN s.data_status >= DATE'2026-07-18'                 THEN 'ia'
           ELSE 'palavra_chave'
       END AS metodo
FROM lakehouse_vertice.silver.status_semanal s
LEFT ANTI JOIN lakehouse_vertice.gold.status_estruturado e
  ON e.projeto_id = s.projeto_id AND e.data_status = s.data_status;

-- a IA roda SÓ nas linhas do método ia (CTE próprio, não um CASE sobre todas as linhas)
CREATE OR REPLACE TEMPORARY VIEW status_classificado AS
WITH chamada_ia AS (
    SELECT *,
           ai_classify(texto_status,
               '["change_freeze","falta_sre","dependencia_fornecedor","rotatividade","mudanca_escopo","bug_retrabalho","aprovacao_cliente","sem_bloqueio"]',
               map('version', '2.0')) AS classificacao,
           ai_extract(texto_status,
               '{"bloqueio":{"type":"string"},"quem_destrava":{"type":"string"},"dias_impacto":{"type":"number","description":"1 semana = 7"}}',
               map('version', '2.0')) AS extracao
    FROM status_novos
    WHERE metodo = 'ia'
),
com_ia AS (
    SELECT projeto_id, data_status, farol,
           classificacao:response[0]::STRING        AS causa_bloqueio,
           extracao:response.bloqueio::STRING       AS bloqueio,
           extracao:response.quem_destrava::STRING  AS quem_destrava,
           extracao:response.dias_impacto::DOUBLE   AS dias_impacto,
           metodo, texto_status
    FROM chamada_ia
),
sem_ia AS (
    SELECT projeto_id, data_status, farol,
           CASE
               WHEN status_vazio                                                     THEN 'nao_reportado'
               WHEN metodo = 'regra'                                                 THEN 'sem_bloqueio'
               WHEN txt RLIKE 'freeze|congelamento|janela de deploy'                 THEN 'change_freeze'
               WHEN txt RLIKE 'sre|infraestrutura|ambiente de homologação'           THEN 'falta_sre'
               WHEN txt RLIKE 'forge|consultoria|fornecedor'                         THEN 'dependencia_fornecedor'
               WHEN txt RLIKE 'saída de|rotatividade|onboarding'                     THEN 'rotatividade'
               WHEN txt RLIKE 'escopo|change request|regra de negócio'               THEN 'mudanca_escopo'
               WHEN txt RLIKE 'bugs|regressão|refazendo'                             THEN 'bug_retrabalho'
               WHEN txt RLIKE 'aprovação do cliente|homologação do cliente'          THEN 'aprovacao_cliente'
               ELSE 'nao_classificado'
           END AS causa_bloqueio,
           CAST(NULL AS STRING) AS bloqueio,
           CAST(NULL AS STRING) AS quem_destrava,
           CASE
               WHEN txt RLIKE 'impacto estimado de [0-9]+ dias'
                   THEN CAST(regexp_extract(txt, 'impacto estimado de ([0-9]+) dias', 1) AS DOUBLE)
               WHEN txt LIKE '%impacto estimado: 1 semana%' THEN 7.0
           END AS dias_impacto,
           metodo, texto_status
    FROM status_novos
    WHERE metodo <> 'ia'
)
SELECT * FROM com_ia
UNION ALL
SELECT * FROM sem_ia;

MERGE INTO lakehouse_vertice.gold.status_estruturado AS alvo
USING status_classificado AS novo
   ON alvo.projeto_id = novo.projeto_id AND alvo.data_status = novo.data_status
WHEN NOT MATCHED THEN INSERT
    (projeto_id, data_status, farol, causa_bloqueio, bloqueio, quem_destrava, dias_impacto, metodo, texto_status, _classificado_em)
VALUES
    (novo.projeto_id, novo.data_status, novo.farol, novo.causa_bloqueio, novo.bloqueio, novo.quem_destrava,
     novo.dias_impacto, novo.metodo, novo.texto_status, current_timestamp());

-- leitura: quantos status por método e causa
SELECT metodo, causa_bloqueio, COUNT(*) AS status
FROM lakehouse_vertice.gold.status_estruturado
GROUP BY metodo, causa_bloqueio
ORDER BY metodo, status DESC;
