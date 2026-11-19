#!/usr/bin/env bash
# michele.sh — enxuto: perfil dev leve, VS Code (em vez de Zed), sem snapper/virtualizacao.
# Reusa lib/ do fedorapi; selecione as fases abaixo.

set -euo pipefail
IFS=$'\n\t'

export MICHELE=1

source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

# Repos extras: VS Code (Microsoft) — em vez do Terra/Zed.
if [ ! -f /etc/yum.repos.d/vscode.repo ]; then
  try_warn rpm --import https://packages.microsoft.com/keys/microsoft.asc
  cat > /etc/yum.repos.d/vscode.repo <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
  ok "vscode repo added"
fi

PHASES=(
  "01:Third-party repos (Terra, RPM Fusion, COPRs, Docker CE)"
  "02:Removal of pre-installed bloatware"
  "03:Mise + Bun + Python/uv (toolchains)"
  "04:dnf packages + opencode/omniroute/sunshine/runtime"
  "05:Codecs and video acceleration (Radeon)"
  "07:systemd services + tailscale"
  "08:Flathub + flatpaks"
  "09:Dotfiles (clone)"
  "10:GNOME (dconf)"
  "11:GNOME extensions"
  "12:Customization (OpenCode + helpers + Plymouth + fonts)"
  "15:GDM (login screen: 125% interface scaling)"
  "16:Git (identity, SSH key and HTTPS credentials)"
)

step "Starting Michele Fedora $FDC post-install (logs at: $LOG)"

for entry in "${PHASES[@]}"; do
  num="${entry%%:*}"
  desc="${entry#*:}"
  if ask_phase "$num" "$desc"; then
    source "$SCRIPT_DIR/lib/phases/$num.sh" || warn "phase $num had errors (continuing)"
  else
    ok "Skipped by user"
  fi
done

# gtk-theme-sync + titlebar (clone + install), caso a phase 12 tenha sido pulada.
step "gtk-theme-sync + titlebar"
if [ ! -x "$SUH/.local/bin/gtk-theme-sync" ]; then
  clone_repo "https://github.com/EmanuProds/gtk-theme-sync.git" "$CLONES/gtk-theme-sync" 2>/dev/null || true
  if [ -f "$CLONES/gtk-theme-sync/gtk_theme_sync.py" ]; then
    install -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$CLONES/gtk-theme-sync/gtk_theme_sync.py" "$SUH/.local/bin/gtk-theme-sync"
    install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$SUH/.config/systemd/user"
    [ -f "$CLONES/gtk-theme-sync/units/gtk-theme-sync.service" ] && install -m 644 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$CLONES/gtk-theme-sync/units/gtk-theme-sync.service" "$SUH/.config/systemd/user/"
    as_user systemctl --user daemon-reload || true
    try_warn as_user systemctl --user enable --now gtk-theme-sync.service
  fi
fi
if [ ! -x "$SUH/.local/bin/opencode-desktop-titlebar-patch" ]; then
  clone_repo "https://github.com/EmanuProds/opencode-desktop-titlebar.git" "$CLONES/titlebar" 2>/dev/null || true
  if [ -f "$CLONES/titlebar/opencode-desktop-titlebar-patch" ]; then
    install -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$CLONES/titlebar/opencode-desktop-titlebar-patch" "$SUH/.local/bin/opencode-desktop-titlebar-patch"
  fi
fi

# Kernel CachyOS como padrao (sem tuning/snapper).
step "Kernel CachyOS (default)"
if ! rpm -q kernel-cachyos-lto >/dev/null 2>&1; then
  try_warn dnf install -y kernel-cachyos-lto kernel-cachyos-lto-devel-matched || true
fi
kdef=$(ls /boot 2>/dev/null | grep 'vmlinuz.*cachy' | sort -V | tail -1 || true)
if [ -n "$kdef" ]; then try_warn grubby --set-default="/boot/$kdef" || true; ok "default kernel: $kdef"; else warn "no cachy kernel in /boot"; fi

step "Cleanup"
rm -rf "$CLONES" || true
try_warn flatpak uninstall -y --unused --system || true
ok "Done :D — reboot recommended!"