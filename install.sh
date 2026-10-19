#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

PHASES=(
  "01:Repos de terceiros (Terra, RPM Fusion, COPRs, Docker CE)"
  "02:Remoção de bloatware pré-instalado"
  "03:Mise (node/bun/go/usage/pipx/gh)"
  "04:Pacotes dnf + opencode/omniroute/sunshine/runtime"
  "05:Codecs e aceleração de vídeo (Radeon)"
  "06:Virtualização (virt-manager + libvirt + qemu-kvm)"
  "07:Serviços systemd + dnsmasq"
  "08:Flathub + flatpaks"
  "09:Dotfiles (clone)"
  "10:GNOME (dconf)"
  "11:Extensões GNOME"
  "12:Customization (OpenCode + helpers + Plymouth + fonts)"
  "13:LSPs (npm) + gopls"
  "14:Tuning (kernel + split-lock + BBR3 + snapper + Secure Boot)"
  "15:GIMP PhotoGIMP + Inkscape (adw-inkscape)"
)

step "Iniciando pós instalação customizada do Fedora $FDC (logs em: $LOG)"

for entry in "${PHASES[@]}"; do
  num="${entry%%:*}"
  desc="${entry#*:}"
  if ask_phase "$num" "$desc"; then
    source "$SCRIPT_DIR/lib/phases/$num.sh"
  else
    ok "Ignorado pelo usuário"
  fi
done

step "Limpeza"
rm -rf "$CLONES"
try_warn flatpak uninstall -y --unused --system || true
ok "Concluído :D — Recomendo fortemente que reinicie seu Fedora para efetivar as alterações!"
