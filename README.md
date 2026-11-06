# Naruto Native Launcher

O pacote público contém apenas o código do inicializador. Consulte [PRIVACY.md](PRIVACY.md) antes de publicar. O workspace de desenvolvimento e seus diagnósticos são locais.

Inicializador local para o port de Ultimate Ninja 5, começando pelo macOS Apple Silicon. Seleciona a ISO do usuário, confere sua identidade e abre um motor nativo compatível. Nenhum arquivo é enviado pela internet.

## Estado atual

A interface, o leitor ISO9660, a verificação por SHA-256, a seleção de motor, os saves por edição, os logs, o áudio e a resolução 1×/2× estão implementados. O jogo começa do boot, na cadência PAL original; não há interpolação ou FPS desbloqueado. O motor usa recompilação do código EE e um runtime que reproduz os subsistemas do PS2; não é uma reescrita integral do jogo.

**A edição europeia fornecida pelo usuário foi adaptada e testada do boot até uma luta Naruto versus Naruto.** A versão é PAL, SLES-55605, com a seguinte identidade:

```text
ISO SHA-256: c4f0fe0f2175b7c52ec59d7f33da84894197b6edd811c064e5272d8cf49f65d7
ELF SHA-256: 20a43677397731a2a20899336d1165ace5b436906b9b89be90fb10f4558dd19d
ISO bytes: 1926234112
```

O inicializador não aceita outra imagem apenas por ela informar SLES-55605. Identificar o serial não comprova que o código recompilado seja compatível. Imagens alteradas e outras revisões ficam indisponíveis até validação própria.

O aplicativo jogável de desenvolvimento usa um motor que contém código de jogo previamente recompilado para essa edição. Ao importar, ele valida a ISO e extrai o ELF para uso local. A ISO fornece os recursos durante a execução. O aplicativo com esse motor é destinado a uso local.

O build padrão permite abrir a interface e verificar uma ISO. Para jogar, ainda é preciso gerar o motor a partir da cópia do próprio usuário. O código público atual cobre a interface e o empacotador. A compilação do motor depende do pipeline privado de desenvolvimento.

## Compilar a interface

Requer macOS Apple Silicon, Command Line Tools com Swift e Python3 para o script de build. O aplicativo produzido não depende de Python, Homebrew ou ferramentas de compilação para abrir sua interface.

```sh
python3 scripts/build.py
open 'build/Naruto Native Launcher.app'
```

O build da interface requer macOS 15 ou posterior. O motor atual requer macOS 26 ou posterior. Windows e Linux ainda não foram implementados ou testados.

Para empacotar localmente o motor europeu validado no workspace de desenvolvimento:

```sh
python3 scripts/build.py --output 'build/European.app' \
  --european-manifest '/caminho/stock-europe-2171.json' \
  --sdl '/caminho/libSDL2-2.0.0.dylib'
```

O manifesto deve apontar para o motor e para a ISO que o validaram. O executável resultante contém traduções de rotinas do jogo. Mantenha esse executável e os C++ gerados localmente, conforme a separação de código documentada pelo [projeto base](https://github.com/snuri00/ps2-web-recomp#legal).

O build altera os caminhos de biblioteca e assina apenas as cópias privadas, preservando o executável de referência. A assinatura local ad hoc não equivale a notarização Apple.

## Saves e operação

Abra o aplicativo, clique em **Selecionar ISO…** e aguarde a conferência da imagem europeia. Com a mensagem **ISO validada. Pronto para jogar.**, clique em **Jogar**. Na tela de título, escolha **New Game** para começar sem save. O jogo usa a cadência original PAL de 50 campos por segundo, com aproximadamente 25 FPS nas lutas. A resolução padrão é 1× e o menu oferece 2×. Para habilitar o áudio, desmarque **Silenciar o jogo**.

Saves ficam em `~/Library/Application Support/NarutoNativeLauncher/Games/<perfil>/memory-card.ps2`. O ELF extraído para uso local e os logs ficam na mesma pasta. Nenhum save antigo é importado ou substituído automaticamente. A ISO é aberta somente para leitura e não é duplicada integralmente.

O aplicativo verifica o hash da imagem inteira antes de autorizar a execução, além do hash do ELF e dos arquivos do motor. Edições desconhecidas ficam indisponíveis para execução. Isso é uma lista de compatibilidade técnica, não uma verificação jurídica de propriedade da ISO.

## Verificações

```sh
python3 tests/test_import.py 'build/Naruto Native Launcher.app/Contents/MacOS/NarutoLauncher'
```

O executável aceita `--inspect /caminho.iso` para consultar metadados em JSON, `--plan` para preparar o ELF e imprimir o comando de lançamento e `--smoke-test` para testar 600 campos do boot. O teste roda oculto, mudo e com cartão de memória privado. A cadência de lançamento é PAL em todos os casos.

## Cobertura e próximos passos

O backend europeu partiu da1532, que recompilou22 unidades que diferiram da base e manteve114 programasVU previamente compilados, selecionados pela identidade do código carregado. O móduloMOD da edição anterior foi removido. A cadênciaPAL foi mantida:50 campos/s e aproximadamente25 atualizações/s na luta observada.

A candidata1560 inclui13 entradas adicionais de métodos de batalha, incluindo a rotina ausente apontada pelo fechamento relatado pelo usuário. As funções foram recompiladas a partir dos bytes originais; metadados de tabelas não foram tratados como código. A validação cobre idioma inglês, boot, título, New Game, menus, seleção de personagens/cenário, combate Naruto versus Naruto e um replay Naruto versus Neji com especial e retorno à seleção. Isso amplia a cobertura, mas não certifica todos os caminhos de batalha. Não cobre uma campanha inteira, todos os personagens ou todos os idiomas. O aplicativo ainda não foi notarizado pela Apple. O trabalho de FPS desbloqueado e mods foi encerrado a pedido do usuário; próximos trabalhos são ampliar cobertura e preparar a distribuição pública.

## Atualização de cobertura de batalha

A revisão1583 inclui mais sete entradas originais de métodos em relação à1560. O fechamento relatado após trocar para Hinata contra Neji foi reproduzido como código ausente na preparação de objetos. A investigação também recuperou métodos alcançados nos golpes da luta. Foram verificadas as tabelas e os bytes originais antes de recompilar; nenhum detector de falha foi desativado. O replay corrigido passou pelo carregamento, pelos golpes e pelo retorno à seleção de personagens. Uma imagem de referência de Naruto contra Neji permaneceu idêntica. Isso não certifica todas as combinações de personagens ou a campanha.

## Cobertura de habilidades

A revisão1593 ampliou a recompilação com337 pontos de entrada que faltavam em215 tabelas da família de habilidades de combate. A leitura das tabelas e dos nomes de tipo foi conferida nos arquivos originais. Os1705 alvos únicos desse conjunto têm entradas de execução; isso é cobertura estática, não execução de todos os métodos. O novo fechamento de Naruto/Kakashi foi reproduzido no endereço do log e o replay corrigido passou por ele. Antes da falha, imagem, ciclos e RAMEE completos foram iguais à versão anterior.

A revisão1700 inclui58 entradas adicionais de componentes de batalha identificadas nas tabelas originais, incluindo os endereços encontrados nos fechamentos de Ino/Guy, Gaara/Shino, Guy/Shikamaru, Asuma/Kiba e Kurenai/Gaara. O conjunto estático analisado passa a438 tabelas e2655 métodos únicos com entradas compiladas; uma tabela mista foi excluída. Isso não certifica todos os golpes, combinações, modos ou bancos do jogo.

O motor 2141 agrupa comandos VIF vazios e transfere blocos de vértices contíguos em lote. O ritmo do jogo continua sendo o PAL original.

O motor 2171 reserva a memória gráfica de leitura conforme o uso. A revisão reduziu o pico de memória nos replays PAL em 2×.
