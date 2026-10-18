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
# executa um passo não-crítico: se falhar, a instalação continua (e a falha entra
# na contagem, senão a fase imprime [ OK ] com a fase furada — foi o que
# aconteceu na fase 6: zero flatpaks instalados e "[ OK ] flatpaks instalados")
FAIL_COUNT=0
try_warn() { "$@" || { warn "não-crítico, seguiu em frente: $*"; mark_fail; }; }
mark_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); }
# fecha a fase com honestidade: [ OK ] só quando nenhum passo não-crítico falhou
phase_end() { # phase_end <FAIL_COUNT do início da fase> <texto de sucesso>
  local antes="$1" texto="$2"
  if [ "$FAIL_COUNT" -eq "$antes" ]; then
    ok "$texto"
  else
    warn "$((FAIL_COUNT - antes)) passo(s) não-crítico(s) falharam nesta fase — veja o log acima"
  fi
}

# /tmp e sticky e o kernel tem fs.protected_regular=1: se o log veio de um run
# anterior sem sudo ele pertence ao usuario e o tee (mesmo rodando como root)
# nao consegue abrir com O_CREAT -> "tee: /tmp/fedorapi.log: Permissao negada".
# Log de root a gente mantem (append); log de outro dono a gente descarta.
if [ -e "$LOG" ] && [ "$(stat -c '%u' "$LOG" 2>/dev/null || echo 1)" != "0" ]; then
  rm -f "$LOG"
fi
exec > >(tee -a "$LOG") 2>&1

# --- identidade ---------------------------------------------------- #
[ "$(id -u)" -eq 0 ] || die "rode com sudo (o script altera pacotes de sistema)"
SUDO_USER="${SUDO_USER:-}"
[ -n "$SUDO_USER" ] || die "SUDO_USER indefinido"
readonly SUH="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
readonly UID_R="$(id -u "$SUDO_USER")"

read_list() { grep -vE '^\s*(#|$)' "$1" | sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//' | grep -vE '^$'; }

# --- helpers de idempotência (verificação de estado real) ---
# "instalado" aqui significa "presente no sistema", não "já tentado antes".
rpm_installed() { rpm -q "$1" >/dev/null 2>&1; }
flatpak_installed() { flatpak list --system --columns=application 2>/dev/null | grep -qx "$1"; }
# extrai o appID de uma ref flatpak, com ou sem remote/prefixo e branch/arch.
# Ex.: "flathub/org.freedesktop.Platform.ffmpeg-full/x86_64/24.08" -> "org.freedesktop.Platform.ffmpeg-full"
#      "org.remmina.Remmina" -> "org.remmina.Remmina"
flatpak_appid() {
  local ref="$1"
  # remove prefixo de remote (primeiro segmento sem ponto: flathub, fedora, oci)
  case "${ref%%/*}" in
    flathub|fedora|oci) ref="${ref#*/}" ;;
  esac
  # appID é o primeiro componente (antes da primeira /)
  printf '%s' "${ref%%/*}"
}
service_enabled() { systemctl is-enabled "$1" >/dev/null 2>&1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }
npm_global_installed() { /home/emanuel/.local/bin/mise exec -- npm ls -g --depth=0 2>/dev/null | grep -q " $1@"; }
# gopls vem do toolchain do mise (go), não do npm
gopls_installed() { ls "$SUH/.local/share/mise/installs/go/"*/bin/gopls >/dev/null 2>&1; }
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

# Limpa transação offline pendente (GNOME Software agenda updates offline; se
# o script mexer em pacotes antes do reboot, ela fica inválida e o dnf avisa).
# Só roda se houver algo pendente em /var/lib/dnf/offline.
if [ -d /var/lib/dnf/offline/packages ] && [ -n "$(ls -A /var/lib/dnf/offline/packages 2>/dev/null)" ]; then
  try_warn dnf5 offline clean
fi

# dnf: espelhos e paralelismo. Tem de vir antes do primeiro download — o dnf
# le /etc/dnf/dnf.conf a cada invocacao, entao tudo que baixa depois ja pega.
# O dnf.conf do Fedora 44 vem so com "[main]" e nenhuma opcao (conferido nesta
# maquina): sem tuning o dnf5 baixa 3 pacotes por vez, no maximo 3 por mirror,
# e escolhe o mirror na ordem do metalink. Foi o que apareceu na fase 4 de
# 2026-10-17: o rpmfusion entregou mirror da America Central/Europa, o
# ffmpeg-libs caiu para 29 KiB/s e cada pacote grande levou ~5 min, com varios
# "Curl error (28): Timeout was reached ... Less than 1000 bytes/sec transferred
# the last 30 seconds" — isso e o minrate do dnf largando o mirror lento, nao um
# travamento (a transacao seguia viva, trocando de espelho).
#   max_parallel_downloads=15   -> 15 downloads simultaneos (teto do dnf5 e 20)
#   max_downloads_per_mirror=15 -> sem isso o teto de 3 POR MIRROR anula o de cima
#   fastestmirror=True          -> libdnf5 mede latencia e fura a ordem do metalink
# setopt sem prefixo de repo grava em [main] e e idempotente (testado no 5.4.6).
# idempotência: só aplica se alguma chave ainda não estiver no valor esperado
if grep -q '^max_parallel_downloads=15' /etc/dnf/dnf.conf 2>/dev/null \
   && grep -q '^fastestmirror=True' /etc/dnf/dnf.conf 2>/dev/null; then
  ok "dnf: tuning já aplicado (15 paralelos, 15 por mirror, fastestmirror) — pulando"
else
  for kv in max_parallel_downloads=15 max_downloads_per_mirror=15 fastestmirror=True; do
    try_warn dnf config-manager setopt "$kv"
  done
  if grep -q '^max_parallel_downloads=15' /etc/dnf/dnf.conf 2>/dev/null; then
    ok "dnf: 15 downloads paralelos (15 por mirror) + fastestmirror"
  else
    warn "dnf.conf nao recebeu o tuning — confira /etc/dnf/dnf.conf"
  fi
fi

# O --repofrompath so serve na primeira instalacao: com o terra-release ja
# instalado existe /etc/yum.repos.d/terra.repo e o dnf recusa criar um segundo
# repo com o mesmo ID ("o ID esta presente mais de uma vez").
if rpm -q terra-release >/dev/null 2>&1; then
  try_warn dnf install -y terra-release terra-gpg-keys
else
  # (nota: comentario em linha propria — comentario colado depois da barra
  # invertida quebra a continuacao e o dnf recebe um argumento vazio)
  dnf install -y --nogpgcheck \
    --repofrompath "terra,https://repos.fyralabs.com/terra$FDC" \
    terra-release terra-gpg-keys
fi

# idempotência: só instala os release RPMs se ainda não estiverem presentes
rpm -q rpmfusion-free-release >/dev/null 2>&1 || dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$FDC.noarch.rpm"
rpm -q rpmfusion-nonfree-release >/dev/null 2>&1 || dnf install -y "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$FDC.noarch.rpm"

for copr in sneexy/zen-browser atim/heroic-games-launcher \
            rivenirvana/morewaita-icon-theme chronoscrat/starship \
            bieszczaders/kernel-cachyos-lto bieszczaders/kernel-cachyos-addons; do
  # idempotência: só habilita se o repo ainda não existir
  repo_file="/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:${copr/\//\:}.repo"
  if [ -f "$repo_file" ]; then
    continue
  fi
  # retries extras: os coprs hospedam no S3 (lento/timeout) e são o ponto mais
  # frágil da fase 1; o timeout global de 30s não basta para eles.
  try_warn dnf --setopt=retries=20 copr enable -y "$copr" >/dev/null 2>&1
done

# docker-ce: só adiciona se ainda não existir
if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
  try_warn dnf config-manager addrepo --overwrite \
    --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo >/dev/null 2>&1
fi

# O Google descontinuou os repos yum; o mise instala o Cloud SDK (fase 10).
ok "repos prontos"

# --------------------------------------------------------------- #
# 2. LIMPEZA DO SISTEMA (bloatware)                                #
# --------------------------------------------------------------- #
step "Fase 2/12 — removendo bloatware pré-instalado"
if [ -s "$LISTS/removals.txt" ]; then
  mapfile -t REMS < <(read_list "$LISTS/removals.txt")
  # o dnf nao expande curingas: 'libreoffice*' seria tratado como nome literal.
  # Entao resolvemos os padroes contra os pacotes realmente instalados.
  REMS_EXPANDIDOS=()
  for p in "${REMS[@]:-}"; do
    [ -z "$p" ] && continue
    if [[ $p == *'*'* ]]; then
      while IFS= read -r encontrado; do
        [ -n "$encontrado" ] && REMS_EXPANDIDOS+=("$encontrado")
      done < <(rpm -qa --qf '%{NAME}\n' | grep -E "^${p//\*/.*}$" || true)
    else
      REMS_EXPANDIDOS+=("$p")
    fi
  done
  # idempotência: só tenta remover o que ainda está instalado
  REMS_A_REMOVER=()
  for p in "${REMS_EXPANDIDOS[@]:-}"; do
    [ -z "$p" ] && continue
    rpm_installed "$p" && REMS_A_REMOVER+=("$p")
  done
  if [ "${#REMS_A_REMOVER[@]}" -eq 0 ]; then
    ok "bloatware já removido — pulando"
  else
    try_warn dnf remove -y --setopt=clean_requirements_on_remove=True "${REMS_A_REMOVER[@]}"
    ok "bloatware removido"
  fi
fi
ok "bloatware removido"

# --------------------------------------------------------------- #
# 3. PACOTES                                                       #
# --------------------------------------------------------------- #
step "Fase 3/12 — instalando pacotes (dnf)"
mapfile -t PKGS < <(read_list "$LISTS/packages.txt")
[ "${#PKGS[@]}" -gt 0 ] || die "packages.txt vazio"
# idempotência: só instala os que ainda não estão presentes
PKGS_FALTANDO=()
for p in "${PKGS[@]:-}"; do
  [ -z "$p" ] && continue
  rpm_installed "$p" || PKGS_FALTANDO+=("$p")
done
if [ "${#PKGS_FALTANDO[@]}" -eq 0 ]; then
  ok "pacotes já instalados — pulando"
else
  dnf install -y "${PKGS_FALTANDO[@]}"
  ok "pacotes instalados"
fi

# --- cola do kernel cachy (comentada linha a linha em candidates) --
# cachyos-settings fornece/obsoleta o zram-generator-defaults: os dois NAO podem
# entrar no mesmo 'dnf install' (o dnf5 aborta com "solicitações conflitantes"),
# por isso cachyos-settings saiu de packages.txt e a troca acontece aqui, de
# forma idempotente.
if ! rpm -q cachyos-settings >/dev/null 2>&1; then
  if rpm -q zram-generator-defaults >/dev/null 2>&1; then
    try_warn dnf swap -y zram-generator-defaults cachyos-settings
  else
    try_warn dnf install -y cachyos-settings
  fi
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
# 4. GRÁFICOS/CODECS (Radeon: VA/Vulkan freeworld + ffmpeg)        #
# --------------------------------------------------------------- #
step "Fase 4/12 — codecs e aceleração de vídeo"
_f0=$FAIL_COUNT
# O ffmpeg do RPM Fusion conflita com as libs "-free" que o Fedora já traz
# (libswscale-free/libavcodec-free): sem --allowerasing o dnf5 aborta com
# "solicitações conflitantes" e o ffmpeg completo não entra (é a recomendação
# oficial do RPM Fusion Howto/Multimedia).
# idempotência: só troca se o ffmpeg (RPM Fusion) ainda não estiver instalado
if ! rpm_installed ffmpeg; then
  try_warn dnf swap -y ffmpeg-free ffmpeg --allowerasing
else
  ok "ffmpeg (RPM Fusion) já instalado — pulando swap"
fi
# No Fedora 44 o mesa-va-drivers foi absorvido pelo mesa-dri-drivers: não há mais
# o que trocar (o "swap" fazia o dnf querer remover o mesa-dri-drivers e o steam
# derrubava a transação). O -freeworld instala AO LADO — repoquery confirma que
# ele não declara conflito e só exige libs + mesa-filesystem.
if ! rpm_installed mesa-va-drivers-freeworld; then
  try_warn dnf install -y mesa-va-drivers-freeworld
else
  ok "mesa-va-drivers-freeworld já instalado — pulando"
fi
# mesa-vdpau-drivers não existe mais no 44, nem o -freeworld (a troca antiga era
# letra morta). O equivalente atual para acelerar vídeo é o Vulkan freeworld.
if ! rpm_installed mesa-vulkan-drivers-freeworld; then
  try_warn dnf swap -y mesa-vulkan-drivers mesa-vulkan-drivers-freeworld --allowerasing
else
  ok "mesa-vulkan-drivers-freeworld já instalado — pulando swap"
fi
# O grupo @multimedia puxa libheif-freeworld, que hoje exige libheif 1.23.6 e o
# Fedora 44 está em 1.23.5 (libheif-ffmpeg): sem excluir, a transação inteira
# falha e NADA do grupo instala.
# idempotência: só instala o grupo se ainda não estiver instalado
if ! dnf group list --installed 2>/dev/null | grep -q '^multimedia'; then
  try_warn dnf group install -y multimedia --setopt=install_weak_deps=False \
    --exclude=PackageKit-gstreamer-plugin,libheif-freeworld
else
  ok "grupo multimedia já instalado — pulando"
fi
# libva: só instala se faltar
if ! rpm_installed libva-utils; then
  try_warn dnf install -y libva libva-utils
else
  ok "libva/libva-utils já instalados — pulando"
fi
phase_end "$_f0" "codecs/VA-API prontos"

# --------------------------------------------------------------- #
# 5. SERVIÇOS                                                      #
# --------------------------------------------------------------- #
step "Fase 5/12 — serviços systemd"
_f0=$FAIL_COUNT
# O tailscaled.service está em services.txt mas o tailscale não existe em nenhum
# repo do Fedora: sem instalar o pacote antes, o "enable --now" abaixo falha com
# "Failed to enable unit: Unit tailscaled.service does not exist" (log de hoje).
# Repo oficial do upstream, com repo_gpgcheck ligado.
if ! command -v tailscale >/dev/null 2>&1; then
  try_warn dnf config-manager addrepo --overwrite \
    --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
  try_warn dnf install -y tailscale
fi
while IFS= read -r svc; do
  [ -z "$svc" ] && continue
  # idempotência: só habilita/inicia se ainda não estiver ativo
  if service_enabled "$svc"; then
    ok "$svc já habilitado — pulando"
  else
    try_warn systemctl enable --now "$svc"
  fi
done < <(read_list "$LISTS/services.txt")
phase_end "$_f0" "serviços habilitados"

# --------------------------------------------------------------- #
# 6. FLATPAKS                                                       #
# --------------------------------------------------------------- #
step "Fase 6/12 — Flathub + flatpaks"
_f0=$FAIL_COUNT
command -v flatpak >/dev/null 2>&1 || dnf install -y flatpak
try_warn flatpak remote-add --system --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
mapfile -t FPKS < <(read_list "$LISTS/flatpak.txt")
# Um ref por chamada: um ref ruim aborta a transação INTEIRA. Foi o que o
# ffmpeg-full sem branch fez ("Várias refs correspondem...") — nenhum dos 32 apps
# instalou e a fase ainda imprimia [ OK ].
# Fedora também tem alguns apps no remote 'fedora' (OCI). Quando o appID existe
# em ambos (remmina, flatseal, calibre...), flatpak pede para escolher remote.
# Forçamos 'flathub/' quando a ref não traz prefixo explícito.
for app in "${FPKS[@]:-}"; do
  [ -z "$app" ] && continue
  # idempotência: extrai o appID (sem remote/prefixo/branch) para checar se já está instalado
  appid="$(flatpak_appid "$app")"
  if flatpak_installed "$appid"; then
    ok "$appid já instalado — pulando"
    continue
  fi
  # já vem com remote? (ex.: flathub/org.foo.Bar)
  case "$app" in
    flathub/*|fedora/*|oci:*)
      target="$app"
      ;;
    *)
      target="flathub/$app"
      ;;
  esac
  try_warn flatpak install -y --system --noninteractive "$target"
done
phase_end "$_f0" "flatpaks instalados (${#FPKS[@]} refs)"

# --------------------------------------------------------------- #
# 7. DOTFILES    (clone do repo dotfiles — fonte única)           #
# --------------------------------------------------------------- #
step "Fase 7/12 — dotfiles (clone EmanuProds/dotfiles)"
clone_repo "$DOTFILES_REPO" "$CLONES/dotfiles"
# ~/.config precisa PERTENCER ao usuário. Se um run anterior deixou a pasta como
# root (ou se o cp -a cria a pasta copiando o dono do clone), tudo que grava
# config de usuário quebra: foi o que derrubou o gcloud ("Could not create
# directory [/home/emanuel/.config/gcloud]: Permission denied"), o mise (sem
# poder escrever ~/.config/mise/config.toml não cria shims → npm/go sumiram) e o
# ~/.config/systemd. O chown -R no fim desta fase fecha o buraco de vez.
install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$SUH/.config"
install -m 644 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" \
  "$CLONES/dotfiles/home/.bashrc" "$SUH/.bashrc"
install -m 644 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" \
  "$CLONES/dotfiles/home/.shell_aliases" "$SUH/.shell_aliases"
install -m 644 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" \
  "$CLONES/dotfiles/home/gdm/watermark.png" "$SUH/.config/watermark.png"
cp -a "$CLONES/dotfiles/home/.config/." "$SUH/.config/"
chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" \
  "$SUH/.config" "$SUH/.bashrc" "$SUH/.shell_aliases" 2>/dev/null || true
# Garante ativação do mise e do starship no .bashrc (idempotente): se o dotfiles
# vier sem essas linhas (versão antiga), o usuário ainda consegue usar os
# binários instalados pelo mise no terminal.
if ! grep -q 'mise.*activate bash' "$SUH/.bashrc" 2>/dev/null; then
  printf '\n# Mise (instalado em ~/.local/bin pelo mise.run)\neval "$("$HOME/.local/bin/mise" activate bash)" 2>/dev/null || true\n' >> "$SUH/.bashrc"
fi
if ! grep -q 'starship init bash' "$SUH/.bashrc" 2>/dev/null; then
  printf '\ncommand -v starship >/dev/null 2>&1 && eval "$(starship init bash)"\n' >> "$SUH/.bashrc"
fi
chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.bashrc"
ok "dotfiles no lugar (bash, ghostty, zed, gamemode, topgrade, watermark)"

# --- plymouth: esconder a watermark e centralizar o spinner --- #
# O tema precisa ser ATIVADO (plymouth-set-default-theme) e o initramfs
# reconstruído (-R), senão as mudanças no spinner.plymouth não persistem no boot.
# Centraliza horizontal e verticalmente: HorizontalAlignment=.5 e VerticalAlignment=.5
SPINNER_CONF="/usr/share/plymouth/themes/spinner/spinner.plymouth"
if [ -f "$SPINNER_CONF" ] && grep -q '\[two-step\]' "$SPINNER_CONF"; then
  try_warn rm -f /usr/share/plymouth/themes/spinner/watermark.png
  # ancora no início da linha: evita casar DialogVerticalAlignment/TitleVerticalAlignment
  if ! grep -q '^VerticalAlignment=.5$' "$SPINNER_CONF"; then
    try_warn sed -i 's/^VerticalAlignment=.7$/VerticalAlignment=.5/' "$SPINNER_CONF"
  fi
  # HorizontalAlignment já é .5 (centro); garante caso tenha mudado
  try_warn sed -i 's/^HorizontalAlignment=.7$/HorizontalAlignment=.5/' "$SPINNER_CONF"
  # ativa o tema spinner e reconstrói o initramfs para persistir
  try_warn plymouth-set-default-theme spinner
  try_warn plymouth-set-default-theme -R spinner
  ok "plymouth spinner centralizado e ativado"
else
  warn "spinner.plymouth sem seção [two-step] (tema mudou no 44) — tweak do plymouth ignorado"
fi

# --------------------------------------------------------------- #
# 8. DCONF (restauracao)  (vem do clone do dotfiles)              #
# --------------------------------------------------------------- #
step "Fase 8/12 - restaurando GNOME (dconf dump do repo dotfiles)"
try_warn as_user dconf load / < "$CLONES/dotfiles/dconf/gnome-settings.ini"
ok "dconf restaurado"

# --------------------------------------------------------------- #
# 9. EXTENSÕES DO GNOME  (D-Bus: InstallRemoteExtension)          #
# --------------------------------------------------------------- #
mapfile -t EXT_UUIDS < <(read_list "$LISTS/extensions.txt")
step "Fase 9/12 — extensões GNOME (${#EXT_UUIDS[@]} UUIDs)"
_f0=$FAIL_COUNT
EXT_DIR="$SUH/.local/share/gnome-shell/extensions"
for uuid in "${EXT_UUIDS[@]:-}"; do
  [ -z "$uuid" ] && continue
  [ -d "$EXT_DIR/$uuid" ] && continue   # já veio de um run anterior
  # O exit code do dbus-send MENTE: o org.gnome.Shell.Extensions é ativado a cada
  # chamada, o gnome-shell extrai o zip e o serviço sai sem responder — o cliente
  # recebe "NoReply: Remote peer disconnected" mesmo com a extensão instalada.
  # (No run de hoje: 16 de 19 instalaram e o script contou 18 falhas.)
  as_user dbus-send --session --print-reply \
    --dest=org.gnome.Shell.Extensions \
    /org/gnome/Shell/Extensions \
    org.gnome.Shell.Extensions.InstallRemoteExtension string:"$uuid" >/dev/null 2>&1 || true
  # o download/extração é assíncrono: o veredito vem do disco, não do D-Bus
  for _ in $(seq 1 20); do
    [ -d "$EXT_DIR/$uuid" ] && break
    sleep 1
  done
  if [ ! -d "$EXT_DIR/$uuid" ]; then
    mark_fail
    warn "extensão não instalou (UUID existe na loja?): $uuid"
  fi
done
phase_end "$_f0" "extensões do GNOME instaladas (${#EXT_UUIDS[@]})"

# --------------------------------------------------------------- #
# 10. MISE + GLOBAIS DO NPM + LSP DE GO                            #
# --------------------------------------------------------------- #
step "Fase 10/12 — mise (node/bun/go/usage/pipx/gh) + LSPs npm"
_f0=$FAIL_COUNT
as_user bash -c 'curl -fsSL https://mise.run | sh' || warn "mise.run falhou"
if [ -x "$SUH/.local/bin/mise" ]; then
  mapfile -t TOOLS < <(read_list "$LISTS/mise.txt")
  if [ "${#TOOLS[@]}" -gt 0 ]; then
    # grava ~/.config/mise/config.toml e cria os shims em ~/.local/share/mise/shims
    # (depende do ~/.config ser do usuário — garantido na fase 7)
    try_warn as_user "$SUH/.local/bin/mise" use -g "${TOOLS[@]}"
  fi
fi
mapfile -t NPMG < <(read_list "$LISTS/npm.txt")
# idempotência: só instala os LSPs npm que ainda não estiverem globais
NPMG_FALTANDO=()
for p in "${NPMG[@]:-}"; do
  [ -z "$p" ] && continue
  npm_global_installed "$p" || NPMG_FALTANDO+=("$p")
done
if [ "${#NPMG[@]}" -gt 0 ] && [ "${#NPMG_FALTANDO[@]}" -eq 0 ]; then
  ok "LSPs npm já instalados — pulando"
elif [ "${#NPMG_FALTANDO[@]}" -gt 0 ]; then
  # via 'mise exec' em vez de 'npm' pelado: não depende de PATH nem de shim, só do
  # config global escrito logo acima. (No run de hoje o PATH apontava para um
  # ~/.local/share/mise/shims que não existia → "env: npm: Arquivo ou diretório
  # inexistente" e nenhum global/LSP foi instalado.)
  try_warn as_user "$SUH/.local/bin/mise" exec -- npm i -g --silent "${NPMG_FALTANDO[@]}"
fi
# gopls: LSP de Go (o mise já instalou o go na fase acima)
if as_user "$SUH/.local/bin/mise" exec -- go version >/dev/null 2>&1; then
  if gopls_installed; then
    ok "gopls já instalado — pulando"
  else
    try_warn as_user "$SUH/.local/bin/mise" exec -- go install golang.org/x/tools/gopls@latest
  fi
fi
# conclusão de comandos do mise (como no setup do Arch)
try_warn as_user bash -c 'mkdir -p "$HOME/.local/share/bash-completion/completions" && \
  mise completion bash --include-bash-completion-lib > "$HOME/.local/share/bash-completion/completions/mise"'
phase_end "$_f0" "toolchains prontos"

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
install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$SUH/.agents/skills"
cp -a "$CLONES/dotfiles/skills/." "$SUH/.agents/skills/"
chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.config" "$SUH/.agents"
as_user "$SUH/.local/bin/mise" exec -- npm install --silent --prefix "$SUH/.config/opencode" \
  || warn "npm opencode parcial"

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
      # dentro de try_warn: se o instalador falhar, a instalacao continua
      if curl -fsSL "$url" | bash; then
        ok "$name: installer rodou"
      else
        warn "$name: installer falhou (curl | bash)"
      fi
      ;;
  esac
done < <(read_list "$LISTS/phases.txt")

# --------------------------------------------------------------- #
# LIMPEZA FINAL                                                    #
# --------------------------------------------------------------- #
step "Cleanup"
rm -rf "$CLONES"
# NÃO rodar 'dnf autoremove -y': remove pacotes opcionais que o usuário usa
# (ex.: pipewire-codec-aptx/libfreeaptx do fone Bluetooth). O flatpak --unused
# é seguro (só remove runtimes não referenciados por nenhum app).
try_warn flatpak uninstall -y --unused --system || true
ok "concluído — log completo em $LOG"
