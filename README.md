<div align="center">
  <img src="Image/readme-preview.png" alt="DBK TX16 MK3" width="420"/>
</div>

# DBK_TX16KMK3

> Esta versao e uma adaptacao baseada no projeto/fork original `DBK` para a plataforma **TX16 MK3**, com ajustes e evolucoes para este repositorio.
>
> Fica aqui o agradecimento ao criador original pelo trabalho inicial, pela ideia do layout e pela base que tornou esta continuacao possivel.
>
> Se o projeto original tambem foi util para voce, considere prestigiar e apoiar o autor original da mesma forma sugerida por ele, inclusive com doacao quando essa opcao estiver disponivel.
>
> **Donate**  
> If you find DBK Telemetry Script useful, please consider supporting the development by donating via PayPal: `aliuge2000@163.com`  
> When donating, feel free to include your email address — I will send you new features for early testing!

Widget de telemetria para **EdgeTX** voltado ao uso com **Rotorflight** em rádios da linha **RadioMaster TX16 MK3**.

O foco deste projeto é entregar uma tela principal limpa, legível e otimizada para helicópteros, com informações de voo, estado de arm, governor, alertas sonoros e integração com as imagens do modelo no cartão SD.

## Funcionalidades

- Tela principal em layout dedicado para TX16 MK3
- Exibição em tempo real de:
  - RSSI/link quality
  - RPM
  - tensão principal
  - tensão por célula
  - tensão de BEC
  - temperatura
  - corrente
  - consumo de bateria
  - percentual de bateria
- Status de `ARM` com prioridade para `disable flags`
- Exibição do estado do `Governor`
- Contador de voos e timer de voo
- Nome do piloto usando arquivo de configuração no cartão SD
- Alertas sonoros para:
  - armado
  - desarmado
  - governor `OFF`
  - governor `SPOOLUP`
  - governor `ACTIVE`
  - mudança de profile
  - bateria baixa
- Alerta háptico triplo para bateria baixa
- Controle opcional dos LEDs do rádio:
  - cor configurável quando armado
  - cor configurável quando desarmado
  - animação na cor de desarmado em caso de `disable flag`
- Uso das imagens do modelo a partir da pasta `/IMAGES` do cartão SD
- Timer de voo por sessão
- Contagem de voos por modelo

## Requisitos

- Rádio compatível com **EdgeTX**
- Rotorflight com telemetria CRSF funcionando
- Cartão SD com suporte a widgets Lua

## Instalação

Você pode baixar a versão mais recente em `.zip` por este link:

[Baixar DBK_TX16KMK3 v1.0.5 (.zip)](https://github.com/vhuzalo/DBK_TX16KMK3/archive/refs/tags/v1.0.5.zip)

Depois de baixar:

1. Extraia o arquivo `.zip`.
2. Copie a pasta `DBK_TX16KMK3` para o cartão SD do rádio.

Copie o conteúdo deste projeto para a seguinte pasta do cartão SD:

```text
/WIDGETS/DBK_TX16KMK3/
```

Os arquivos principais do widget devem ficar assim:

```text
/WIDGETS/DBK_TX16KMK3/main.lua
/WIDGETS/DBK_TX16KMK3/config.lua
/WIDGETS/DBK_TX16KMK3/audio/
/WIDGETS/DBK_TX16KMK3/Image/
```

Para configurar o nome do piloto exibido no rodapé do widget, crie também o arquivo:

```text
/WIDGETS/DBK_TX16KMK3_config.json
```

Depois no rádio:

1. Abra a página onde deseja usar o widget.
2. Escolha um layout com suporte a widget em tela cheia.
3. Selecione o widget `DBK_TX16KMK3`.
4. Ajuste as opções conforme necessário.

### Deploy pelo computador

Em Linux, `deploy.sh` detecta automaticamente um cartão SD ou rádio EdgeTX
montado em `/run/media`, `/media` ou `/mnt`:

```bash
./deploy.sh --dry-run
./deploy.sh
```

Também é possível informar explicitamente a raiz que contém `WIDGETS/` e
`IMAGES/`:

```bash
./deploy.sh /run/media/$USER/EDGETX
```

Para instalar uma versão publicada no GitHub, use `-v`. O script apresenta os
10 releases mais recentes, baixa o pacote da versão escolhida e o instala usando
as mesmas regras do deploy local:

```bash
./deploy.sh -v
./deploy.sh -v /run/media/$USER/EDGETX
./deploy.sh -v --dry-run /run/media/$USER/EDGETX
```

Esse modo requer `curl`, `unzip` e acesso à internet.

O script compara os arquivos e copia somente os ausentes ou alterados. Os logs
de voo e `/WIDGETS/DBK_TX16KMK3_config.json` existentes no rádio são sempre
preservados.

## Imagens dos modelos

As imagens dos modelos agora são carregadas da pasta:

```text
/IMAGES/
```

O nome do arquivo deve corresponder ao nome do modelo no rádio. O caractere
inicial `>` é opcional no nome do modelo e não faz parte do nome procurado para
a imagem.

Exemplo:

- Nome do modelo no rádio: `>GOOSKYRS4`
- Arquivo da imagem: `/IMAGES/GOOSKYRS4.png`

Se a imagem com o nome do modelo não for encontrada, o widget tenta a imagem
selecionada em **Model Setup** no EdgeTX. Se ela também não estiver disponível,
usa a imagem padrão interna.

### Preparar imagens para o widget

O utilitário [`tools/redimensionar_imagem_widget.py`](tools/redimensionar_imagem_widget.py)
cria uma imagem PNG de `250x150 px`, preserva a proporção da imagem original e
centraliza o resultado em um fundo preto. Ele requer Python 3 e a biblioteca
Pillow:

```bash
python3 -m pip install Pillow
```

Na raiz do repositório, use-o informando a imagem de origem e, opcionalmente, o
arquivo de saída:

```bash
python3 tools/redimensionar_imagem_widget.py foto-do-modelo.jpg /IMAGES/GOOSKYRS4.png
```

Sem o segundo argumento, o arquivo é criado ao lado da imagem de origem com o
sufixo `_dbk.png`:

```bash
python3 tools/redimensionar_imagem_widget.py foto-do-modelo.jpg
```

Para remover automaticamente o fundo antes do redimensionamento, instale também
`rembg` e adicione `--remover-fundo`:

```bash
python3 -m pip install rembg
python3 tools/redimensionar_imagem_widget.py foto-do-modelo.png /IMAGES/GOOSKYRS4.png --remover-fundo
```

Copie o PNG gerado para `/IMAGES/` no cartão SD e dê a ele o mesmo nome do
modelo configurado no rádio, conforme os exemplos acima.

## Configuração do widget

O widget possui as seguintes opções:

- `SquareColor`: cor dos textos e elementos secundários
- `ValueColor`: cor dos valores principais
- `DispLED`: habilita ou desabilita os LEDs do rádio
- `ArmLED`: escolhe a cor dos LEDs quando o modelo está armado
- `DisarmLED`: escolhe a cor dos LEDs quando o modelo está desarmado e a cor base da animação de `disable flags`
- `UseGovernor`: habilita ou desabilita a leitura e exibição do governor
- `HoldSwitch`: chave usada para congelar mínimos e máximos
- `BatAlertPct`: percentual de bateria para disparo do alerta de bateria baixa

O valor padrão inicial para `BatAlertPct` vem de `battery_alert_pct` no arquivo de configuração. Se essa chave não existir, o padrão usado é `25`.

As opções `ArmLED` e `DisarmLED` oferecem vermelho, verde, azul, amarelo,
ciano, magenta, branco, laranja, roxo e rosa. Os padrões são azul para armado
e vermelho para desarmado. Assim como as demais opções do widget, esses valores
são persistidos pelo próprio EdgeTX e não pelo arquivo JSON.

## Configuração em JSON

O widget lê configurações do arquivo:

```text
/WIDGETS/DBK_TX16KMK3_config.json
```

Atualmente ele suporta estas chaves:

- `pilot_name`: nome mostrado no rodapé
- `battery_alert_pct`: percentual padrão do alerta de bateria
- `battery_alert_interval`: intervalo entre alertas de bateria baixa, em segundos

Exemplo:

```json
{
  "pilot_name": "Victor",
  "battery_alert_pct": 25,
  "battery_alert_interval": 10
}
```

Se o arquivo não existir, estiver vazio, ou não trouxer alguma dessas chaves, o widget usa os seguintes padrões:

```text
pilot_name = Rotorflight
battery_alert_pct = 25
battery_alert_interval = 10
```

Na inicialização, se `/WIDGETS/DBK_TX16KMK3_config.json` não existir ou estiver vazio, o próprio widget tenta criar esse arquivo automaticamente com os valores padrão.

## Novidades da v1.0.5

- reduzido o uso de memória e a criação de tabelas temporárias durante o desenho
- removida a coleta de curvas que estava marcada como desativada
- recarga do JSON reduzida para uma vez por minuto e debug limitado à inicialização
- renderização limitada a 10 FPS e geometria dos medidores reutilizada entre frames
- corrigido o comportamento de tela cheia acionado pelo toque no EdgeTX
- adicionado `deploy.sh` seguro, com detecção automática e modo `--dry-run`

## Novidades da v1.0.3

- corrigido o alerta de bateria baixa para respeitar o valor persistido em `BatAlertPct` nas opções do widget
- removida a sobrescrita em runtime do percentual de alerta a partir do JSON, evitando que o aviso continuasse disparando com valor antigo

## Novidades da v1.0.2

- `BatAlertPct` passou a usar entrada numérica para facilitar ajuste pelo scroller
- nome do piloto saiu da configuração do widget e foi movido para arquivo JSON no SD
- novo arquivo `/WIDGETS/DBK_TX16KMK3_config.json` para configurações persistentes fora da pasta do widget
- suporte às chaves `pilot_name`, `battery_alert_pct` e `battery_alert_interval`
- criação automática do arquivo de configuração com valores padrão quando ele não existir ou estiver vazio
- recarga dinâmica da configuração em tempo de execução
- extração da lógica de configuração para `config.lua`, deixando o `main.lua` mais limpo

## Telemetria esperada

O widget foi preparado para trabalhar com sensores Rotorflight/CRSF como:

- `Vbat`
- `Curr`
- `Hspd`
- `Capa`
- `Bat%`
- `Tesc`
- `1RSS`
- `RQly`
- `Thr`
- `Vbec`
- `ARM`
- `Gov`
- `Vcel`
- `PID#`
- `ARMD`

Uma forma simples de habilitar todos os sensores necessários é executar este comando no CLI:

```text
set telemetry_sensors = 3,4,5,6,7,8,43,50,60,88,90,91,99,95,96,15,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
```

## Alertas e comportamento

### Timer de voo

O campo `Time` mostra o tempo do voo atual.

- o timer começa a contar quando o modelo entra em estado armado
- o timer para quando o modelo é desarmado
- ele representa o tempo da sessão de voo atual, não um acumulado total do rádio

Isso permite usar o timer como referência rápida do voo em andamento, especialmente para gerenciamento de bateria.

### Contagem de voos por modelo

O campo `Flight` mostra dois contadores:

- o valor da esquerda representa o total acumulado de voos daquele modelo no rádio
- o valor da direita representa a quantidade de voos registrada para o modelo no contexto atual exibido pelo widget

Na prática, a contagem é feita por modelo, então cada aeronave mantém seu próprio histórico separado.

Um novo voo só é contabilizado quando há um ciclo válido de voo, evitando contagens indevidas em arm/desarm muito curtos.

### ARM e disable flags

- Quando houver `disable flags`, o texto de bloqueio tem prioridade sobre `ARMED`
- O campo usa a mesma área visual do status de arm
- `disable flags` aparecem em vermelho
- `ARMED` aparece em amarelo

### Governor

O estado do governor pode ser obtido:

- diretamente do sensor `Gov`, quando disponível
- ou inferido a partir do throttle, seguindo a lógica já usada no RFMONO

Se a opção `UseGovernor` estiver desabilitada nas configurações do widget, o script deixa de ler o governor e também desativa sua exibição e os áudios relacionados.

### Bateria baixa

Quando a bateria atinge o percentual configurado:

- o widget toca o áudio de alerta
- dispara 3 pulsos de haptic

## Observações

- Este projeto é voltado para **EdgeTX**, não Ethos
- A pasta `.vscode/` não faz parte da instalação no rádio
- A pasta `modelImage/` deixou de ser a origem principal das imagens dos modelos

## Versão

Versão atual do widget: **v1.0.5**
