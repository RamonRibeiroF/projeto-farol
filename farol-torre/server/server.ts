import { createApp, analytics, genie, server, getWarehouseId } from '@databricks/appkit';
import { WorkspaceClient } from '@databricks/sdk-experimental';

// O score do modelo (gold.score_estouro_30d) pode ainda não existir. Por isso ele NÃO é uma query de
// config/queries (o typegen e o build quebrariam): vem desta rota, que responde {disponivel, linhas}.
// Contrato da tabela (docs/etapa-4-contexto.md): projeto_id, data_referencia, prob_estouro_30d (0 a 1),
// ranking, faixa_risco ('alto', 'medio', 'baixo') e principais_fatores. Lê a data_referencia mais recente.
const TABELA_SCORE = 'lakehouse_vertice.gold.score_estouro_30d';

type LinhaScore = { projeto_id: string; prob_estouro_30d: number; faixa_risco: string; principais_fatores: string };
type RespostaScore = { disponivel: boolean; linhas: LinhaScore[]; motivo?: string };

async function lerScore(): Promise<RespostaScore> {
  const cliente = new WorkspaceClient({});
  const r = await cliente.statementExecution.executeStatement({
    warehouse_id: await getWarehouseId(),
    statement: `SELECT projeto_id, prob_estouro_30d, faixa_risco, principais_fatores FROM ${TABELA_SCORE}
                WHERE data_referencia = (SELECT MAX(data_referencia) FROM ${TABELA_SCORE})`,
    wait_timeout: '30s',
  });
  if (r.status?.state !== 'SUCCEEDED') {
    return { disponivel: false, linhas: [], motivo: r.status?.error?.message ?? String(r.status?.state) };
  }
  const linhas = (r.result?.data_array ?? []).map((l) => ({
    projeto_id: String(l[0]),
    prob_estouro_30d: Number(l[1]),
    faixa_risco: String(l[2]),
    principais_fatores: String(l[3] ?? ''),
  }));
  return { disponivel: true, linhas };
}

// Sem cache: os números vêm sempre do warehouse.
// genie(): o agente "Farol · Diretoria" (DATABRICKS_GENIE_SPACE_ID, alias "default"), em nome de quem pergunta.
createApp({
  plugins: [analytics(), genie(), server()],
  onPluginsReady(appkit) {
    appkit.server.extend((app) => {
      app.get('/api/score-estouro', async (_req, res) => {
        try {
          res.json(await lerScore());
        } catch (e) {
          const resposta: RespostaScore = { disponivel: false, linhas: [], motivo: String(e) };
          res.json(resposta);
        }
      });
    });
  },
}).catch(console.error);
