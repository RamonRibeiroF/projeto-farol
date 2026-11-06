# Etapa 3 · Como reproduzir (bundle, silver e gold)

Passo a passo no Windows (PowerShell). No macOS e no Linux os comandos da CLI são os mesmos.

## Antes de começar

- Etapas 1 e 2 feitas: catálogo `lakehouse_vertice`, bronze carregada e o job `Ingestao` no workspace.
- Ferramentas: Git, Python, [Databricks CLI](https://docs.databricks.com/dev-tools/cli/install.html) e Claude Code
  (`winget install Anthropic.ClaudeCode`; depois feche e abra o terminal e confira com `claude --version`).

## 1 · Login no workspace

Passe o endereço inteiro, com `https://` e sem barra no fim, e um nome de profile:

```powershell
databricks auth login --host https://<seu-workspace>.cloud.databricks.com --profile <perfil>
databricks current-user me --profile <perfil>
databricks experimental aitools tools query "SHOW TABLES IN lakehouse_vertice.bronze" --profile <perfil>
```

A última lista as tabelas da bronze (as 9 da carga e `feriados`). Todo comando `databricks` daqui para frente leva
`--profile <perfil>`.

## 2 · O job de ingestão vira código

O `databricks.yml` já está na raiz. Importe o job que você criou clicando e tire as chaves do YAML:

```powershell
databricks jobs list --profile <perfil>
databricks bundle generate job --existing-job-id <id> --profile <perfil>
python tools\tirar_chaves_do_job.py
Select-String -Path resources\*.yml -Pattern "AWS_"
```

O `generate` grava as chaves do data lake em texto no YAML, e o repositório é público. O script troca cada chave por
`${var.s3_...}` e guarda o valor em `.databricks\bundle\dev\variable-overrides.json`, que o Git ignora. Rode-o **antes**
do primeiro `git add`. Conferência: o `Select-String` mostra as duas chaves como `${var.s3_...}`, e o `git status` não
lista `.databricks/`.

Neste repositório o job já foi renomeado para `vertice_farol` (`resources/vertice.job.yml`). Se você parte dele, em
vez do `generate`, crie o arquivo de valores das chaves à mão:

```powershell
New-Item -ItemType Directory -Force .databricks\bundle\dev | Out-Null
'{"s3_access_key_id": "<sua chave>", "s3_secret_access_key": "<seu segredo>"}' | Set-Content .databricks\bundle\dev\variable-overrides.json
```

Sem acesso a um data lake S3, a bronze vem da etapa 1 (`ingestao/01-carregar-dados` e `ingestao/02-bronze.sql`). A
conferência e o pipeline não dependem da ingestão: rode só eles (passo 4).

## 3 · Claude Code e as travas

```powershell
databricks aitools install --agents claude-code --scope project --skills-only --experimental
New-Item -ItemType Directory -Force .claude | Out-Null
```

Crie `.claude\settings.json` proibindo o que não tem volta (`bundle destroy`, deploy em `prod`, `git push --force`,
`rm -rf`). Se o `aitools install` der `Acesso negado`, feche o editor e apague só `.databricks\aitools` antes de repetir.
Nunca apague a `.databricks` inteira: as chaves estão lá.

## 4 · Os prompts

Abra o Claude Code na raiz (`claude`) e siga a ordem de [`llm/README.md`](../llm/README.md). Depois de cada prompt:

```powershell
databricks bundle validate --profile <perfil>
databricks bundle deploy --profile <perfil>
databricks bundle run vertice_farol --only conferencia_bronze,medalhao --profile <perfil>
git status
```

O `git status` não pode listar chaves nem `.databricks/`. Salve no GitHub só depois de conferir.

## Problemas comuns

| Sintoma | Causa | O que fazer |
|---|---|---|
| `invalid host` no login | endereço digitado sem `//` ou com letra a mais | passe o host inteiro pelo parâmetro `--host` |
| `claude` não reconhecido após instalar | o terminal não leu o caminho novo | feche e abra o terminal (ou o editor) |
| `RESOURCE_EXHAUSTED` | dois runs ao mesmo tempo no serverless | espere o run ativo terminar |
| a ingestão falha com `EndpointConnectionError` ou `NameResolutionError` | a rede do workspace não alcança o domínio | veja [`docs/decisoes/001-apis-externas-no-free-edition.md`](decisoes/001-apis-externas-no-free-edition.md) |
