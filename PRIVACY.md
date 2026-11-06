# Publicação e privacidade

Publique os arquivos do pacote de código-fonte exportado por `scripts/export_source.py`. A pasta de desenvolvimento completa contém diagnósticos, logs, configurações e caminhos locais; não deve ser usada como raiz do repositório público.

## Conferir e exportar

```sh
python3 scripts/check_privacy.py
python3 tests/test_privacy.py
python3 scripts/export_source.py dist/naruto-native-launcher-source.zip
```

O exportador usa uma lista explícita de arquivos, bloqueia caminhos privados e padrões comuns de credenciais e recusa links simbólicos. O ZIP não inclui históricoGit, arquivos de build, configurações locais, saves, relatórios de sessão, ISO, ELF ou dados do jogo. Datas e permissões são normalizadas; atributos estendidos do macOS não são exportados.

Essas verificações reduzem o risco de publicação acidental; não garantem detectar todo possível segredo ou identificador.

## Conta e identidade Git

Criar outra conta GitHub não muda automaticamente o nome e o e-mail que oGit grava nos commits. Antes do primeiro commit, configure a identidade **neste repositório**, usando seu apelido público e o endereço **noreply** fornecido peloGitHub nas configurações da nova conta. Não use o nome de login do computador como apelido se quiser manter as identidades separadas.

```sh
git config --local user.name 'SEU_APELIDO_PUBLICO'
git config --local user.email 'ENDERECO_NOREPLY_DA_NOVA_CONTA'
python3 scripts/check_privacy.py --git
```

Substitua os exemplos pelos valores corretos antes de commitar. O modo `--git` exige repositório próprio e identidade local explícita. Verifica a identidade efetiva dos próximos commits, os blobs preparados no índice e os autores, mensagens e blobs do histórico, inclusive arquivos removidos. `.gitignore` não remove dados já commitados. Históricos extensos ou blobs grandes podem precisar de revisão manual adicional.

## Aplicativos compilados

O aplicativo jogável local contém rotinas recompiladas da ISO. O pacote público é restrito aos fontes do inicializador. Use a pasta exportada para o GitHub e mantenha o aplicativo local fora da publicação.

O empacotador local remove metadados de depuração, assina as cópias e atualiza o catálogo de integridade. Os diagnósticos e arquivos gerados pelo motor ficam no computador.

## Dados locais durante o uso

O seletor de ISO guarda a última seleção nas preferências locais do aplicativo. Logs, saídas de `--inspect`/`--plan` e dados de diagnóstico podem conter caminhos da máquina em que foram gerados. Não anexe esses arquivos completos aIssues ouReleases sem revisá-los. O processo do jogo recebe apenas variáveis de ambiente doSO explicitamente permitidas e opções do motor; chaves de ferramentas externas não são repassadas.

Esta revisão de privacidade do inicializador não equivale a uma auditoria integral do runtime doPS2 ou de todas as dependências de terceiros.
