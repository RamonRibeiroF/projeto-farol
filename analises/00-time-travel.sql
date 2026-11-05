-- ============================================
-- TIME TRAVEL — errei, e agora?
-- ============================================
-- Conceito: toda tabela Delta guarda versões. DESCRIBE HISTORY, VERSION AS OF, RESTORE
-- Pergunta de negócio: alguém duplicou um projeto e a carteira do dono ficou errada. Dá para voltar?
-- Conexão: a bronze não é "só um arquivo". Cada mudança vira uma versão, e nenhuma se perde.
--          Rode bloco a bloco (selecione o bloco e Ctrl+Enter), não tudo de uma vez.
--
-- A gente brinca numa CÓPIA do cadastro, para não mexer na bronze de verdade.

-- 1. Uma cópia do cadastro de projetos. Ela nasce na versão 0.
DROP TABLE IF EXISTS lakehouse_vertice.bronze.projetos_copia;
CREATE TABLE lakehouse_vertice.bronze.projetos_copia AS
SELECT * FROM lakehouse_vertice.bronze.projetos;

-- 2. Como está hoje: 60 projetos, carteira de R$ 305,2 mi
SELECT COUNT(*)                                                 AS projetos,
       ROUND(SUM(CAST(valor_contrato AS DECIMAL(18,2))) / 1e6, 1) AS carteira_mi
FROM lakehouse_vertice.bronze.projetos_copia;

-- 3. O erro: alguém rodou a carga do PRJ-021 duas vezes. O projeto agora aparece duplicado.
INSERT INTO lakehouse_vertice.bronze.projetos_copia
SELECT * FROM lakehouse_vertice.bronze.projetos_copia
WHERE projeto_id = 'PRJ-021';

-- 4. O estrago: 61 projetos, e a carteira "cresceu" de R$ 305,2 mi para R$ 318,8 mi sem nenhum contrato novo
SELECT COUNT(*)                                                 AS projetos,
       ROUND(SUM(CAST(valor_contrato AS DECIMAL(18,2))) / 1e6, 1) AS carteira_mi
FROM lakehouse_vertice.bronze.projetos_copia;

-- 5. O histórico: cada linha é uma versão. Versão 0 = a cópia; versão 1 = o INSERT errado.
--    Repare nas colunas operation (CREATE TABLE AS SELECT, WRITE) e operationMetrics (numOutputRows: 1).
DESCRIBE HISTORY lakehouse_vertice.bronze.projetos_copia;

-- 6. A viagem no tempo: a tabela como ela era ANTES do erro. Sem restaurar nada, só olhando.
SELECT COUNT(*)                                                 AS projetos,
       ROUND(SUM(CAST(valor_contrato AS DECIMAL(18,2))) / 1e6, 1) AS carteira_mi
FROM lakehouse_vertice.bronze.projetos_copia VERSION AS OF 0;

-- 7. Volta para a versão 0 de verdade.
RESTORE TABLE lakehouse_vertice.bronze.projetos_copia TO VERSION AS OF 0;

-- 8. Conferindo: 60 projetos de novo. E o histórico ganhou mais uma linha (RESTORE):
--    voltar no tempo também fica registrado.
SELECT COUNT(*)                                                 AS projetos,
       ROUND(SUM(CAST(valor_contrato AS DECIMAL(18,2))) / 1e6, 1) AS carteira_mi
FROM lakehouse_vertice.bronze.projetos_copia;

DESCRIBE HISTORY lakehouse_vertice.bronze.projetos_copia;

-- 9. Arrumando a casa: a cópia não faz parte da bronze. (Antes de apagar, dá uma olhada
--    na aba History dela no Catalog: é o mesmo histórico, pela interface.)
DROP TABLE lakehouse_vertice.bronze.projetos_copia;
