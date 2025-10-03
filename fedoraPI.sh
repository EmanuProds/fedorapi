#!/bin/bash
#
# Facilitate post installation Fedora Linux in minutes personalizated.
#
# Website:       https://fedoraproject.org/
# Author:        Emanuel Pereira
# Maintenance:   Emanuel Pereira
#
# ------------------------------------------------------------------------ #
# WHAT IT DOES?
# This script can be called by the normal way using "./".
#
# CONFIGURATION?
# I recommend that you open it in your favorite text editor and customize it with whatever packages you want.
#
# HOW TO USE IT?
# Examples:
# $ ./fedoraPI-personal.sh
#
# ------------------------------------------------------------------------ #
# Changelog:
#   v1.0 - 28/09/2025, Emanuel Pereira:
#	- Initial Release
#
# ------------------------------------------------------------------------ #
# Tested on:
#		Fedora 42 Workstation
#   bash 5.2.37(1)
#
# ------------------------------------------------------------------------ #
update_blotware_dependences_flathub () {
	sudo dnf upgrade --refresh -y
	sudo dnf remove rhythmbox gnome-contacts gnome-connections gnome-maps mediawriter evince totem -y
	sudo dnf install cabextract lzip p7zip p7zip-plugins unrar gnome-tweaks file-roller openssl gnome-shell-extension-appindicator gnome-shell-extension-caffeine gnome-shell-extension-gsconnect -y
	flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
	flatpak install flathub com.mattjakeman.ExtensionManager com.github.tchx84.Flatseal org.gnome.Decibels -y
}
fonts () {
	sudo dnf install fira-code-fonts jetbrains-mono-fonts-all -y
}
move_backup () {
	mkdir $HOME/Backup/containers

	sudo cp -rf /media/robert/Ventoy/Backup/.config $HOME
	sudo cp -rf /media/robert/Ventoy/Backup/.local $HOME
	sudo cp -rf /media/robert/Ventoy/Backup/.npm $HOME
	sudo cp -rf /media/robert/Ventoy/Backup/.dotnet $HOME
	sudo cp -rf /media/robert/Ventoy/Backup/.dbclient $HOME
	sudo cp -rf /media/robert/Ventoy/Backup/.expo $HOME 
	sudo cp -rf /media/robert/Ventoy/Backup/.vscode $HOME
	sudo cp -rf /media/robert/Ventoy/Backup/.bash-history $HOME
	sudo cp -rf /media/robert/Ventoy/Backup/.cargo $HOME
	sudo cp -rf /media/robert/Ventoy/Backup/.android $HOME
	sudo cp -rf /media/robert/Ventoy/Backup/.java	$HOME
	sudo cp -rf /media/robert/Ventoy/Backup/.gk $HOME
	sudo cp -rf /media/robert/Ventoy/Backup/snap $HOME/Backup
	sudo cp -rf /var/lib/docker/containers/ $HOME/Backup/containers
}
apps_and_dependencies () {
	sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
	echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc \n"|sudo tee /etc/yum.repos.d/vscode.repo	
	sudo dnf copr enable psygreg/linuxtoys -y
	sudo dnf update --refresh -y	
	sudo dnf install gnome-boxes code gparted gamemode npm git code decibels papers showtime linuxtoys -y
	flatpak install flathub -y io.gitlab.adhami3310.Converter rest.insomnia.Insomnia io.dbeaver.DBeaverCommunity 
}
finalization () {
	sudo cd ..
	sudo rm -rf post-installation_fedora
	echo Finalizado - Pressione "enter" para sair e reinicie seu computador :D; read_
}
#------------------------------------------------------------------------ #
# Commands (uncomment the ones you want to use)
#------------------------------------------------------------------------ #
update_blotware_dependences_flathub
fonts
#move_backup
apps_and_dependencies
finalization
