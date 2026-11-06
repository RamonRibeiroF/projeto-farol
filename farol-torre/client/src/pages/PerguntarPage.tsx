import { Alert, AlertDescription, GenieChat } from '@databricks/appkit-ui/react';
import { HOJE } from '../lib/formato';

// O agente "Farol · Diretoria" (Genie), registrado no servidor com o alias "default".
export function PerguntarPage() {
  return (
    <div className="w-full max-w-4xl mx-auto flex flex-col gap-4 h-[calc(100vh-8rem)]">
      <div>
        <h2 className="text-2xl font-semibold text-foreground">Perguntar</h2>
        <p className="text-sm text-muted-foreground">
          Pergunte em português sobre a carteira em {HOJE}. Ex.: &quot;O que vai dar errado no próximo mês, e o que eu faço
          agora?&quot;
        </p>
      </div>
      <Alert>
        <AlertDescription>
          Respostas geradas por IA a partir da gold do Farol: confira o SQL de cada resposta antes de decidir. As perguntas
          rodam com as suas permissões no Databricks.
        </AlertDescription>
      </Alert>
      <GenieChat alias="default" placeholder="Faça uma pergunta sobre os projetos…" className="flex-1 min-h-0" />
    </div>
  );
}
