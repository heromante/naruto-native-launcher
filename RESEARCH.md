# Pesquisa técnica de Ultimate Ninja 5

Notas para quem quer reproduzir os testes ou contribuir com o port. Os resultados abaixo descrevem percursos específicos em builds de desenvolvimento. A edição de referência do inicializador é a europeia PAL SLES-55605. O alvo inicial é macOS em Apple Silicon.

## Como o projeto se divide

O inicializador Swift/AppKit verifica a ISO9660 e os hashes da edição e do ELF. A build de desenvolvimento usa código do Emotion Engine recompilado para ARM64 e um runtime que reproduz os serviços do PS2. O VIF prepara comandos e dados das unidades vetoriais, o GS é reproduzido pelo backend gráfico e o runtime também implementa partes do IOP e do áudio. Esses subsistemas têm custos e relógios diferentes.

Este repositório compila a interface e permite inspecionar a ISO. O pipeline que gera o motor específico do jogo ainda precisa ser reproduzido e documentado para uso fora do ambiente de desenvolvimento. O [ps2-web-recomp](https://github.com/snuri00/ps2-web-recomp) é a base técnica para esse trabalho. Produtos recompilados do jogo, dados extraídos e saves ficam na máquina de quem os gera.

## Campos, FPS e tempo da luta

| Medida | O que conta |
| --- | --- |
| Campos e VBlank | Cadência de vídeo da máquina simulada |
| Ciclos gráficos do jogo | Trabalho de renderização submetido pelo jogo |
| Imagens entregues à janela | Trabalho que o host conseguiu apresentar, incluindo imagens repetidas |
| Imagens distintas | Mudanças nos pixels capturados pelo medidor |

A cadência PAL observada foi de aproximadamente **50 campos/s e 25 atualizações do jogo por segundo** no combate. A edição japonesa NTSC apresentou **60 campos/s e 30 atualizações/s** na referência medida. O valor mostrado pelo compositor do Mac não mede o ritmo interno do jogo.

Nas lutas analisadas, um divisor de espera igual a dois sincronizava o ciclo gráfico com os campos. Uma captura diagnóstica de 240 campos em uma rota a 60 campos/s apresentou 120 imagens distintas, repetidas em pares. Essa relação descreve o combate observado. Filmes, telas estáticas e outros modos podem ter comportamento diferente.

Reduzir o divisor de dois para um, em um ensaio separado de 1.200 campos, aumentou as chamadas de início gráfico, do dispatcher de batalha e do relógio de 600 para 1.198. O consumo do relógio também quase dobrou. Um patch de divisor que produza mais quadros precisa ser medido também pelo tempo do combate, pelos comandos e pela animação. O lançamento de referência preserva a cadência PAL original.

## A edição japonesa e um ensaio europeu em 60 Hz

Medimos o especial conjunto Naruto e Sakura contra Shizune e Tsunade, na Vila da Folha. O segundo controle ficou neutro e nenhum comando foi inserido durante a disputa. A duração vai da pausa à retomada do relógio da batalha. As duas edições originais foram medidas na mesma build do [Play!](https://github.com/jpd002/Play-/tree/1f27232772e484bfb79364b751b84f41f4c87481). Usamos a cadência nominal registrada pelo emulador.

| Edição e execução | Campos/s | Campos entre pausa e retomada | Duração |
| --- | ---: | ---: | ---: |
| Europa original no Play! | 50 | 1.379 | 27,58 s |
| Japão original no Play! | 60 | 1.589 | 26,48 s |
| Recompilação europeia PAL | 50 | 1.382 | 27,64 s |
| Recompilação europeia em ensaio a 60 campos/s | 60 | 1.384 | 23,07 s |

A repetição da referência japonesa gerou o mesmo registro do relógio. O especial original japonês durou cerca de 4% menos que o europeu original nesse teste. A maior parte da diferença em número de campos ocorreu após a disputa de comandos. O ensaio europeu a 60 campos/s ficou 3,42 s mais curto que a edição japonesa original. Isso mostra que a troca de frequência sozinha não reproduz o comportamento regional.

Durante a luta normal, os dois originais usaram o mesmo passo de ponto fixo Q24 no relógio. O passo ocorria 25 vezes/s no PAL e 30 vezes/s no Japão no percurso medido. O relógio japonês avançou cerca de 20% mais rápido por segundo real naquele trecho. Essa proporção não deve ser extrapolada para a duração dos especiais.

## Desempenho e estabilidade

- **VIF.** Agrupar comandos vazios e copiar vetores V4-32 contíguos em lote preservou a ordem e o estado nos replays comparados. Dois microbenchmarks isolados ficaram 9,4× e 2,8× mais rápidos. A diferença de CPU no jogo completo foi pequena.
- **Memória gráfica.** Alocar buffers de leitura sob demanda reduziu o pico em 84 a 104 MB em dois pares de replays em 2×. As capturas e os estados comparados coincidiram. Em 1×, a diferença de pico foi pequena. O resultado em 2× é principalmente de memória, com intervalos de entrega próximos do controle.
- **Primeiros segundos da luta.** Em 2×, um replay manteve a cadência lógica próxima de 25 FPS enquanto o SDL recebeu cerca de 14,5 imagens/s nos dois primeiros segundos. O replay incluía a restauração de um estado, portanto a medição mistura aquecimento e preparação gráfica. Vale testar uma entrada normal em arena com janela visível.
- **Fechamentos no combate.** Alguns casos vieram de destinos de chamadas indiretas ainda ausentes do motor recompilado. Reproduzir o percurso que atingia o endereço permitiu corrigir a cobertura. Uma sequência validada passou do fim de Hinata × Neji à seleção e ao início de Kurenai × Neji no mesmo processo. Campanha completa, todas as arenas e sessões longas ainda precisam de validação.

## Por onde contribuir

1. **Geração local do motor.** Documentar dependências, versões, entrada, saída e etapas que permitem reconstruir o motor usando a ISO do jogador. Separar ferramentas públicas dos arquivos do jogo gerados localmente.
2. **Entrega de imagens.** Medir 1× e 2× separadamente. Registrar campos/s, ciclos gráficos/s, imagens entregues/s, percentil 99 dos intervalos e pico de memória. Comparar a mesma luta, arena, entrada e duração em pares, invertendo a ordem dos testes.
3. **Tempo e versões.** Para qualquer mudança de FPS, medir também o relógio da luta, a resposta do controle e a duração de um especial. Tratar PAL europeu e NTSC japonês como referências independentes.
4. **Cobertura.** Reproduzir um problema com edição, modo, personagens, arena, sequência de ações e resultado esperado. Comparar os estados e as imagens antes de declarar uma regressão corrigida.

Ao abrir uma Issue, inclua a versão do macOS, a família do chip, a resolução e os passos de reprodução. Use um trecho de log redigido, com caminhos locais, nomes de usuário e identificadores removidos. Os testes do inicializador usam fixtures sintéticas e podem ser executados sem arquivos do jogo.
