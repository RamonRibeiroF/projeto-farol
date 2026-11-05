# 001 · APIs externas no Databricks Free Edition

**Data:** 05/11/2026 · **Etapa:** 2 (ingestão de uma API) · **Status:** em vigor

## Contexto

O notebook `ingestao/01_ingestao_api.py` busca os feriados nacionais de 2026 na BrasilAPI. No Free Edition, com
computação serverless, a chamada falhou:

```
ConnectionError: HTTPSConnectionPool(host='brasilapi.com.br', port=443): Max retries exceeded with url:
/api/feriados/v1/2026 (Caused by NameResolutionError: Failed to resolve 'brasilapi.com.br'
([Errno -3] Temporary failure in name resolution))
```

O erro é de **resolução de DNS**, antes de qualquer resposta da API. A rede do serverless no Free Edition só
resolve uma lista de domínios liberados (repositórios de pacotes e o GitHub, por exemplo). A BrasilAPI não está nela.
O mesmo código, no mesmo workspace, funcionou ao trocar a URL por `raw.githubusercontent.com`.

**A restrição depende do workspace.** Em 05/11/2026 o mesmo teste foi repetido em dois workspaces Free Edition:

| Workspace | Cadastro | brasilapi.com.br | Supabase Storage | raw.githubusercontent.com |
|---|---|---|---|---|
| 1 | e-mail Microsoft | não resolve | inacessível (`EndpointConnectionError`) | ok |
| 2 | conta Google | `200`, 14 feriados | porta 443 abre | ok |

**Como as contas foram criadas.** O workspace 1 foi aberto com um e-mail da Microsoft; o workspace 2, com a conta
Google. Fora isso, o procedimento foi o mesmo (Free Edition, serverless, mesmo repositório e mesmos notebooks).
No workspace 2 o job `Ingestao` (tarefas `IngestaoApi` e `IngestaoAWS`) terminou com sucesso em 05/11/2026,
1 min 58 s. O que se observou é uma correlação com o tipo de conta usada no cadastro; a causa não foi confirmada e
não encontrei documentação que explique a diferença. Por isso o processo abaixo não assume o bloqueio: testa a
chamada original primeiro, e quem cadastrar outro workspace deve repetir o teste de rede.

## Decisão

Para toda chamada de API externa, seguir este processo:

1. Escrever primeiro a chamada à API original, como no material da imersão.
2. Se falhar com `NameResolutionError`, publicar neste repositório uma cópia do JSON, no mesmo formato da API, em
   `data/`, e apontar o `requests.get` para a URL `raw.githubusercontent.com` do arquivo.
3. Registrar aqui o código original, o motivo e a data.

O exercício continua sendo o mesmo: uma chamada HTTP, o JSON pousado no raw, a bronze lida com `read_files`.
A diferença é que a fonte é um espelho estático, e não a API viva.

## Consequências

- A tabela não acompanha mudanças da API original: os dados são uma foto de 2026.
- Em um ambiente sem essa restrição (o workspace 2, por exemplo), basta voltar para a URL original.
- O espelho no GitHub funciona nos dois workspaces, então o notebook do repositório continua apontando para ele.

## Código original (BrasilAPI)

```python
import requests

url = "https://brasilapi.com.br/api/feriados/v1/2026"
resposta = requests.get(url, timeout=30)
resposta.raise_for_status()    # se a API cair, para aqui com o erro, em vez de seguir com nada

feriados = resposta.json()
```

O SQL original lia o campo `weekday` do JSON (`weekday AS dia_da_semana`). O espelho tem só `date`, `name` e
`type`, então o notebook calcula o dia da semana a partir da data.

## Código atual (espelho no GitHub)

```python
url = "https://raw.githubusercontent.com/RamonRibeiroF/projeto-farol/main/data/feriados-2026.json"
```

## Registro de APIs

| Notebook | API original | Situação no Free Edition | Espelho |
|---|---|---|---|
| `ingestao/01_ingestao_api.py` | `brasilapi.com.br/api/feriados/v1/2026` | workspace 1: bloqueada (DNS) · workspace 2: funciona | `data/feriados-2026.json` |
| `ingestao/02_ingestao_boto3.py` | storage S3 (Supabase) | workspace 1: inacessível · workspace 2: funciona (job concluído) | não precisa: o Supabase é a fonte original |
