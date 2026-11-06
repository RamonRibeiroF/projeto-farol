Use as skills databricks-core e databricks-dabs.
Sempre --profile <perfil> (o profile do meu workspace; se não souber qual, pergunte). Nunca escolha um profile sozinho.
Leia o CLAUDE.md e o docs/PRD.md da raiz (não substitua o CLAUDE.md) e use
tools/run_sql.py para rodar SQL. As pastas continuam em src/ (conferencia,
silver, gold, testes) e ganham src/ia/.

Continue o bundle na raiz deste repositório. A gold e os testes estão
prontos. Agora a última camada da noite, e o job inteiro rodando sozinho.
O "hoje" é DATE'2026-10-16'. Nunca current_date().

0. Antes de escrever qualquer coisa, teste as funções de IA neste workspace
   (tools/run_sql.py, nas duas linhas abaixo). Se alguma não existir ou for
   recusada no Free Edition, pare e me mostre o erro: não improvise outro caminho.
     SELECT ai_classify('Sem SRE alocado: pipeline de deploy quebrado. Impacto estimado: 1 semana.',
       '["change_freeze","falta_sre","dependencia_fornecedor","rotatividade","mudanca_escopo","bug_retrabalho","aprovacao_cliente","sem_bloqueio"]',
       map('version','2.0')):response[0]::STRING;      -- esperado: falta_sre
     SELECT ai_extract('Sem SRE alocado: pipeline de deploy quebrado. Impacto estimado: 1 semana.',
       '{"bloqueio":{"type":"string"},"quem_destrava":{"type":"string"},"dias_impacto":{"type":"number","description":"1 semana = 7"}}',
       map('version','2.0')):response;                 -- esperado: dias_impacto = 7

1. O texto livre do status vira coluna. Use as funções de IA na versão 2.0
   (map('version','2.0')); o resultado é VARIANT, lido com ':response'.

   src/ia/status_estruturado.sql (sql_task, caminho completo das tabelas)
   a. CREATE TABLE IF NOT EXISTS lakehouse_vertice.gold.status_estruturado com
      COMMENT em cada coluna: projeto_id, data_status, farol, causa_bloqueio,
      bloqueio, quem_destrava, dias_impacto (DOUBLE), metodo ('regra', 'ia' ou
      'palavra_chave'), texto_status, _classificado_em.
      NÃO é CREATE OR REPLACE: a tabela acumula, e a IA não pode ser refeita
      a cada execução.
   b. MERGE INTO ... WHEN NOT MATCHED THEN INSERT, só com os status da
      silver.status_semanal que ainda não estão na tabela (LEFT ANTI JOIN por
      projeto_id e data_status). Para cada status:
      - metodo = 'regra' se status_vazio ou se o texto (minúsculas) diz
        'bloqueios: nenhum', 'sem bloqueios' ou 'nada relevante';
        'ia' se data_status >= DATE'2026-07-18' (últimos 90 dias);
        senão 'palavra_chave'.
      - causa_bloqueio: 'nao_reportado' se vazio; 'sem_bloqueio' na regra;
        na IA, ai_classify com a lista ["change_freeze","falta_sre",
        "dependencia_fornecedor","rotatividade","mudanca_escopo",
        "bug_retrabalho","aprovacao_cliente","sem_bloqueio"]; na
        palavra-chave, RLIKE: freeze|congelamento|janela de deploy →
        change_freeze; sre|infraestrutura|ambiente de homologação → falta_sre;
        forge|consultoria|fornecedor → dependencia_fornecedor; saída de|
        rotatividade|onboarding → rotatividade; escopo|change request|regra de
        negócio → mudanca_escopo; bugs|regressão|refazendo → bug_retrabalho;
        aprovação do cliente|homologação do cliente → aprovacao_cliente.
      - só na IA: ai_extract com JSON schema tipado: bloqueio (string),
        quem_destrava (string), dias_impacto (number, "1 semana = 7").
      - dias_impacto fora da IA: regex em 'impacto estimado de N dias' e
        'impacto estimado: 1 semana' (= 7).
   c. No fim, um SELECT de leitura: quantos status por metodo e causa.

   Acrescente ao job a tarefa status_com_ia, depois de medalhao (em paralelo
   com testes_de_qualidade).

2. O job inteiro
   - confira em resources/vertice.job.yml a ordem: ingestao_feriados e
     ingestao_data_lake em paralelo → conferencia_bronze → medalhao →
     testes_de_qualidade e status_com_ia em paralelo
   - agendamento toda segunda às 6h (America/Sao_Paulo); no dev ele fica
     pausado pelo preset, e está certo
   - max_concurrent_runs: 1 (duas execuções ao mesmo tempo apagariam a
     bronze uma da outra)
   - atualize o comentário do topo com as 6 tarefas e o que cada uma faz
     (sem citar "prompt" nem "aula" nos comentários)

3. Documentação do repositório
   - CLAUDE.md: acrescente src/ia/ na tabela de pastas e uma linha sobre a
     gold (3 tabelas + status_estruturado) e sobre o MERGE incremental da IA

Trabalhe direto: o EXPECT e os testes são a conferência. Nunca dispare um
run com outro ainda ativo (limite de compute do Free Edition).

Rode e me mostre a saída (a ingestão já rodou; o medalhão, os testes e a IA
rodam agora, os dois últimos em paralelo):
  databricks bundle validate --profile <perfil>
  databricks bundle deploy --profile <perfil>
  databricks bundle run vertice_farol --only medalhao,testes_de_qualidade,status_com_ia --profile <perfil>
E no fim, numa tabela: cada tarefa, quanto tempo levou e o resultado.
Depois rode o job uma segunda vez, do mesmo jeito: o MERGE da IA deve inserir
ZERO linhas e terminar em segundos.
