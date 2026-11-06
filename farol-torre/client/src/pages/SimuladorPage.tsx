import { useState } from 'react';
import {
  useAnalyticsQuery,
  Alert,
  AlertDescription,
  AlertTitle,
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
  Input,
  Label,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  Skeleton,
} from '@databricks/appkit-ui/react';
import { brl, causa, dec1, HOJE, idx, int, num, porcento } from '../lib/formato';

const SEM_PARAMETROS = {};
const SEMANAS_NO_MES = 4;
const JANELA_DIAS = 90; // status dos últimos 90 dias (desde 18/07/2026)
const HORIZONTE_DIAS = 30;
const ONBOARDING_PADRAO = 40;

function Linha({ rotulo, valor, destaque }: { rotulo: string; valor: string; destaque?: 'bom' | 'ruim' }) {
  const cor = destaque === 'bom' ? 'text-emerald-600' : destaque === 'ruim' ? 'text-destructive' : 'text-foreground';
  return (
    <div className="flex items-baseline justify-between gap-4 py-2 border-b last:border-b-0">
      <span className="text-sm text-muted-foreground">{rotulo}</span>
      <span className={`text-lg font-semibold tabular-nums ${cor}`}>{valor}</span>
    </div>
  );
}

export function SimuladorPage() {
  const pessoas = useAnalyticsQuery('pessoas_ociosas', SEM_PARAMETROS);
  const projetos = useAnalyticsQuery('projetos_risco', SEM_PARAMETROS);

  const [pessoaId, setPessoaId] = useState<string>('');
  const [projetoId, setProjetoId] = useState<string>('');
  const [onboarding, setOnboarding] = useState<number>(ONBOARDING_PADRAO);

  const pessoa = pessoas.data?.find((p) => p.colaborador_id === pessoaId);
  const ehSre = pessoa?.papel === 'sre';
  // SRE destrava falta de SRE; as demais pessoas cobrem buraco de rotatividade.
  const causaAlvo = ehSre ? 'falta_sre' : 'rotatividade';

  const destinos = (projetos.data ?? [])
    .filter((p) => p.situacao === 'atenção' || p.situacao === 'crítico')
    .map((p) => ({ ...p, dias_causa: num(ehSre ? p.dias_falta_sre : p.dias_rotatividade) }))
    .sort((a, b) => (ehSre ? b.dias_causa - a.dias_causa : 0));
  const projeto = destinos.find((p) => p.projeto_id === projetoId);

  const custoHora = num(pessoa?.custo_hora);
  const horasMes = num(pessoa?.horas_paradas_semana) * SEMANAS_NO_MES;
  const ociosidadeEvitada = horasMes * custoHora;
  const diasRecuperados = projeto ? (projeto.dias_causa / JANELA_DIAS) * HORIZONTE_DIAS : 0;
  const mobilizacao = onboarding * custoHora;
  const saldo = ociosidadeEvitada - mobilizacao;

  const carregando = pessoas.loading || projetos.loading;
  const erro = pessoas.error ?? projetos.error;

  return (
    <div className="space-y-6 w-full max-w-5xl mx-auto">
      <div>
        <h2 className="text-2xl font-semibold text-foreground">Simulador de realocação</h2>
        <p className="text-sm text-muted-foreground">
          Quem está parado (utilização abaixo de 20% nas últimas 12 semanas, até {HOJE}) pode destravar um projeto em
          atenção ou crítico? Simule por um mês.
        </p>
      </div>

      {erro && (
        <Alert variant="destructive">
          <AlertTitle>Não deu para ler os dados</AlertTitle>
          <AlertDescription>{erro}</AlertDescription>
        </Alert>
      )}

      {carregando && <Skeleton className="h-40 w-full" />}

      {!carregando && pessoas.data && pessoas.data.length === 0 && (
        <Empty>
          <EmptyHeader>
            <EmptyTitle>Ninguém abaixo de 20% de utilização</EmptyTitle>
            <EmptyDescription>Não há pessoa ociosa para realocar nas últimas 12 semanas.</EmptyDescription>
          </EmptyHeader>
        </Empty>
      )}

      {!carregando && pessoas.data && pessoas.data.length > 0 && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <Card>
            <CardHeader>
              <CardTitle>Escolha</CardTitle>
              <CardDescription>
                {ehSre ? 'Para SRE, os projetos vêm ordenados pelos dias perdidos por falta de SRE.' : 'Projetos do pior para o melhor.'}
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="pessoa">Pessoa ociosa</Label>
                <Select
                  value={pessoaId}
                  onValueChange={(v) => {
                    setPessoaId(v);
                    setProjetoId('');
                  }}
                >
                  <SelectTrigger id="pessoa" className="w-full">
                    <SelectValue placeholder="Escolha uma pessoa" />
                  </SelectTrigger>
                  <SelectContent>
                    {pessoas.data.map((p) => (
                      <SelectItem key={p.colaborador_id} value={p.colaborador_id}>
                        {p.nome} · {p.papel} {p.senioridade} · {porcento(p.utilizacao)} de utilização
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-2">
                <Label htmlFor="projeto">Projeto destino</Label>
                <Select value={projetoId} onValueChange={setProjetoId} disabled={!pessoa}>
                  <SelectTrigger id="projeto" className="w-full">
                    <SelectValue placeholder={pessoa ? 'Escolha um projeto' : 'Escolha a pessoa primeiro'} />
                  </SelectTrigger>
                  <SelectContent>
                    {destinos.map((p) => (
                      <SelectItem key={p.projeto_id} value={p.projeto_id}>
                        {p.projeto_id} · {p.situacao} · SPI {idx(p.spi)} · {int(p.dias_causa)} dias de {causa(causaAlvo).toLowerCase()}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-2">
                <Label htmlFor="onboarding">Horas de onboarding</Label>
                <Input
                  id="onboarding"
                  type="number"
                  min={0}
                  value={onboarding}
                  onChange={(e) => setOnboarding(Math.max(0, Number(e.target.value)))}
                />
              </div>

              {pessoa && (
                <p className="text-xs text-muted-foreground">
                  {pessoa.nome}: {dec1(pessoa.horas_paradas_semana)} h paradas por semana, custo/hora {brl(custoHora)}.
                </p>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Resultado em um mês</CardTitle>
              <CardDescription>
                {projeto ? `${pessoa?.nome} → ${projeto.projeto}` : 'Escolha a pessoa e o projeto para ver a conta.'}
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Linha rotulo="Horas no mês" valor={pessoa ? `${dec1(horasMes)} h` : '—'} />
              <Linha rotulo="Ociosidade que deixa de ser paga" valor={pessoa ? brl(ociosidadeEvitada) : '—'} destaque="bom" />
              <Linha
                rotulo={`Dias de cronograma recuperados (${causa(causaAlvo).toLowerCase()})`}
                valor={projeto ? dec1(diasRecuperados) : '—'}
                destaque="bom"
              />
              <Linha rotulo="Mobilização (onboarding × custo/hora)" valor={pessoa ? brl(mobilizacao) : '—'} destaque="ruim" />
              <Linha
                rotulo="Saldo"
                valor={pessoa ? brl(saldo) : '—'}
                destaque={pessoa ? (saldo >= 0 ? 'bom' : 'ruim') : undefined}
              />

              <details className="mt-4 text-sm text-muted-foreground">
                <summary className="cursor-pointer text-foreground">Como a conta é feita</summary>
                <ul className="mt-2 list-disc pl-5 space-y-1">
                  <li>Horas no mês = horas paradas por semana (média das últimas 12) × {SEMANAS_NO_MES} semanas.</li>
                  <li>Ociosidade que deixa de ser paga = horas no mês × custo/hora da pessoa.</li>
                  <li>
                    Dias recuperados = dias de impacto da causa ({ehSre ? 'falta de SRE' : 'rotatividade'}) no status dos
                    últimos {JANELA_DIAS} dias ÷ {JANELA_DIAS} × {HORIZONTE_DIAS}: o ritmo de perda do projeto, levado a um mês.
                  </li>
                  <li>Mobilização = horas de onboarding (editável, padrão {ONBOARDING_PADRAO}) × custo/hora.</li>
                  <li>Saldo = ociosidade que deixa de ser paga − mobilização. Os dias recuperados não entram em reais.</li>
                </ul>
              </details>
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  );
}
