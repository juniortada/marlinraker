# Marlinraker Desktop

Instaladores para Ubuntu (`.deb`) e Windows (`.exe`). Eles instalam o Marlinraker com o Mainsail e permitem que a OrcaSlicer envie impressões para uma impressora Marlin ligada por USB, como se ela fosse um OctoPrint em `http://localhost:7125`.

O Marlinraker roda no Docker e liga junto com a OrcaSlicer, pelo atalho **OrcaSlicer + Marlinraker**. Esse atalho:

1. encontra sozinho a OrcaSlicer instalada no computador e a abre;
2. liga o Marlinraker, se ele ainda não estiver rodando.

Fechar a OrcaSlicer não desliga o Marlinraker nem interrompe uma impressão.

> **A impressão depende do computador.** Os comandos são enviados linha por linha pela USB. Se o computador desligar, reiniciar ou suspender (inclusive ao fechar a tampa de um notebook), a impressão para no meio. Em firmwares sem `HOTEND_IDLE_TIMEOUT`, o bico e a mesa continuam quentes nessa situação.

## Ubuntu

Requisitos: Ubuntu 22.04 ou mais novo, de 64 bits (amd64).

```bash
sudo apt install ./marlinraker-desktop_1.0.2_amd64.deb
```

O `apt` instala o Docker e o Docker Compose, se faltarem, e adiciona seu usuário ao grupo `docker`. **Saia da sessão e entre de novo** antes do primeiro uso.

A OrcaSlicer é procurada nesta ordem:

1. Flatpak (`com.orcaslicer.OrcaSlicer`);
2. comando `orca-slicer` no PATH;
3. atalho `.desktop` chamado OrcaSlicer;
4. AppImage em `~/Applications`, `~/Aplicativos`, `~/Programas`, `~/Downloads`, na área de trabalho ou em `/opt`. Se houver mais de uma, vale a versão mais nova.

Comandos no terminal:

| Comando | O que faz |
|---|---|
| `marlinraker orca` | Liga o Marlinraker e abre a OrcaSlicer (o mesmo que o atalho) |
| `marlinraker mainsail` | Liga o Marlinraker e abre o Mainsail no navegador |
| `marlinraker stop` | Desliga o Marlinraker. Recusa durante uma impressão, a menos que você use `--force` |
| `marlinraker status`, `marlinraker logs` | Mostram o estado e o log |
| `marlinraker find-orca` | Mostra qual OrcaSlicer será aberta |

Para desinstalar:

- `sudo apt remove marlinraker-desktop` mantém a configuração e os G-codes;
- `sudo apt purge marlinraker-desktop` apaga a configuração, os G-codes e a imagem.

## Windows

Requisitos: Windows 10 ou 11 de 64 bits e o Docker Desktop com o backend WSL 2, que é o padrão.

Execute `MarlinrakerDesktopSetup-1.0.2.exe`. O instalador não é assinado, então o Windows pode mostrar o aviso do SmartScreen; para continuar, clique em "Mais informações" e depois em "Executar assim mesmo". O instalador:

- confere se o Docker Desktop está instalado e oferece instalar pelo `winget`;
- instala o [usbipd-win](https://github.com/dorssel/usbipd-win), que repassa o USB da impressora ao Docker;
- cria os atalhos **OrcaSlicer + Marlinraker**, **Marlinraker (Mainsail)** e **Parar Marlinraker**;
- informa se encontrou a OrcaSlicer.

A OrcaSlicer é procurada no registro de programas instalados, em `Arquivos de Programas\OrcaSlicer`, nos atalhos do menu Iniciar e, para a versão portátil, em Downloads, Área de Trabalho e Documentos.

**Na primeira vez que você abrir o atalho:**

- **Mais de uma porta COM:** se houver mais de um dispositivo serial USB, o atalho pergunta qual é a impressora e lembra a escolha.
- **Pedido de administrador:** o Windows pede permissão uma vez para compartilhar aquela porta USB com o Docker (`usbipd bind`).

Enquanto o Marlinraker estiver ligado, **a porta COM da impressora fica indisponível para os programas do Windows**, como Pronterface ou Cura. O atalho **Parar Marlinraker** devolve a porta ao Windows.

Para desinstalar, use "Adicionar ou remover programas". O desinstalador pergunta se deve apagar a configuração e os G-codes.

## Configurar a impressora

Depois de instalar, abra o **Marlinraker (Mainsail)** e vá em *Machine* para editar os arquivos de configuração:

- `marlinraker.toml`: em `[serial]`, defina `port` e `baud_rate`.
  - **Porta:** no Ubuntu, use o caminho estável `/dev/serial/by-id/...`; no Windows, `/dev/ttyUSB0` ou `/dev/ttyACM0`.
  - **Velocidade:** use o `BAUDRATE` do firmware.
  - Com `"auto"`, o Marlinraker testa todas as portas e velocidades ao iniciar, e cada tentativa reinicia a placa.
- `printer.toml`: área de impressão, temperaturas e macros. Para impressoras delta, use `kinematics = "delta"` e `print_radius`, como em `config/printers/generic_delta.toml`.

Na OrcaSlicer, configure a conexão da impressora como **Octo/Klipper**, com o endereço `localhost:7125`.

O nome que aparece no Mainsail (e na aba Device da OrcaSlicer) é `marlinraker`. Para trocar, use a engrenagem no canto superior direito do Mainsail, depois **General → Printer Name**.

No menu de energia do Mainsail:
- **Shutdown** desliga o Marlinraker (o container). Ele volta a ligar ao abrir o atalho.
- **Reboot** e **Restart** reiniciam o Marlinraker.

## Gerar os instaladores

Tudo roda em containers. No computador, só o Docker é necessário:

```bash
./installer/build.sh
```

Os arquivos ficam em `installer/dist/`. A versão do instalador está em `installer/VERSION`, e o Mainsail embutido segue o `Dockerfile`.

## Testes

- Os scripts do Ubuntu foram verificados com `shellcheck`.
- O `.deb` passou no `lintian` e foi testado num Ubuntu 24.04 com Docker-in-Docker: instalação, grupo `docker`, `start`, API, busca da OrcaSlicer, `remove` e `purge`.
- A lógica do Windows tem testes Pester (`installer/windows/tests`) e passa no PSScriptAnalyzer, incluindo a sintaxe do Windows PowerShell 5.1.
- **O fluxo completo no Windows, com Docker Desktop, usbipd-win e uma impressora real, ainda não foi testado.**
