# Sofabox

Transforma um portátil (ou PC) antigo com Linux numa box de multimédia ligada à TV:

- **Kodi** arranca em ecrã inteiro quando o portátil liga, sem ambiente de trabalho pelo meio.
- **qBittorrent** corre em segundo plano, com uma página web para adicionares torrents a partir do telemóvel.
- Os downloads (mesmo os que ainda estão a descarregar) aparecem no Kodi em **Vídeos > Ficheiros > Torrent Downloads**.
- Fechar a tampa do portátil **não** o põe a dormir.

Funciona em Debian, Ubuntu, Linux Mint e outras distribuições baseadas em apt.

---

## Índice

1. [Requisitos](#requisitos)
2. [Instalação](#instalação)
3. [Primeiro arranque](#primeiro-arranque)
4. [Adicionar torrents pelo telemóvel](#adicionar-torrents-pelo-telemóvel)
5. [Ver enquanto descarrega](#ver-enquanto-descarrega)
6. [Controlar o Kodi](#controlar-o-kodi)
7. [Opções de instalação](#opções-de-instalação)
8. [O que o script altera](#o-que-o-script-altera)
9. [Comandos úteis](#comandos-úteis)
10. [Resolução de problemas](#resolução-de-problemas)
11. [Desinstalar](#desinstalar)
12. [Uso responsável](#uso-responsável)

---

## Requisitos

- Portátil/PC com Debian 11+, Ubuntu 20.04+, Linux Mint 20+ (ou outra distro com `apt`)
- Ligação à internet durante a instalação
- Um utilizador normal com acesso a `sudo`
- Cabo HDMI para a TV
- Espaço em disco livre para os downloads

## Instalação

Abre um terminal **no portátil que vai ficar ligado à TV** e escolhe uma das opções.

### Opção A: um só comando

```bash
curl -fsSL https://raw.githubusercontent.com/DjNysa/sofabox/main/install.sh | sudo bash
```

> Se o `curl` não estiver instalado: `sudo apt install -y curl`

### Opção B: com git

```bash
sudo apt install -y git
git clone https://github.com/DjNysa/sofabox.git
cd sofabox
sudo bash install.sh
```

Durante a instalação:

1. Vai pedir uma **palavra-passe para a página de torrents** (mínimo 6 caracteres).
2. No fim mostra o endereço para abrires no telemóvel, por exemplo `http://192.168.1.50:8080`. Aponta-o.
3. Reinicia: `sudo reboot`

### Instalar a partir de outro PC (por SSH)

Se o portátil tiver SSH ativo (`sudo apt install -y openssh-server`), podes fazer tudo a partir do teu outro PC:

```bash
ssh utilizador@IP-DO-PORTATIL
curl -fsSL https://raw.githubusercontent.com/DjNysa/sofabox/main/install.sh | sudo bash
sudo reboot
```

## Primeiro arranque

Depois de reiniciar, o portátil arranca diretamente no Kodi. Não aparece o ambiente de trabalho. Se quiseres voltar a ele, vê [Comandos úteis](#comandos-úteis).

## Adicionar torrents pelo telemóvel

1. Liga o telemóvel à **mesma rede Wi-Fi** que o portátil.
2. Abre no browser o endereço que o script mostrou (ex.: `http://192.168.1.50:8080`).
3. Entra com o utilizador `admin` e a palavra-passe que escolheste.
4. Toca no ícone **+** / link e cola um link magnet ou um URL de `.torrent`, ou envia um ficheiro `.torrent`.
5. Dica: adiciona a página ao ecrã principal do telemóvel para abrir como se fosse uma app.

Também podes usar apps como **qBittorrent Controller** (Android) ou **qBitControl** (iOS) apontadas para o mesmo endereço.

Os ficheiros ficam em `~/Downloads/Torrents` no portátil.

## Ver enquanto descarrega

1. Ao adicionar o torrent, marca **"Download in sequential order"** e **"Download first and last pieces first"**.
   Num torrent já a correr: toque longo (ou clique direito) > ativa as mesmas duas opções.
2. Na TV vai a **Vídeos > Ficheiros > Torrent Downloads** e abre o ficheiro.
3. Normalmente dá para começar depois de alguns por cento. Se parar ou engasgar, pausa e deixa descarregar mais um pouco.

## Controlar o Kodi

- **Teclado ou rato USB**, ou um "air mouse" USB barato (funciona como comando).
- **Telemóvel como comando**: no Kodi vai a **Definições > Serviços > Controlo**, ativa **Permitir controlo remoto via HTTP**, define utilizador e palavra-passe, e usa a app oficial **Kore** (Android) ou **Official Kodi Remote** (iOS).
- O comando da TV via HDMI-CEC raramente funciona em portáteis (falta o hardware CEC).

## Opções de instalação

Podes mudar a porta, o utilizador da página web ou passar a palavra-passe sem ser perguntada:

```bash
sudo WEBUI_PORT=9090 WEBUI_USER=pedro bash install.sh
```

| Variável | Padrão | Para quê |
|---|---|---|
| `WEBUI_PORT` | `8080` | Porta da página de torrents |
| `WEBUI_USER` | `admin` | Utilizador da página de torrents |
| `WEBUI_PASS` | (pergunta) | Palavra-passe da página de torrents |

Por omissão o Kodi corre com o utilizador que chamou o `sudo`. Para outro: `sudo bash install.sh outro_utilizador`.

## O que o script altera

- Instala `kodi`, `qbittorrent-nox`, um servidor X mínimo e áudio (PulseAudio/ALSA).
- Cria `~/Downloads/Torrents` (e `.incomplete` para ficheiros a meio).
- Escreve `~/.config/qBittorrent/qBittorrent.conf` (guarda cópia se já existir).
- Adiciona a pasta de downloads a `~/.kodi/userdata/sources.xml` (guarda cópia se já existir).
- Cria os serviços `sofabox-kodi` e `sofabox-torrent` e ativa-os no arranque.
- Muda o arranque para modo consola (`multi-user.target`) para o Kodi ocupar o ecrã.
- Ignora a tampa do portátil (`/etc/systemd/logind.conf.d/10-sofabox.conf`).
- Permite iniciar o X a partir de um serviço (`/etc/X11/Xwrapper.config`).

Não instala add-ons, scrapers nem indexadores.

## Comandos úteis

| O quê | Comando |
|---|---|
| Reiniciar o Kodi | `sudo systemctl restart sofabox-kodi` |
| Reiniciar o qBittorrent | `sudo systemctl restart sofabox-torrent` |
| Não arrancar o Kodi no boot | `sudo systemctl disable sofabox-kodi` |
| Voltar ao ambiente de trabalho no boot | `sudo systemctl set-default graphical.target` |
| Ver erros | `journalctl -u sofabox-kodi -u sofabox-torrent -e` |
| Ver o IP do portátil | `hostname -I` |

Para chegar a um terminal com o Kodi no ecrã: **Ctrl+Alt+F2** e faz login. **Ctrl+Alt+F7** volta ao Kodi.

## Resolução de problemas

**O telemóvel não abre a página de torrents**
- Confirma que estão na mesma rede e que o IP está certo (`hostname -I`).
- Vê se o serviço corre: `systemctl status sofabox-torrent`.
- Se tiveres firewall: `sudo ufw allow 8080/tcp`.

**Ecrã preto ou o Kodi não arranca**
- `journalctl -u sofabox-kodi -e` mostra o erro.
- Em placas gráficas antigas pode faltar firmware: `sudo apt install firmware-linux` (Debian) ou `sudo ubuntu-drivers install` (Ubuntu).

**Sem som pela TV**
- No Kodi: **Definições > Sistema > Áudio > Dispositivo de saída** e escolhe a saída HDMI.

**Esqueci-me da palavra-passe da página de torrents**
- Volta a correr o instalador. Ele pergunta uma nova e guarda cópia da configuração antiga.

**O IP do portátil muda**
- Define um IP fixo para o portátil nas definições do teu router (reserva DHCP).

## Desinstalar

```bash
sudo systemctl disable --now sofabox-kodi sofabox-torrent
sudo rm /etc/systemd/system/sofabox-kodi.service /etc/systemd/system/sofabox-torrent.service
sudo rm /etc/systemd/logind.conf.d/10-sofabox.conf
sudo systemctl set-default graphical.target
sudo systemctl daemon-reload
# opcional: sudo apt remove kodi qbittorrent-nox
sudo reboot
```

Os teus downloads em `~/Downloads/Torrents` não são apagados.

## Uso responsável

- A página de torrents é só para a tua rede de casa. **Não abras a porta 8080 no router.**
- Usa o Sofabox para conteúdo que tens direito a ver: filmes em domínio público ou Creative Commons (por exemplo Internet Archive e os filmes abertos da Blender), ISOs de Linux e os teus próprios ficheiros.

## Licença

MIT. Vê [LICENSE](LICENSE).
