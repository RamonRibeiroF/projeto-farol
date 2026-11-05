-- Databricks notebook source

-- ##########################################################################
-- ANÁLISE EXPLORATÓRIA EM SQL NA CAMADA BRONZE (partes 1 a 5)
-- ##########################################################################
-- Execute de cima para baixo, uma célula por vez (Shift+Enter).
-- Cada bloco diz o que queremos achar, o que cada comando faz e o que deve aparecer.
--
--   PARTE 1  SELECT                      o que existe no catálogo?
--   PARTE 2  ORDER BY, CAST, DISTINCT    quais os maiores contratos?
--   PARTE 3  WHERE                       dá para confiar nesse número?
--   PARTE 4  GROUP BY                    para onde vai o dinheiro?
--   PARTE 5  UNION                       quais projetos estão mais atrasados? (pergunta 1)
--
-- Em seguida vem 02-custo-do-atraso.sql (pergunta 2), que usa a view criada na parte 5.
-- O nome completo de uma tabela tem 3 partes: catálogo.schema.tabela
--   lakehouse_vertice . bronze . projetos


-- ============================================
-- PARTE 1: SELECT — o que existe no catálogo?
-- ============================================
-- Conceito: SELECT, FROM, LIMIT, COUNT(*)
-- Pergunta de negócio: que projetos a Vértice tem, e onde cada um vive?
-- Conexão: antes de calcular qualquer coisa, olhe o dado. Sempre.

-- 1. A primeira olhada no cadastro de projetos do PMO.
--    SELECT *   traga todas as colunas
--    FROM ...   da tabela tal
--    LIMIT 10   só as 10 primeiras linhas
--    Resultado esperado: 10 projetos com cliente, valor do contrato, prazo e a coluna ferramenta
--    (Excel, ClickUp ou MS Project): é onde o cronograma de cada um vive. Repare que a
--    mesma ferramenta aparece escrita de jeitos diferentes. Volta na parte 2.
SELECT *
FROM lakehouse_vertice.bronze.projetos
LIMIT 10;

-- COMMAND ----------

-- 2. Quantos projetos a Vértice tem?
--    COUNT(*)   conta as linhas
--    AS nome    dá um nome para a coluna do resultado
--    Resultado esperado: 60.
SELECT COUNT(*) AS projetos
FROM lakehouse_vertice.bronze.projetos;

-- COMMAND ----------

-- ============================================
-- PARTE 2: ORDER BY, CAST e DISTINCT — os maiores contratos
-- ============================================
-- Conceito: ORDER BY, CAST, DISTINCT
-- Pergunta de negócio: quais são os maiores contratos da Vértice?
-- Conexão: na bronze tudo é texto. Sem CAST, o Databricks ordena como palavra.

-- 1. Os 5 maiores contratos... ou não.
--    ORDER BY coluna DESC   ordena do maior para o menor
--    Resultado esperado: uma lista que PARECE certa, com o PRJ-052 (R$ 8,4 mi) no topo. Está errada.
--    O valor é texto, e texto se ordena letra por letra: '8380000' vem antes de '15275000'
--    porque '8' vem depois de '1', como numa lista telefônica.
SELECT projeto_id, nome_projeto, valor_contrato
FROM lakehouse_vertice.bronze.projetos
ORDER BY valor_contrato DESC
LIMIT 5;

-- COMMAND ----------

-- 2. A correção: converter o texto em número antes de ordenar.
--    CAST(coluna AS DECIMAL(18,2))   transforma o texto em número com 2 casas decimais
--    Resultado esperado: o maior contrato de verdade é o PRJ-017, R$ 15,3 mi.
SELECT projeto_id, nome_projeto,
       CAST(valor_contrato AS DECIMAL(18,2)) AS valor_numero
FROM lakehouse_vertice.bronze.projetos
ORDER BY valor_numero DESC
LIMIT 5;

-- COMMAND ----------

-- 3. Em quais ferramentas os projetos vivem?
--    DISTINCT   tira as repetições: cada valor aparece uma vez só
--    Resultado esperado: 8 jeitos de escrever 3 ferramentas: 'Excel', 'excel', 'Planilha',
--    'ClickUp', 'Clickup', 'MS Project', 'Project', 'msproject'.
--    É o retrato do problema da Vértice: cada um registra do seu jeito.
SELECT DISTINCT ferramenta
FROM lakehouse_vertice.bronze.projetos
ORDER BY ferramenta;

-- COMMAND ----------

-- ============================================
-- PARTE 3: WHERE — filtrar, e achar a sujeira
-- ============================================
-- Conceito: WHERE, LIKE, AND, IN, IS NULL
-- Pergunta de negócio: dá para confiar nesse número?
-- Conexão: tudo que esta parte encontra é o que a camada silver corrige.
--
-- Dado sujo não dá erro: dá um número errado, em silêncio, e a diretoria decide em cima dele.
--
-- O WHERE vem depois do FROM e diz QUAIS linhas entram:
--   WHERE coluna = 'valor'      igual a
--   WHERE coluna LIKE '%/%'     "parece com". O % quer dizer "qualquer coisa aqui":
--                               '%/%' = tem uma barra em algum lugar

-- 1. A data de início em dois formatos na mesma coluna: 14/03/2025 e 2025-03-14.
--    Quantos projetos estão no formato com barra?
--    Resultado esperado: 24 (os outros 36 estão como 2025-03-14). Uma conta de prazo que só
--    entenda um dos formatos erra 24 projetos.
SELECT COUNT(*) AS formato_brasileiro
FROM lakehouse_vertice.bronze.projetos
WHERE data_inicio LIKE '%/%';

-- COMMAND ----------

-- 2. Excel: a linha de TOTAL que o gerente deixou no fim de cada planilha.
--    Resultado esperado: 20 linhas, uma por planilha. Quem soma a coluna de horas inteira
--    conta tudo duas vezes.
SELECT arquivo, tarefa, horas_previstas
FROM lakehouse_vertice.bronze.excel_tarefas
WHERE tarefa = 'TOTAL';

-- COMMAND ----------

-- 3. Financeiro: custo com vírgula decimal ('12345,67'). Para o computador, isso não é número.
--    Resultado esperado: 671 lançamentos. O parte 4 mostra o estrago.
SELECT COUNT(*) AS com_virgula
FROM lakehouse_vertice.bronze.custos
WHERE valor LIKE '%,%';

-- COMMAND ----------

-- 4. Combinar condições: projetos de VAREJO que estão EM ANDAMENTO.
--    AND   as duas condições precisam valer ao mesmo tempo
--    Resultado esperado: 14 projetos. Varejo é o segmento da Black Friday: o freeze de 01/11 a 10/01 trava os de e-commerce.
SELECT projeto_id, cliente, nome_projeto
FROM lakehouse_vertice.bronze.projetos
WHERE status = 'em_andamento'
  AND segmento = 'varejo';

-- COMMAND ----------

-- 5. Os projetos que vivem no Excel. Note que a ferramenta está escrita de 8 jeitos (parte 2).
--    IN (...)   "é um destes valores": vale como três igualdades ligadas por OR
--    Resultado esperado: 20 projetos. Com WHERE ferramenta = 'Excel' sairiam menos: os escritos
--    'excel' e 'Planilha' ficariam de fora, sem nenhum aviso.
SELECT projeto_id, cliente, ferramenta
FROM lakehouse_vertice.bronze.projetos
WHERE ferramenta IN ('Excel', 'excel', 'Planilha');

-- COMMAND ----------

-- 6. Projeto sem o código da ferramenta: ninguém sabe onde está o cronograma dele.
--    IS NULL   a coluna está vazia. Atenção: "= NULL" não funciona, nunca dá verdadeiro.
--    Resultado esperado: 2 projetos (PRJ-009 e PRJ-012).
SELECT projeto_id, nome_projeto, ferramenta, codigo_ferramenta
FROM lakehouse_vertice.bronze.projetos
WHERE codigo_ferramenta IS NULL;

-- COMMAND ----------

-- 7. A mesma consultoria digitada de vários jeitos em compras.
--    lower(...)   põe tudo em minúscula, para o LIKE achar 'Forge', 'FORGE' e 'forge'
--    Resultado esperado: 4 jeitos de escrever CodeForge. Quem soma "por fornecedor" acha 4 fornecedores.
SELECT DISTINCT fornecedor
FROM lakehouse_vertice.bronze.entregas_fornecedor
WHERE lower(fornecedor) LIKE '%forge%';

-- COMMAND ----------

-- ============================================
-- PARTE 4: GROUP BY — para onde vai o dinheiro da Vértice?
-- ============================================
-- Conceito: GROUP BY, SUM, replace
-- Pergunta de negócio: quanto a Vértice gasta, por categoria de custo?
-- Conexão: é a pergunta 2 do dono ("quanto custa?") começando a ter resposta.
--
-- A tabela é a bronze.custos: um lançamento de custo por linha (23.640 linhas).

-- 1. Quanto cada categoria gastou?
--    GROUP BY categoria   junta as linhas da mesma categoria e faz a conta dentro de cada grupo
--    SUM(...)             soma a coluna dentro do grupo
--    O valor é texto, então primeiro CAST para número (parte 2).
--    Resultado esperado: um ERRO. É de propósito: '1827,44' não vira número. É a vírgula da parte 3.
SELECT categoria,
       SUM(CAST(valor AS DECIMAL(18,2))) AS custo
FROM lakehouse_vertice.bronze.custos
GROUP BY categoria;

-- COMMAND ----------

-- 2. A correção: trocar a vírgula por ponto ANTES de converter.
--    replace(valor, ',', '.')   troca ',' por '.'
--    ROUND(x / 1000000, 1)      em milhões, com 1 casa decimal
--    Resultado esperado: pessoal no topo, com R$ 117,8 mi. Empresa de tecnologia gasta com gente:
--    quase dois terços dos R$ 193,35 mi de custo.
SELECT categoria,
       ROUND(SUM(CAST(replace(valor, ',', '.') AS DECIMAL(18,2))) / 1000000, 1) AS custo_milhoes
FROM lakehouse_vertice.bronze.custos
GROUP BY categoria
ORDER BY custo_milhoes DESC;

-- COMMAND ----------

-- ============================================
-- PARTE 5: UNION — as três ferramentas numa fila só
-- ============================================
-- Conceito: UNION ALL, VIEW, CASE, JOIN, WITH
-- Pergunta de negócio: QUAIS PROJETOS ESTÃO MAIS ATRASADOS?
--
-- É a primeira pergunta do dono, e ninguém na Vértice sabia responder: 20 projetos estão
-- no Excel, 25 no ClickUp e 15 no MS Project. Cada ferramenta guarda a mesma informação
-- (a tarefa, quando devia começar e terminar, quanto está pronta, quantas horas) de um jeito.
--
-- O plano, em 5 degraus:
--   bloco 1   o UNION ALL no menor exemplo possível
--   bloco 2   traduzir UMA ferramenta (o Excel) para as 7 colunas
--   bloco 3   as três traduzidas e empilhadas numa view: o rascunho
--   bloco 4   somar as horas: quanto está pronto e quanto devia estar
--   bloco 5   dividir uma pela outra (o SPI) e dar a resposta ao dono
-- É um RASCUNHO feito à mão: na camada silver isso vira pipeline de verdade.
--
-- O "hoje" do dataset é 16/10/2026: nunca use current_date() aqui,
-- senão o resultado muda todo dia e deixa de ser reproduzível.

-- 1. O UNION ALL, no menor exemplo possível.
--    UNION ALL   empilha o resultado de uma consulta embaixo da outra.
--                Regra: todas com as mesmas colunas, na mesma ordem.
--    Resultado esperado: 3 linhas, uma por ferramenta, com quantas linhas cada uma tem.
--    É essa a ideia da parte inteira. O resto é fazer as três ferramentas
--    terem as mesmas colunas, para poder empilhar.
SELECT 'excel'     AS ferramenta, COUNT(*) AS linhas FROM lakehouse_vertice.bronze.excel_tarefas
UNION ALL
SELECT 'clickup'   AS ferramenta, COUNT(*) AS linhas FROM lakehouse_vertice.bronze.clickup_tarefas
UNION ALL
SELECT 'msproject' AS ferramenta, COUNT(*) AS linhas FROM lakehouse_vertice.bronze.msproject_tarefas;

-- COMMAND ----------

-- 2. Traduzir UMA ferramenta: o Excel nas 7 colunas.
--
--    O QUE A GENTE QUER: que cada linha da planilha vire uma tarefa "limpa", com as mesmas
--    7 colunas que o ClickUp e o MS Project vão ter. Só assim dá para empilhar (bloco 1).
--      projeto_id · ferramenta · tarefa · inicio_baseline · fim_baseline · pct_concluido · horas
--      (baseline = o plano original: quando a tarefa DEVIA começar e terminar)
--
--    O QUE ATRAPALHA (visto nas partes 1 e 3):
--      · a planilha não tem coluna de projeto: o PRJ-xxx está no nome do arquivo
--      · a data vem de dois jeitos: '06/03/2025' ou 45700 (número de série do Excel,
--        que conta os dias desde 30/12/1899)
--      · o % vem de dois jeitos: '45%' (às vezes '64,4%', com vírgula) ou 0.45; e tem % acima de 100
--      · as horas vêm como texto, às vezes com 'h' ('64h')
--      · a última linha de cada planilha é o TOTAL
--
--    O COMANDO NOVO: CASE WHEN condição THEN isto ELSE aquilo END, o "se" do SQL.
--      Ele resolve os dois jeitos: SE tem barra, lê como data; SENÃO, é número de série.
--
--    --    Resultado esperado: datas de verdade (mesmo onde a planilha tinha 45700) e % de 0 a 100.
SELECT -- o projeto está no nome do arquivo: 'Cronograma PRJ-002.xlsx' → pega "PRJ-" + 3 dígitos
       regexp_extract(arquivo, 'PRJ-[0-9]{3}', 0)                         AS projeto_id,
       'excel'                                                            AS ferramenta,
       tarefa,
       -- data com barra ('06/03/2025') → lê como dd/MM/yyyy;
       -- senão é o número de série do Excel (45700 = dias contados desde 30/12/1899)
       CASE WHEN inicio_previsto LIKE '%/%' THEN to_date(inicio_previsto, 'dd/MM/yyyy')
            ELSE date_add(DATE'1899-12-30', CAST(inicio_previsto AS INT)) END   AS inicio_baseline,
       CASE WHEN termino_previsto LIKE '%/%' THEN to_date(termino_previsto, 'dd/MM/yyyy')
            ELSE date_add(DATE'1899-12-30', CAST(termino_previsto AS INT)) END  AS fim_baseline,
       -- '45%' ou '64,4%' → 45 e 64.4;  0.45 → 45;  e LEAST corta quem passou de 100
       LEAST(100, CASE WHEN pct_concluido LIKE '%\%%'
                       THEN CAST(replace(replace(pct_concluido, '%', ''), ',', '.') AS DOUBLE)
                       ELSE CAST(pct_concluido AS DOUBLE) * 100 END)      AS pct_concluido,
       CAST(replace(horas_previstas, 'h', '') AS DOUBLE)                  AS horas
FROM lakehouse_vertice.bronze.excel_tarefas
WHERE tarefa <> 'TOTAL'                     -- fora a linha de TOTAL (parte 3)
LIMIT 10;

-- COMMAND ----------

-- 3. O rascunho: as três ferramentas traduzidas e empilhadas, guardadas numa view.
--    CREATE OR REPLACE VIEW nome AS ...   guarda a consulta com um nome. Não copia o dado:
--                                         toda vez que alguém lê a view, a consulta roda de novo.
--    O Excel é o bloco 2. O ClickUp e o MS Project fazem a mesma tradução, cada um com o seu
--    problema (explicado no comentário de cada parte). Entre eles, o UNION ALL do bloco 1.
--    Resultado esperado: OK. A view bronze.rascunho_tarefas aparece no Catalog.
CREATE OR REPLACE VIEW lakehouse_vertice.bronze.rascunho_tarefas
COMMENT 'Rascunho: tarefas do Excel, ClickUp e MS Project empilhadas à mão. Na camada silver vira silver.tarefas.'
AS
-- ---------- EXCEL ----------
SELECT -- o projeto está no nome do arquivo: 'Cronograma PRJ-002.xlsx' → pega "PRJ-" + 3 dígitos
       regexp_extract(arquivo, 'PRJ-[0-9]{3}', 0)                         AS projeto_id,
       'excel'                                                            AS ferramenta,
       tarefa,
       -- data com barra ('06/03/2025') → lê como dd/MM/yyyy;
       -- senão é o número de série do Excel (45700 = dias contados desde 30/12/1899)
       CASE WHEN inicio_previsto LIKE '%/%' THEN to_date(inicio_previsto, 'dd/MM/yyyy')
            ELSE date_add(DATE'1899-12-30', CAST(inicio_previsto AS INT)) END   AS inicio_baseline,
       CASE WHEN termino_previsto LIKE '%/%' THEN to_date(termino_previsto, 'dd/MM/yyyy')
            ELSE date_add(DATE'1899-12-30', CAST(termino_previsto AS INT)) END  AS fim_baseline,
       -- '45%' ou '64,4%' → 45 e 64.4;  0.45 → 45;  e LEAST corta quem passou de 100
       LEAST(100, CASE WHEN pct_concluido LIKE '%\%%'
                       THEN CAST(replace(replace(pct_concluido, '%', ''), ',', '.') AS DOUBLE)
                       ELSE CAST(pct_concluido AS DOUBLE) * 100 END)      AS pct_concluido,
       CAST(replace(horas_previstas, 'h', '') AS DOUBLE)                  AS horas
FROM lakehouse_vertice.bronze.excel_tarefas
WHERE tarefa <> 'TOTAL'                     -- fora a linha de TOTAL (parte 3)

UNION ALL
-- ---------- CLICKUP ----------
-- O ClickUp não sabe o que é PRJ-xxx. O cadastro do PMO sabe: guarda o código da lista do ClickUp.
-- O JOIN junta as duas tabelas (c = clickup, p = projetos); o OR casa pelo nome quando falta o código.
-- O % e as datas da baseline estão escondidos numa lista de campos personalizados: o filter()
-- procura o campo pelo nome. As datas e as horas vêm em milissegundos.
SELECT p.projeto_id,
       'clickup',
       c.name,
       to_date(timestamp_millis(CAST(filter(c.custom_fields, f -> f.name = 'Início baseline')[0].value AS BIGINT))),
       to_date(timestamp_millis(CAST(filter(c.custom_fields, f -> f.name = 'Fim baseline')[0].value AS BIGINT))),
       CAST(filter(c.custom_fields, f -> f.name = 'Progresso (%)')[0].value AS DOUBLE),
       c.time_estimate / 3600000                                           -- milissegundos → horas
FROM lakehouse_vertice.bronze.clickup_tarefas c
JOIN lakehouse_vertice.bronze.projetos p
  ON p.codigo_ferramenta = c.list_id OR p.nome_projeto = c.list_name

UNION ALL
-- ---------- MS PROJECT ----------
-- As datas da baseline estão dentro da "caixinha" Baseline; as horas vêm como 'PT40H0M0S' (→ 40).
-- Summary = 0: só as tarefas de verdade. A tarefa-resumo (a fase) soma as de baixo e contaria duas vezes.
SELECT regexp_extract(arquivo, 'PRJ-[0-9]{3}', 0),
       'msproject',
       Name,
       to_date(Baseline.Start),
       to_date(Baseline.Finish),
       CAST(PercentComplete AS DOUBLE),
       CAST(regexp_extract(Work, 'PT([0-9]+)H', 1) AS DOUBLE)
FROM lakehouse_vertice.bronze.msproject_tarefas
WHERE Summary = 0;

-- COMMAND ----------

-- 4. Com tudo numa fila só, as horas de cada projeto.
--    horas agregadas  = quanto ESTÁ pronto:        horas da tarefa × % concluído
--    horas planejadas = quanto DEVIA estar pronto:  horas da tarefa × quanto do prazo da tarefa
--                                                   já passou até hoje (de 0 a 1)
--    datediff(fim, inicio)      dias entre duas datas
--    GREATEST(0, LEAST(1, x))   prende x entre 0 e 1: tarefa que nem começou = 0; que já devia ter acabado = 1
--    Resultado esperado: dois números por projeto. Onde o primeiro é bem menor que o segundo, atrasou.
SELECT projeto_id,
       ferramenta,
       ROUND(SUM(horas * pct_concluido / 100)) AS horas_agregadas,
       ROUND(SUM(horas * GREATEST(0, LEAST(1,
           datediff(DATE'2026-10-16', inicio_baseline) / datediff(fim_baseline, inicio_baseline)
       ))))                                     AS horas_planejadas
FROM lakehouse_vertice.bronze.rascunho_tarefas
GROUP BY projeto_id, ferramenta
ORDER BY projeto_id;

-- COMMAND ----------

-- 5. A resposta para o dono: o SPI de cada projeto em andamento.
--    SPI = agregadas ÷ planejadas      abaixo de 1 é atraso (0,80 = andou 80% do que devia)
--    Regra da Torre: abaixo de 0,9 = atenção; abaixo de 0,8 = crítico.
--
--    WITH valor AS (...)          dá um nome à consulta do bloco 4 e usa embaixo, como se fosse
--                                 uma tabela: primeiro soma, depois divide
--    JOIN ... USING (projeto_id)  junta com o cadastro, para trazer o cliente e o status
--    Resultado esperado: 41 projetos em andamento. No topo, PRJ-016 (0,63), PRJ-030 (0,69),
--    PRJ-039 (0,75) e PRJ-011 (0,77). A resposta da pergunta 1.
WITH valor AS (
    SELECT projeto_id,
           ferramenta,
           SUM(horas * pct_concluido / 100) AS horas_agregadas,
           SUM(horas * GREATEST(0, LEAST(1,
               datediff(DATE'2026-10-16', inicio_baseline) / datediff(fim_baseline, inicio_baseline)
           )))                               AS horas_planejadas
    FROM lakehouse_vertice.bronze.rascunho_tarefas
    GROUP BY projeto_id, ferramenta
)
SELECT p.projeto_id,
       p.cliente,
       v.ferramenta,
       ROUND(v.horas_agregadas / v.horas_planejadas, 2) AS spi,
       CASE WHEN v.horas_agregadas / v.horas_planejadas < 0.8 THEN 'crítico'
            WHEN v.horas_agregadas / v.horas_planejadas < 0.9 THEN 'atenção'
            ELSE 'ok' END                               AS situacao_prazo
FROM lakehouse_vertice.bronze.projetos p
JOIN valor v USING (projeto_id)
WHERE p.status = 'em_andamento'
ORDER BY spi;
