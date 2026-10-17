#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

# --- caminhos ------------------------------------------------------ #
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly LISTS="$SCRIPT_DIR/lists"

# --- repos externos (fonte única; nada de dotfiles/scripts aqui) --- #
readonly DOTFILES_REPO="https://github.com/EmanuProds/dotfiles.git"
readonly ACCENT_SYNC_REPO="https://github.com/EmanuProds/accent-sync.git"
readonly TITLEBAR_REPO="https://github.com/EmanuProds/opencode-desktop-titlebar.git"
readonly CLONES="/tmp/fedorapi-clones"

readonly LOG="/tmp/fedorapi.log"
readonly FDC="$(rpm -E %fedora)"

# --- cores (definições reais; bug histórico corrigido aqui) ------- #
readonly C_RED=$'\e[1;31m' C_GRN=$'\e[1;32m' C_YEL=$'\e[1;33m' C_BLU=$'\e[1;34m' C_OFF=$'\e[0m'
step() { printf '\n%s== %s ==%s\n'    "$C_BLU" "$*" "$C_OFF"; }
ok()   { printf '%s[ OK ]%s %s\n'     "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '%s[WARN]%s %s\n'     "$C_YEL" "$C_OFF" "$*"; }
die()  { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }
# executa um passo não-crítico: se falhar, a instalação continua
try_warn() { "$@" || warn "não-crítico, seguiu em frente: $*"; }

exec > >(tee -a "$LOG") 2>&1

# --- identidade ---------------------------------------------------- #
[ "$(id -u)" -eq 0 ] || die "rode com sudo (o script altera pacotes de sistema)"
SUDO_USER="${SUDO_USER:-}"
[ -n "$SUDO_USER" ] || die "SUDO_USER indefinido"
readonly SUH="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
readonly UID_R="$(id -u "$SUDO_USER")"

read_list() { grep -vE '^\s*(#|$)' "$1" | sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//' | grep -vE '^$'; }

# executa um comando como o usuário do sudo, com ambiente utilizável (bus da sessão, PATH)
as_user() {
  runuser -u "$SUDO_USER" -- env \
    HOME="$SUH" \
    XDG_RUNTIME_DIR="/run/user/$UID_R" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_R/bus" \
    PATH="$SUH/.local/bin:$SUH/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin" \
    "$@"
}

# clone raso de um repo público de dotfiles/scripts; falha dura (é requisito)
clone_repo() {
  local url="$1" dest="$2"
  rm -rf "$dest"
  git clone --depth 1 --quiet "$url" "$dest" || die "git clone falhou: $url"
  ok "clone: $(basename "$dest") <- $url"
}

step "Iniciando fedoraPI (Fedora $FDC, log: $LOG)"

# --------------------------------------------------------------- #
# 1. REPOS      terra + rpmfusion + coprs + docker-ce + google    #
# --------------------------------------------------------------- #
step "Fase 1/12 — repos de terceiros"

dnf install -y --nogpgcheck \
  --repofrompath "terra,https://repos.fyralabs.com/terra$FDC" \
  terra-release terra-gpg-keys

dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$FDC.noarch.rpm"
dnf install -y "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$FDC.noarch.rpm"

for copr in sneexy/zen-browser atim/heroic-games-launcher \
            rivenirvana/morewaita-icon-theme chronoscrat/starship \
            bieszczaders/kernel-cachyos-lto bieszczaders/kernel-cachyos-addons; do
  try_warn dnf copr enable -y "$copr"
done

try_warn dnf config-manager addrepo --overwrite \
  --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo

# escrever o repo do Google sempre (idempotente)
cat > /etc/yum.repos.d/google-cloud-sdk.repo <<'EOF'
[google-cloud-sdk]
name=Google Cloud SDK
baseurl=https://packages.cloud.google.com/yum/repos/google-cloud-sdk-el9-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
ok "repos prontos"

# --------------------------------------------------------------- #
# 2. LIMPEZA DO SISTEMA (bloatware)                                #
# --------------------------------------------------------------- #
step "Fase 2/12 — removendo bloatware pré-instalado"
if [ -s "$LISTS/removals.txt" ]; then
  mapfile -t REMS < <(read_list "$LISTS/removals.txt")
  if [ "${#REMS[@]}" -gt 0 ]; then
    try_warn dnf remove -y --setopt=clean_requirements_on_remove=True "${REMS[@]}"
  fi
fi
ok "bloatware removido"

# --------------------------------------------------------------- #
# 3. PACOTES                                                       #
# --------------------------------------------------------------- #
step "Fase 3/12 — instalando pacotes (dnf)"
mapfile -t PKGS < <(read_list "$LISTS/packages.txt")
[ "${#PKGS[@]}" -gt 0 ] || die "packages.txt vazio"
dnf install -y "${PKGS[@]}"
ok "pacotes instalados"

# --- cola do kernel cachy (comentada linha a linha em candidates) --
if [ -f /etc/default/zram-generator ] || dnf list --installed zram-generator-defaults >/dev/null 2>&1; then
  try_warn dnf swap -y zram-generator-defaults cachyos-settings
fi
try_warn dracut -f
try_warn setsebool -P domain_kernel_load_modules on
mkdir -p /etc/dnf/libdnf5-plugins/actions.d
cat > /etc/dnf/libdnf5-plugins/actions.d/cachy-default.actions <<'EOF'
# Depois de instalar qualquer pacote kernel*, deixa o kernel CachyOS mais novo como entrada padrão do boot
post_transaction:kernel*:in::/usr/bin/sh -c /usr/bin/grubby\ --set-default=/boot/$(ls\ /boot\ |\ grep\ vmlinuz.*cachy\ |\ sort\ -V\ |\ tail\ -1)
EOF
kdef=$(ls /boot 2>/dev/null | grep 'vmlinuz.*cachy' | sort -V | tail -1 || true)
if [ -n "$kdef" ]; then
  try_warn grubby --set-default="/boot/$kdef"
  ok "kernel default: $kdef"
else
  warn "nenhum kernel cachy encontrado em /boot (instalou kernel-cachyos-lto? voltando ao Fedora)"
fi

# --------------------------------------------------------------- #
# 4. GRÁFICOS/CODECS (Radeon: VA/VDPAU freeworld + ffmpeg)         #
# --------------------------------------------------------------- #
step "Fase 4/12 — codecs e aceleração de vídeo"
try_warn dnf swap -y ffmpeg-free ffmpeg
try_warn dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
try_warn dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
try_warn dnf group install -y multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin
try_warn dnf install -y libva libva-utils
ok "codecs/VA-API prontos"

# --------------------------------------------------------------- #
# 5. SERVIÇOS                                                      #
# --------------------------------------------------------------- #
step "Fase 5/12 — serviços systemd"
while IFS= read -r svc; do
  try_warn systemctl enable --now "$svc"
done < <(read_list "$LISTS/services.txt")
ok "serviços habilitados"

# --------------------------------------------------------------- #
# 6. FLATPAKS                                                       #
# --------------------------------------------------------------- #
step "Fase 6/12 — Flathub + flatpaks"
command -v flatpak >/dev/null 2>&1 || dnf install -y flatpak
try_warn flatpak remote-add --system --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
mapfile -t FPKS < <(read_list "$LISTS/flatpak.txt")
if [ "${#FPKS[@]}" -gt 0 ]; then
  try_warn flatpak install -y --system --noninteractive "${FPKS[@]}"
fi
ok "flatpaks instalados"

# --------------------------------------------------------------- #
# 7. DOTFILES    (clone do repo dotfiles — fonte única)           #
# --------------------------------------------------------------- #
step "Fase 7/12 — dotfiles (clone EmanuProds/dotfiles)"
clone_repo "$DOTFILES_REPO" "$CLONES/dotfiles"
install -m 644 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" \
  "$CLONES/dotfiles/home/.bashrc" "$SUH/.bashrc"
install -m 644 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" \
  "$CLONES/dotfiles/home/.shell_aliases" "$SUH/.shell_aliases"
install -m 644 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" \
  "$CLONES/dotfiles/home/gdm/watermark.png" "$SUH/.config/watermark.png"
cp -a "$CLONES/dotfiles/home/.config/." "$SUH/.config/"
chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.config/ghostty" "$SUH/.config/zed" \
  "$SUH/.config/gamemode.ini" "$SUH/.config/topgrade.toml" "$SUH/.config/watermark.png" \
  "$SUH/.bashrc" "$SUH/.shell_aliases" 2>/dev/null || true
ok "dotfiles no lugar (bash, ghostty, zed, gamemode, topgrade, watermark)"

# --- plymouth: esconder a watermark e centralizar o spinner (ajuste herdado do Arch; [two-step] é o teste de compatibilidade no 44) --- #
SPINNER_CONF="/usr/share/plymouth/themes/spinner/spinner.plymouth"
if [ -f "$SPINNER_CONF" ] && grep -q '\[two-step\]' "$SPINNER_CONF"; then
  try_warn rm -f /usr/share/plymouth/themes/spinner/watermark.png
  try_warn sed -i '/\[two-step\]/,/VerticalAlignment/ s/VerticalAlignment=.7/VerticalAlignment=.5/' "$SPINNER_CONF"
  try_warn plymouth-set-default-theme -R spinner
  ok "plymouth spinner ajustado"
else
  warn "spinner.plymouth sem seção [two-step] (tema mudou no 44) — tweak do plymouth ignorado"
fi

# --------------------------------------------------------------- #
# 8. DCONF (restauração)  (vem do clone do dotfiles)              #
# --------------------------------------------------------------- #
step "Fase 8/12 — restaurando GNOME (dconf dump do repo dotfiles)"
try_warn as_user dconf load / < "$CLONES/dotfiles/dconf/gnome-settings.ini"
ok "dconf restaurado"

# --------------------------------------------------------------- #
# 9. EXTENSÕES DO GNOME  (D-Bus: InstallRemoteExtension)          #
# --------------------------------------------------------------- #
step "Fase 9/12 — extensões GNOME (19 UUIDs)"
ext_fail=0
while IFS= read -r uuid; do
  if ! as_user dbus-send --session --print-reply \
       --dest=org.gnome.Shell.Extensions \
       /org/gnome/Shell/Extensions \
       org.gnome.Shell.Extensions.InstallRemoteExtension string:"$uuid" >/dev/null 2>&1; then
    ext_fail=$((ext_fail + 1))
    warn "extensão falhou/não achou na loja: $uuid"
  fi
done < <(read_list "$LISTS/extensions.txt")
[ "$ext_fail" -eq 0 ] && ok "todas as extensões instaladas" \
  || warn "$ext_fail extensão(ões) pendentes — D-Bus precisa da sessão GNOME ativa; instale via Extension Manager se faltar"

# --------------------------------------------------------------- #
# 10. MISE + GLOBAIS DO NPM + LSP DE GO                            #
# --------------------------------------------------------------- #
step "Fase 10/12 — mise (node/bun/go/usage/pipx/gh) + LSPs npm"
as_user bash -c 'curl -fsSL https://mise.run | sh' || warn "mise.run falhou"
if [ -x "$SUH/.local/bin/mise" ]; then
  mapfile -t TOOLS < <(read_list "$LISTS/mise.txt")
  if [ "${#TOOLS[@]}" -gt 0 ]; then
    as_user "$SUH/.local/bin/mise" use -g "${TOOLS[@]}" || true
  fi
fi
mapfile -t NPMG < <(read_list "$LISTS/npm.txt")
if [ "${#NPMG[@]}" -gt 0 ]; then
  as_user npm i -g --silent "${NPMG[@]}" || warn "npm -g parcial"
fi
# gopls: LSP de Go (o mise já instalou o go na fase acima)
if as_user bash -c 'command -v go >/dev/null'; then
  try_warn as_user bash -c 'go install golang.org/x/tools/gopls@latest'
fi
# conclusão de comandos do mise (como no setup do Arch)
try_warn as_user bash -c 'mkdir -p "$HOME/.local/share/bash-completion/completions" && \
  mise completion bash --include-bash-completion-lib > "$HOME/.local/share/bash-completion/completions/mise"'
ok "toolchains prontos"

# --------------------------------------------------------------- #
# 11. OPENCODE + SCRIPTS AUXILIARES (tudo clonado dos repos)       #
# --------------------------------------------------------------- #
step "Fase 11/12 — opencode (do dotfiles) + accent-sync/titlebar (repos próprios)"

# esqueleto do opencode: config sanitizada + comandos + plugin de memória
for d in commands plugins tests; do
  [ -d "$CLONES/dotfiles/opencode/$d" ] && cp -a "$CLONES/dotfiles/opencode/$d" "$SUH/.config/opencode/"
done
for f in opencode.json AGENTS.md env.example package.json; do
  install -m 644 "$CLONES/dotfiles/opencode/config/$f" "$SUH/.config/opencode/$f"
done
# skills: vem da raiz do repo dotfiles e vai para ~/.agents/skills
# (é o caminho lido pelo opencode.json através de "skills")
install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$SUH/.agents"
cp -a "$CLONES/dotfiles/skills" "$SUH/.agents/skills"
chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.config/opencode" "$SUH/.agents"
as_user npm install --silent --prefix "$SUH/.config/opencode" || warn "npm opencode parcial"

# auxiliares + units: um repo por script
clone_repo "$ACCENT_SYNC_REPO" "$CLONES/accent-sync"
clone_repo "$TITLEBAR_REPO" "$CLONES/titlebar"
install -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" \
  "$CLONES/accent-sync/accent-sync" "$SUH/.local/bin/accent-sync"
install -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" \
  "$CLONES/titlebar/opencode-desktop-titlebar-patch" "$SUH/.local/bin/opencode-desktop-titlebar-patch"
install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$SUH/.config/systemd/user"
install -m 644 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$CLONES/accent-sync/units/"* "$SUH/.config/systemd/user/"
install -m 644 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$CLONES/titlebar/units/"* "$SUH/.config/systemd/user/"
as_user systemctl --user daemon-reload || true
for u in accent-sync.path opencode-titlebar-patch.path; do
  try_warn as_user systemctl --user enable --now "$u"
done
ok "opencode + helpers + units ok (memory.db nasce do zero; migre ~/.opencode/memory.db* do Arch se quiser histórico)"

# --------------------------------------------------------------- #
# 12. FASES DE RUNTIME (rpm do gh / AppImage / zip / curl|sh)     #
# --------------------------------------------------------------- #
step "Fase 12/12 — fases pós-dnf (phases.txt runtime)"
while IFS='|' read -r kind name url extra; do
  case "$kind" in
    rpm)
      rpm_url=$(curl -fsSL "$url" | \
        grep -oE '"browser_download_url": *"[^"]+"' | cut -d'"' -f4 | \
        grep -E "$extra" | head -1 || true)
      if [ -n "$rpm_url" ]; then
        curl -fsSL "$rpm_url" -o "/tmp/$name.rpm" && dnf install -y "/tmp/$name.rpm"
        rm -f "/tmp/$name.rpm"; ok "$name: rpm instalado ($rpm_url)"
      else warn "$name: asset não achado no release"; fi
      ;;
    appimage)
      as_user mkdir -p "$SUH/Applications" "$SUH/.local/share/applications"
      if curl -fsS --retry 2 "$url" -o /tmp/epic.appimage; then
        install -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" /tmp/epic.appimage "$SUH/Applications/$extra"
        cat > "$SUH/.local/share/applications/epic-launcher.desktop" <<EOF
[Desktop Entry]
Name=Epic Games Launcher
Exec=$SUH/Applications/$extra
Type=Application
Categories=Game;
StartupNotify=true
EOF
        chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.local/share/applications/epic-launcher.desktop"
        try_warn as_user update-desktop-database "$SUH/.local/share/applications"
        ok "$name: AppImage nativo em ~/Applications (self-updater da EGLv2)"
      else
        warn "$name: download falhou (checar conexao/endpoint)"
      fi
      rm -f /tmp/epic.appimage
      ;;
    zip)
      curl -fsSL "$url" -o "/tmp/$name.zip"
      case "$extra" in
        fonts)
          install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$SUH/.local/share/fonts"
          as_user unzip -oq "/tmp/$name.zip" -d "$SUH/.local/share/fonts/"
          try_warn as_user fc-cache -f
          try_warn as_user gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 11'
          ;;
      esac
      rm -f "/tmp/$name.zip"; ok "$name: zip aplicado"
      ;;
    sh)
      curl -fsSL "$url" | bash
      ok "$name: installer rodou"
      ;;
  esac
done < <(read_list "$LISTS/phases.txt")

# --------------------------------------------------------------- #
# LIMPEZA FINAL                                                    #
# --------------------------------------------------------------- #
step "Cleanup"
rm -rf "$CLONES"
try_warn dnf autoremove -y
try_warn flatpak uninstall -y --unused --system || true
ok "concluído — log completo em $LOG"
ok "lembrete: TODO-verify pendente na máquina real — btrbk (dnf), nomes dos pacotes Terra, kernel default após reboot"
