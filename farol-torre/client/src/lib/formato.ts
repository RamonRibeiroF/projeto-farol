// Formatação em português. Tudo que vem do warehouse passa por Number(): DECIMAL chega como texto.

const reais = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
const reaisCompacto = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
  notation: 'compact',
  maximumFractionDigits: 1,
});
const indice = new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const inteiro = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });
const umaCasa = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 1 });
const pct = new Intl.NumberFormat('pt-BR', { style: 'percent', maximumFractionDigits: 0 });

export const num = (v: unknown): number => Number(v ?? 0);
export const brl = (v: unknown): string => reais.format(num(v));
export const brlCompacto = (v: unknown): string => reaisCompacto.format(num(v));
export const idx = (v: unknown): string => indice.format(num(v));
export const int = (v: unknown): string => inteiro.format(num(v));
export const dec1 = (v: unknown): string => umaCasa.format(num(v));
export const porcento = (v: unknown): string => pct.format(num(v));

const CAUSAS: Record<string, string> = {
  change_freeze: 'Change freeze',
  falta_sre: 'Falta de SRE',
  dependencia_fornecedor: 'Dependência de fornecedor',
  rotatividade: 'Rotatividade',
  mudanca_escopo: 'Mudança de escopo',
  bug_retrabalho: 'Bugs e retrabalho',
  aprovacao_cliente: 'Aprovação do cliente',
};
export const causa = (c: string | null | undefined): string => (c ? (CAUSAS[c] ?? c) : '—');

// "Hoje" do dataset: os dados param em 16/10/2026.
export const HOJE = '16/10/2026';
