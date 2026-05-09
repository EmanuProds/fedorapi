#!/bin/bash
#
# Facilitate post installation Fedora Linux Workstation in minutes personalizated.
#
# Website:       https://fedoraproject.org/
# Author:        Emanuel Pereira
#
# ------------------------------------------------------------------------ #

## directorys ##
# sudo config file
SUDOERS_FILE="/etc/sudoers"

# temporary directory
TEMP_DIR="$HOME/.tmp"

temp_folder () {
    if [[ ! -d "$TEMP_DIR" ]]; then
        mkdir -p "$TEMP_DIR"
    fi

    cd "$TEMP_DIR"
}

# src directory
FPI_SRC_DIR="./src"
FPI_APPS_DIR="$FPI_SRC_DIR/apps"
FPI_BASH_DIR="$FPI_SRC_DIR/bash"
FPI_EXTENSIONS_DIR="$FPI_SRC_DIR/extensions"
FPI_GDM_DIR="$FPI_SRC_DIR/gdm"
FPI_ICONS_DIR="$FPI_SRC_DIR/icons"

# config directory
CONFIG_DIR="$HOME/.config"

# local directory
LOCAL_DIR="$HOME/.local/share"

# extensions directory
EXTENSIONS_DIR="$HOME/.local/share/gnome-shell/extensions"

# plymouth spinner directory
SPINNER_DIR="/usr/share/plymouth/themes/spinner"
SPINNER_CONFIG="$SPINNER_DIR/spinner.plymouth"

# custom icons directory
ICONS_DIR="$HOME/.local/share/icons/"

custom_icons_folder () {
    if [[ ! -d "$ICONS_DIR" ]]; then
        mkdir -p "$ICONS_DIR"
    fi
}

# theme directory
THEME_DIR="$HOME/.themes"

theme_folder () {
    if [[ ! -d "$THEME_DIR" ]]; then
        mkdir -p "$THEME_DIR"
    fi
}

## gnome extensions ##
ADW_GTK3_COLORIZER="8084"
SYSTEM_MONITOR="6807"
CAFFEINE="517"
MONITOR_VOLUME_DDCUTIL="6325"
TOUCHPAD_TOGGLE="7000"
HOT_EDGE="4222"
TASKS_PANEL="8642"
SHOTZY="9707"
JUST_PERFECTION="3843"
TILING_SHELL="7065"
GSCONNECT="1319"
BLUETOOTH_BATTERY_METER="6670"
AUTO_POWER_PROFILE="6583"
EXTENSIONS=($ADW_GTK3_COLORIZER $SYSTEM_MONITOR $CAFFEINE $MONITOR_VOLUME_DDCUTIL $TOUCHPAD_TOGGLE $HOT_EDGE $TASKS_PANEL $SHOTZY \
    $JUST_PERFECTION $TILING_SHELL $GSCONNECT $BLUETOOTH_BATTERY_METER $AUTO_POWER_PROFILE)

## terminal font colors ##
AZUL="\033[0;34m"
VERDE="\033[0;32m"
AMARELO="\033[1;33m"
VERMELHO="\033[0;31m"
RESET="\033[0m"
BOLD="\033[1m"

## dialog theme ##
cat << EOF > /tmp/theme
screen_color = (WHITE,BLACK,OFF)
dialog_color = (BLACK,WHITE,OFF)
menubox_border_color = (BLACK,WHITE,ON)
title_color = (BLACK,WHITE,ON)

item_selected_color = (WHITE,BLACK,OFF)
tag_key_color = (BLUE,WHITE,OFF)
tag_selected_color = (WHITE,BLACK,OFF)
tag_key_selected_color = (WHITE,BLACK,OFF)

button_active_color = (WHITE,BLACK,ON)
button_inactive_color = (BLACK,WHITE,OFF)
button_label_active_color = (WHITE,BLACK,ON)
button_label_inactive_color = (BLACK,WHITE,OFF)

position_indicator_color = (WHITE,BLACK,OFF)
use_shadow = OFF
shadow_color = (BLACK,BLACK,ON)
EOF

export DIALOGRC=/tmp/theme

## packages variables ##
# repositorys
RPMFUSION_FREE="https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
RPMFUSION_NONFREE="https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
TOPGRADE_REPO="lilay/topgrade"
RESOURCES_REPO="atim/resources"
ZEN_BROWSER_REPO="sneexy/zen-browser"
GPU_RECORDER_REPO="brycensranch/gpu-screen-recorder-git"
TENACITY_REPO="nielsenb/tenacity"
ANYDESK_REPO="https://keys.anydesk.com/repos/RPM-GPG-KEY"
VSCODE_REPO="[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=
https://packages.microsoft.com/keys/microsoft.asc"
DOCKER_REPO="'https://download.docker.com/linux/fedora/docker-ce.repo'"
STARSHIP_REPO="chronoscrat/starship"
JETBRAINS_FONTS_REPO="maveonair/jetbrains-mono-nerd-fonts"
GAMING_REPO="atim/heroic-games-launcher"

# system
BLOTWARE="gnome-connections gnome-contacts gnome-maps"
RPMFUSION_APPSTREAM="rpmfusion-free-appstream-data rpmfusion-nonfree-appstream-data"
FLATPAK_PACKAGE_SYSTEM="io.github.flattool.Warehouse com.github.tchx84.Flatseal it.mijorus.gearlever com.mattjakeman.ExtensionManager
com.github.tchx84.Flatseal page.codeberg.libre_menu_editor.LibreMenuEditor net.nokyan.Resources io.github.realmazharhussain.GdmSettings"
SYSTEM_PACKAGES="resources topgrade gnome-epub-thumbnailer samba-client gutenprint gutenprint-cups cups tesseract zbarimg openssl gnome-tweaks
ddcutil fastfetch btrfs-assistant btrbk snapper"
ARCHIVE="file-roller p7zip p7zip-plugins unrar"
APPIMAGE_SUPPORT="fuse fuse-libs"

# drivers
GRAPHICS_CARD_DRIVERS="mesa-vulkan-drivers vulkan-loader mesa-libGLU libva-utils"
VA_SWAP="mesa-va-drivers mesa-va-drivers-freeworld"
VDPAU_SWAP="mesa-vdpau-drivers mesa-vdpau-drivers-freeworld"
FFMPEG="ffmpeg-free ffmpeg"
FLATPAK_FFMPEG="org.freedesktop.Platform.ffmpeg-full/x86_64/24.08 org.freedesktop.Platform.ffmpeg-full/x86_64/23.08
org.freedesktop.Platform.ffmpeg-full/x86_64/22.08"
HA="ffmpeg-libs libva libva-utils"

# apps
ANYDESK_ADD="[anydesk]\nname=AnyDesk Fedora - stable\nbaseurl=http://rpm.anydesk.com/fedora/$"basearch"/\ngpgcheck=1\nrepo_gpgcheck=1\
ngpgkey=https://keys.anydesk.com/repos/RPM-GPG-KEY"
FLATPAK_APPS="io.github.diegoivan.pdf_metadata_editor com.obsproject.Studio io.github.flattool.Ignition org.pitivi.Pitivi
io.gitlab.adhami3310.Impression io.anytype.anytype org.nickvision.tubeconverter com.microsoft.Edge io.github.giantpinkrobots.varia"
APPS="anydesk remmina gparted gimp inkscape handbrake-gui zen-browser gpu-screen-recorder-gtk"

# development
VSCODE="code"
CONTAINERS="podman podman-compose docker containerd.io docker-compose docker-compose"
FLATPAK_PODMANDESKTOP="io.podman_desktop.PodmanDesktop"
DEV_APPS="gh starship"
FLATPAK_DEV_APPS="io.github.shonebinu.Brief me.iepure.devtoolbox rest.insomnia.Insomnia"
JETBRAINS_FONTS="jetbrains-mono-nerd-fonts jetbrains-mononl-nerd-fonts"
MICROSOFT_FONTS="cabextract fontconfig"
MICROSOFT_CORE_FONTS="https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-*.noarch.rpm"

# virtualization
WINBOAT="freerdp winboat-*-x86_64.rpm"

# games
GAMING="steam gamemode gamescope mangohud heroic-games-launcher-bin qt6-qtwebengine"
FLATPAK_GAMING="io.github.radiolamp.mangojuice com.steamgriddb.SGDBoop com.vysp3r.ProtonPlus com.github.Matoking.protontricks
org.prismlauncher.PrismLauncher net.retrodeck.retrodeck io.github.hedge_dev.hedgemodmanager"

# wine
WINE="wine-desktop wine-filesystem winetricks wine-mono"

# personalization
FLATPAK_THEME="org.gtk.Gtk3theme.adw-gtk3 org.gtk.Gtk3theme.adw-gtk3-dark"

## dependencies to inicialize ##
# sudo in memory
echo -e "${AMARELO}Solicitando acesso root para as operações...${RESET}"
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# shh key autenticate
echo -e "${AMARELO}Verificando conexão SSH com GitHub...${RESET}"
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo -e "${VERDE}SSH já configurado! Ignorando...${RESET}"
else
    echo -e "${AMARELO}Configurando chave SSH...${RESET}"
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/id_ed25519 2> /dev/null || echo -e "${VERMELHO}Aviso:${RESET} Arquivo ~/.ssh/id_ed25519 não encontrado."
    ssh -T git@github.com
fi

# GitHub CLI Token autenticate
echo -e "${AMARELO}Verificando autenticação do GitHub CLI...${RESET}"
if gh auth status &> /dev/null; then
    echo -e "${VERDE}GitHub CLI já está autenticado! Ignorando...${RESET}"
else
    echo -e "${AMARELO}Iniciando login no GitHub CLI...${RESET}"
    gh auth login
fi

# dialog installation
if rpm -q dialog &> /dev/null; then
    echo -e "${VERDE}O pacote dialog já está instalado. Pulando...${RESET}"
    sleep 1.5
else
    echo -e "${AMARELO}Instalando Dialog...${RESET}"
    sudo dnf install dialog -y
    sleep 1.5
fi

# update system and remove blotwares
update_configs() {
    export SUDO_ASKPASS=/usr/bin/zenity

    dialog --title "Aguarde" --infobox "\nRemovendo bloatwares..." 7 50
    sudo dnf remove -y $BLOTWARE &> /dev/null
    sleep 1

    dialog --title "Aguarde" --infobox "\nAtualizando o sistema...\nIsso pode levar alguns minutos." 7 50
    sudo dnf update --refresh -y &> /dev/null
    sleep 1

    dialog --title "Processo finalizado" --msgbox "\nO sistema foi limpo e atualizado com sucesso!" 8 45
    }

# install rpm fusion and system dependencies
dependencies() {
    export SUDO_ASKPASS=/usr/bin/zenity

    dialog --title "Aguarde" --infobox "\nInstalando adicionando asteriscos no sudo..." 7 50
    sleep 1
    if grep -q "pwfeedback" "$SUDOERS_FILE" &> /dev/null; then
        dialog --title "Interrompido" --infobox "\nOs asteriscos já estão ativados no sudo." 7 50
        sleep 1
    else
        sudo sed -i '/Defaults/a Defaults pwfeedback' "$SUDOERS_FILE" &> /dev/null

        if sudo visudo -c &> /dev/null; then
            dialog --title "Processo finalizado" --infobox "\nConfiguração aplicada com sucesso!" 7 50
            sleep 5
        else
            sudo sed -i '/Defaults pwfeedback/d' "$SUDOERS_FILE" &> /dev/null
            dialog --title "Abortado" --msgbox "\nErro ao validar o arquivo sudoers. Revertendo alterações..." 7 50
            sleep 1
        fi
    fi
    sleep 1

    dialog --title "Aguarde" --infobox "\nInstalando repositórios RPM Fusion..." 7 50
    sudo dnf install -y $RPMFUSION_FREE $RPMFUSION_NONFREE $RPMFUSION_APPSTREAM &> /dev/null
    sudo dnf check-update &> /dev/null
    sleep 1

    dialog --title "Aguarde" --infobox "\nInstalando e configurando dependências do sistema..." 7 50
    sudo dnf copr enable -y $TOPGRADE_REPO &> /dev/null
    sudo dnf copr enable -y $RESOURCES_REPO &> /dev/null
    sudo dnf install -y $SYSTEM_PACKAGES $ARCHIVE $APPIMAGE_SUPPORT &> /dev/null
    sudo systemctl enable --now cups &> /dev/null
    sudo systemctl enable --now snapper-timeline.timer &> /dev/null
    sudo systemctl enable --now snapper-cleanup.timer &> /dev/null
    sudo timedatectl set-local-rtc 0 --adjust-system-clock &> /dev/null
    sleep 1

    dialog --title "Aguarde" --infobox "\nConfigurando e Instalando flatpaks do sistema..." 7 50
    flatpak remote-delete fedora &> /dev/null
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo &> /dev/null
    flatpak install flathub -y $FLATPAK_PACKAGE_SYSTEM &> /dev/null
    sleep 1

    dialog --title "Processo finalizado" --msgbox "\nRepositórios e dependências instalados com sucesso!" 8 45
}

# install graphics drivers and enable video acceleration
video_multimedia() {
    export SUDO_ASKPASS=/usr/bin/zenity

    dialog --title "Aguarde" --infobox "\nInstalando drivers de vídeo AMD..." 7 50
    sudo dnf install -y $GRAPHICS_CARD_DRIVERS &> /dev/null
    sleep 1

    dialog --title "Aguarde" --infobox "\nAdicionando aceleração de vídeo..." 7 50
    sudo dnf swap $VA_SWAP -y --allowerasing &> /dev/null
    sudo dnf swap $VDPAU_SWAP -y --allowerasing &> /dev/null
    sudo dnf install -y $HA &> /dev/null
    sleep 1

    dialog --title "Aguarde" --infobox "\nAdicionando codecs proprietários..." 7 50
    flatpak install flathub -y $FLATPAK_FFMPEG &> /dev/null
    sudo dnf swap $FFMPEG -y --allowerasing &> /dev/null
    sudo dnf update -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin &> /dev/null
    sleep 1

    dialog --title "Processo finalizado" --msgbox "\nOs drivers de vídeo foram configurados com sucesso!" 8 45
}

# apps and utilities
apps_and_utilities() {
    export SUDO_ASKPASS=/usr/bin/zenity

    dialog --title "Aguarde" --infobox "\nAdicionando AnyDesk ao repositório do sistema..." 7 50
    sudo rpmkeys --import $ANYDESK_REPO &> /dev/null
    echo -e $ANYDESK_ADD | sudo tee /etc/yum.repos.d/AnyDesk-Fedora.repo &> /dev/null
    sleep 1

    dialog --title "Aguarde" --infobox "\nInstalando LinuxToys..." 7 50
    curl -fsSL https://linux.toys/install.sh | bash &> /dev/null
    sleep 1

    dialog --title "Aguarde" --infobox "\nInstalando aplicativos essenciais..." 7 50
    sudo dnf copr enable -y $TENACITY_REPO &> /dev/null
    sudo dnf copr enable -y $GPU_RECORDER_REPO &> /dev/null
    sudo dnf install -y $APPS &> /dev/null
    flatpak install flathub -y $FLATPAK_APPS &> /dev/null
    sleep 1

    dialog --title "Processo finalizado" --msgbox "\nOs apps foram instalados com sucesso!" 8 45
}

# development dependencies
development() {
    export SUDO_ASKPASS=/usr/bin/zenity

    dialog --title "Aguarde" --infobox "\nInstalando plugins..." 7 50
    cp $FPI_BASH_DIR/.bashrc $HOME &> /dev/null
    cp $FPI_BASH_DIR/.bash_aliases $HOME &> /dev/null
    cp $FPI_BASH_DIR/.blerc $HOME &> /dev/null
    cp $FPI_BASH_DIR/.booster $HOME &> /dev/null

    git clone --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git  &> /dev/null
    make -C ble.sh install PREFIX=~/.local &> /dev/null
    sudo dnf install -y dnf-plugins-core &> /dev/null
    sudo dnf install -y android-tools python3-pip &> /dev/null
    sleep 1

    dialog --title "Aguarde" --infobox "\nInstalando ZED IDE..." 7 50
    curl -fsSL https://zed.dev/install.sh | sh &> /dev/null
    sleep 1

    dialog --title "Aguarde" --infobox "\nInstalando Microsoft VSCode..." 7 50
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc &> /dev/null
    sudo echo -e $VSCODE_REPO | sudo tee /etc/yum.repos.d/vscode.repo &> /dev/null
    sudo dnf install -y $VSCODE &> /dev/null
    sleep 1

    dialog --title "Aguarde" --infobox "\nInstalando containers e suas dependências..." 7 50
    sudo dnf install -y $CONTAINERS &> /dev/null
    flatpak install flathub -y $FLATPAK_PODMANDESKTOP &> /dev/null
    sudo systemctl start docker &> /dev/null
    sudo systemctl enable docker &> /dev/null
    sudo usermod -aG docker $USER &> /dev/null
    sleep 1

    dialog --title "Aguarde" --infobox "\nHabilitando o docker..." 7 50
    sudo systemctl start docker &> /dev/null
    sudo systemctl enable docker &> /dev/null
    sudo groupadd docker &> /dev/null
    sudo usermod -aG docker $USER &> /dev/null
    sleep 1

    dialog --title "Aguarde" --infobox "\nInstalando e configurando o mise..." 7 50
    curl -fsSL https://mise.run/bash | sh &> /dev/null
    cp $FPI_BASH_DIR/.bashrc $HOME &> /dev/null
    source $HOME/.bashrc &> /dev/null
    mkdir -p $LOCAL_DIR/bash-completion/completions/
    mise completion bash --include-bash-completion-lib > ~/.local/share/bash-completion/completions/mise
    sleep 1

    dialog --title "Aguarde" --infobox "\nInstalando dependências de programação via mise..." 7 50
    mise use -g usage &> /dev/null
    mise use -g node@lts &> /dev/null
    mise use -g opencode &> /dev/null
    mise use -g java@temurin-8 &> /dev/null
    sleep 1

    dialog --title "Aguarde" --infobox "\nInstalando ferramentas para desenvolvimento..." 7 50
    sudo dnf copr enable -y $STARSHIP_REPO &> /dev/null
    source $HOME/.bashrc &> /dev/null
    sudo dnf install -y $DEV_APPS &> /dev/null
    flatpak install flathub -y $FLATPAK_DEV_APPS &> /dev/null
    sleep 1

    dialog --title "Aguarde" --infobox "\nInstalando JetBrains Mono Nerd Font..." 7 50
    sudo dnf copr enable -y $JETBRAINS_FONTS_REPO &> /dev/null
    sudo dnf install -y $JETBRAINS_FONTS &> /dev/null
    gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 11'
    sleep 1

    dialog --title "Aguarde" --infobox "\nInstalando fontes da Microsoft..." 7 50
    sudo dnf install -y $MICROSOFT_FONTS &> /dev/null
    sudo dnf install -y $MICROSOFT_CORE_FONTS &> /dev/null
    sleep 1

    dialog --title "Processo finalizado" --msgbox "\nO seu sistema está pronto para desenvolvimento!" 8 45
}

# installation winboat and dependencies
winboat (){
    export SUDO_ASKPASS=/usr/bin/zenity
    tput civis

    dialog --title "Aguarde" --infobox "\nInstalando Winboat..." 7 50
    temp_folder
    gh release download --repo TibixDev/winboat --pattern "winboat-*-x86_64.rpm" &> /dev/null
    sudo dnf install -y $WINBOAT &> /dev/null
    cd $HOME
    sleep 1

    dialog --title "Processo finalizado" --msgbox "\nO WinBoat foi instalado com sucesso!" 8 45
}

# gaming dependencies
gaming() {
    export SUDO_ASKPASS=/usr/bin/zenity

    dialog --title "Aguarde" --infobox "\nInstalando Steam e Heroic Games Launcher..." 7 50
    sudo dnf copr enable -y $GAMING_REPO &> /dev/null
    sudo dnf install -y $GAMING &> /dev/null
    sleep 1

    dialog --title "Aguarde" --infobox "\nInstalando dependências para jogos..." 7 50
    flatpak install flathub -y $FLATPAK_GAMING &> /dev/null
    sleep 1

    dialog --title "Processo finalizado" --msgbox "\nO seu sistema está pronto para jogos!" 8 45
}

# wine dependencies
wine() {
    export SUDO_ASKPASS=/usr/bin/zenity

    dialog --title "Aguarde" --infobox "\nInstalando o Wine e suas dependências..." 7 50
    sudo dnf install -y $WINE &> /dev/null
    sleep 1

    dialog --title "Processo finalizado" --msgbox "\nO Wine foi instalado com sucesso!" 8 45
}

# personalize system and themes
personalize() {
    export SUDO_ASKPASS=/usr/bin/zenity

    dialog --title "Aguarde" --infobox "\nPersonalizando o sistema e temas..." 7 50
    custom_icons_folder
    cp -r $FPI_EXTENSIONS_DIR/gradia-* $EXTENSIONS_DIR &> /dev/null
    cp $FPI_GDM_DIR/.watermark.png $CONFIG_DIR &> /dev/null
    cp -r $FPI_ICONS_DIR/Adwaita-* $ICONS_DIR &> /dev/null
    cp -r $FPI_ICONS_DIR/MoreWaita $ICONS_DIR &> /dev/null
    cp $FPI_ICONS_DIR/.folder-*.svg $HOME &> /dev/null
    cp -r $FPI_SRC_DIR/autostart $CONFIG_DIR &> /dev/null
    cp -r $FPI_SRC_DIR/applications $LOCAL_DIR &> /dev/null
    cp -r $FPI_APPS_DIR/. $CONFIG_DIR &> /dev/null

    temp_folder
    gh release download --repo lassekongo83/adw-gtk3 --pattern "adw-gtk3v*.tar.xz" &> /dev/null
    tar -xf adw-gtk3v*.tar.xz -C $THEME_DIR &> /dev/null
    cd $HOME
    flatpak install flathub -y $FLATPAK_THEME &> /dev/null

    gsettings set org.gnome.desktop.interface gtk-theme "Adw-gtk3-dark" &> /dev/null
    gsettings set org.gnome.desktop.interface icon-theme "Adwaita-slate" &> /dev/null
    sleep 1

    dialog --title "Aguarde" --infobox "\nInstalando extensões no gnome..." 7 50
    pip install -q gnome-extensions-cli &> /dev/null
    for ext in "${EXTENSIONS[@]}"; do
        (gnome-extensions-cli install "$ext" && gnome-extensions-cli enable "$ext") &> /dev/null
    done
    sleep 1

    dialog --title "Aguarde" --infobox "\nConfigurando Plymouth..." 7 50
    sudo rm $SPINNER_DIR/watermark.png &> /dev/null
    sudo sed -i '/\[two-step\]/,/VerticalAlignment/ s/VerticalAlignment=.7/VerticalAlignment=.5/' $SPINNER_CONFIG
    sudo plymouth-set-default-theme -R spinner &> /dev/null
    sleep 1

    dialog --title "Processo finalizado" --msgbox "\nO sistema foi personalizado com sucesso!" 8 45
}

# system cleanup
cleanup() {
    export SUDO_ASKPASS=/usr/bin/zenity

    dialog --title "Aguarde" --infobox "\nLimpando cache e pacotes orfãos do sistema..." 7 50
    sudo dnf clean all &> /dev/null
    sudo dnf autoremove -y &> /dev/null
    cd $HOME
    sudo rm -rf $TEMP_DIR
    sleep 1
}

## script ui ##
# welcome screen
tput civis
TITULO="
███████╗███████╗██████╗░░█████╗░██████╗░░█████╗░  ██████╗░██╗
██╔════╝██╔════╝██╔══██╗██╔══██╗██╔══██╗██╔══██╗  ██╔══██╗██║
█████╗░░█████╗░░██║░░██║██║░░██║██████╔╝███████║  ██████╔╝██║
██╔══╝░░██╔══╝░░██║░░██║██║░░██║██╔══██╗██╔══██║  ██╔═══╝░██║
██║░░░░░███████╗██████╔╝╚█████╔╝██║░░██║██║░░██║  ██║░░░░░██║
╚═╝░░░░░╚══════╝╚═════╝░░╚════╝░╚═╝░░╚═╝╚═╝░░╚═╝  ╚═╝░░░░░╚═╝

By: EmanuProds
"
dialog --infobox "$TITULO" 11 65
sleep 5

# loop menu #
while true; do
    OPTIONS=$(dialog --stdout \
        --backtitle "Fedora Linux Workstation - Script de Pós-Instalação" \
        --menu "Escolha uma opção:" \
        0 0 8 \
        1 "Atualizar e remover blotwares do sistema" \
        2 "Instalar repositórios e dependências do sistema" \
        3 "Configurar drivers de vídeo e aceleração" \
        4 "Instalar apps e ferramentas" \
        5 "Instalar ferramentas de desenvolvimento" \
        6 "Instalar e configurar o WinBoat" \
        7 "Instalar e configurar suporte a jogos" \
        8 "Instalar e configurar o Wine" \
        9 "Personalizar o sistema" \
        0 "Limpar cache e sair")

    [ $? -ne 0 ] && break

    # menu options
    case $OPTIONS in
        1)
            update_configs
            ;;
        2)
            dependencies
            ;;
        3)
            video_multimedia
            ;;
        4)
            apps_and_utilities
            ;;
        5)
            development
            ;;
        6)
            winboat
            ;;
        7)
            gaming
            ;;
        8)
            wine
            ;;
        9)
            personalize
            ;;
        0)
            cleanup
            break
    esac
done

clear
echo -e "${VERDE}Script finalizado! É fortemente recomendado que reinicie o seu sistema -_^${RESET}"
