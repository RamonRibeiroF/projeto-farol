import { useEffect, useState } from 'react';
import { z } from 'zod';

// GET /api/score-estouro: o score do modelo pode ainda não existir; a tela mostra "—" nesse caso.
const respostaSchema = z.object({
  disponivel: z.boolean(),
  linhas: z.array(
    z.object({
      projeto_id: z.string(),
      prob_estouro_30d: z.coerce.number(),
      faixa_risco: z.string(),
      principais_fatores: z.string(),
    }),
  ),
  motivo: z.string().optional(),
});

export type Score = z.infer<typeof respostaSchema>;

export function useScore(): { score: Score | null; carregando: boolean } {
  const [score, setScore] = useState<Score | null>(null);
  const [carregando, setCarregando] = useState(true);

  useEffect(() => {
    let ativo = true;
    fetch('/api/score-estouro')
      .then((r) => r.json())
      .then((json: unknown) => {
        const r = respostaSchema.safeParse(json);
        if (ativo) setScore(r.success ? r.data : { disponivel: false, linhas: [] });
      })
      .catch(() => {
        if (ativo) setScore({ disponivel: false, linhas: [] });
      })
      .finally(() => {
        if (ativo) setCarregando(false);
      });
    return () => {
      ativo = false;
    };
  }, []);

  return { score, carregando };
}
