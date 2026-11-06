import {
  useAnalyticsQuery,
  Alert,
  AlertDescription,
  AlertTitle,
  Badge,
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
  Skeleton,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@databricks/appkit-ui/react';
import { brl, brlCompacto, causa, HOJE, idx, int, num, porcento } from '../lib/formato';
import { useScore } from '../lib/useScore';

const SEM_PARAMETROS = {};

function Kpi({ titulo, valor, detalhe, carregando }: { titulo: string; valor: string; detalhe: string; carregando: boolean }) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardDescription>{titulo}</CardDescription>
        <CardTitle className="text-3xl tabular-nums">{carregando ? <Skeleton className="h-9 w-24" /> : valor}</CardTitle>
      </CardHeader>
      <CardContent className="text-xs text-muted-foreground">{detalhe}</CardContent>
    </Card>
  );
}

function Situacao({ valor }: { valor: string }) {
  if (valor === 'crítico') return <Badge variant="destructive">crítico</Badge>;
  if (valor === 'atenção') return <Badge className="bg-amber-500 text-black hover:bg-amber-500">atenção</Badge>;
  return <Badge variant="secondary">{valor}</Badge>;
}

export function ProjetosRiscoPage() {
  const kpis = useAnalyticsQuery('kpis', SEM_PARAMETROS);
  const projetos = useAnalyticsQuery('projetos_risco', SEM_PARAMETROS);
  const { score, carregando: carregandoScore } = useScore();

  const k = kpis.data?.[0];
  const porProjeto = new Map((score?.disponivel ? score.linhas : []).map((l) => [l.projeto_id, l]));
  const altoRisco = score?.disponivel ? score.linhas.filter((l) => l.faixa_risco === 'alto').length : null;

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <div>
        <h2 className="text-2xl font-semibold text-foreground">Projetos em risco</h2>
        <p className="text-sm text-muted-foreground">
          Carteira em andamento em {HOJE}, calculada na camada gold. Crítico: SPI ou CPI abaixo de 0,8; atenção: abaixo de 0,9.
        </p>
      </div>

      {kpis.error && (
        <Alert variant="destructive">
          <AlertTitle>Não deu para ler os KPIs</AlertTitle>
          <AlertDescription>{kpis.error}</AlertDescription>
        </Alert>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <Kpi
          titulo="Projetos em risco"
          valor={k ? int(k.em_risco) : '—'}
          detalhe={k ? `${int(k.criticos)} críticos · ${int(k.melancias)} melancias · de ${int(k.em_andamento)} em andamento` : 'atenção + crítico'}
          carregando={kpis.loading}
        />
        <Kpi
          titulo="Estouro previsto"
          valor={k ? brlCompacto(k.estouro_previsto) : '—'}
          detalhe="EAC − orçamento, somado nos projetos em andamento"
          carregando={kpis.loading}
        />
        <Kpi
          titulo="Carteira em andamento"
          valor={k ? brlCompacto(k.carteira) : '—'}
          detalhe="soma do valor de contrato"
          carregando={kpis.loading}
        />
        <Kpi
          titulo="Alto risco em 30 dias"
          valor={altoRisco === null ? '—' : int(altoRisco)}
          detalhe={score?.disponivel ? 'projetos na faixa alta do modelo de estouro' : 'score do modelo ainda não publicado'}
          carregando={carregandoScore}
        />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Do pior para o melhor</CardTitle>
          <CardDescription>
            🍉 melancia: o gerente diz verde, mas o SPI está abaixo de 0,9. Causa principal e dias de impacto vêm do texto do
            status semanal dos últimos 90 dias.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {projetos.loading && (
            <div className="space-y-2">
              {Array.from({ length: 6 }, (_, i) => (
                <Skeleton key={i} className="h-8 w-full" />
              ))}
            </div>
          )}
          {projetos.error && (
            <Alert variant="destructive">
              <AlertTitle>Não deu para ler os projetos</AlertTitle>
              <AlertDescription>{projetos.error}</AlertDescription>
            </Alert>
          )}
          {projetos.data && projetos.data.length === 0 && (
            <Empty>
              <EmptyHeader>
                <EmptyTitle>Nenhum projeto em andamento</EmptyTitle>
                <EmptyDescription>Confira se o pipeline da gold rodou.</EmptyDescription>
              </EmptyHeader>
            </Empty>
          )}
          {projetos.data && projetos.data.length > 0 && (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Projeto</TableHead>
                  <TableHead>Situação</TableHead>
                  <TableHead className="text-right">SPI</TableHead>
                  <TableHead className="text-right">CPI</TableHead>
                  <TableHead className="text-right">Estouro</TableHead>
                  <TableHead className="text-right">Atraso (dias)</TableHead>
                  <TableHead>Farol do gerente</TableHead>
                  <TableHead>Farol pelo número</TableHead>
                  <TableHead>Causa principal</TableHead>
                  <TableHead className="text-right">P(estouro)</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {projetos.data.map((p) => {
                  const s = porProjeto.get(p.projeto_id);
                  return (
                    <TableRow key={p.projeto_id}>
                      <TableCell className="max-w-xs">
                        <div className="font-medium truncate">{p.projeto}</div>
                        <div className="text-xs text-muted-foreground">{p.cliente}</div>
                      </TableCell>
                      <TableCell>
                        <Situacao valor={p.situacao} />
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{idx(p.spi)}</TableCell>
                      <TableCell className="text-right tabular-nums">{idx(p.cpi)}</TableCell>
                      <TableCell className="text-right tabular-nums">{brl(p.estouro_previsto)}</TableCell>
                      <TableCell className="text-right tabular-nums">{int(p.atraso_projetado_dias)}</TableCell>
                      <TableCell>
                        {p.farol_do_gerente ?? '—'}
                        {(p.melancia === true || String(p.melancia) === 'true') && <span title="melancia"> 🍉</span>}
                      </TableCell>
                      <TableCell>{p.farol_calculado}</TableCell>
                      <TableCell>{causa(p.causa_principal)}</TableCell>
                      <TableCell className="text-right tabular-nums">{s ? porcento(num(s.prob_estouro_30d)) : '—'}</TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
