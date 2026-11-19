#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

PHASES=(
  "01:Third-party repos (Terra, RPM Fusion, COPRs, Docker CE)"
  "02:Removal of pre-installed bloatware"
  "03:Mise + Bun + Python/uv (toolchains)"
  "04:dnf packages + opencode/omniroute/sunshine/runtime"
  "05:Codecs and video acceleration (Radeon)"
  "06:Virtualization (virt-manager + libvirt + qemu-kvm)"
  "07:systemd services + tailscale"
  "08:Flathub + flatpaks"
  "09:Dotfiles (clone)"
  "10:GNOME (dconf)"
  "11:GNOME extensions"
  "12:Customization (OpenCode + helpers + Plymouth + fonts)"
  "14:Tuning (kernel + split-lock + BBR3 + snapper + Secure Boot)"
  "15:GIMP PhotoGIMP + Inkscape (adw-inkscape)"
  "16:GDM (login screen: 125% interface scaling)"
  "17:Git (identity, SSH key and HTTPS credentials)"
)

step "Starting custom Fedora $FDC post-install (logs at: $LOG)"

for entry in "${PHASES[@]}"; do
  num="${entry%%:*}"
  desc="${entry#*:}"
  if ask_phase "$num" "$desc"; then
    source "$SCRIPT_DIR/lib/phases/$num.sh"
  else
    ok "Skipped by user"
  fi
done

step "Cleanup"
rm -rf "$CLONES"
try_warn flatpak uninstall -y --unused --system || true
ok "Done :D — I strongly recommend rebooting your Fedora to apply the changes!"
