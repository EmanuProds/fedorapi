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
# Com 'set -e' qualquer comando nu que falhe ENCERRA o script. Quando esse
# comando ainda redireciona a saida, o script morre em silencio e o log
# termina sem explicar nada (aconteceu na fase 11). O trap ERR com errtrace
# imprime a linha exata culprit antes de sair.
set -o errtrace
trap 'rc=$?; printf "\n%s[FATAL]%s linha %s devolveu %s — script encerrado por set -e\n" \
  "$C_RED" "$C_OFF" "$LINENO" "$rc" >&2
  printf "%s        comando: %s%s\n" "$C_YEL" "${BASH_COMMAND:-desconhecido}" "$C_OFF" >&2
  exit "$rc"' ERR
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
npm_global_installed() { "$SUH/.local/bin/mise" exec -- npm ls -g --depth=0 2>/dev/null | grep -q " $1@"; }
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
# Com retry e timeout: redes lentas/Instáveis não devem derrubar a instalação.
clone_repo() {
  local url="$1" dest="$2" tentativas=3 timeout_seg=120
  rm -rf "$dest"
  for i in $(seq 1 "$tentativas"); do
    if timeout "$timeout_seg" git clone --depth 1 --quiet "$url" "$dest" 2>/dev/null; then
      ok "clone: $(basename "$dest") <- $url"
      return 0
    fi
    warn "git clone falhou (tentativa $i/$tentativas): $url — aguardando 5s"
    sleep 5
  done
  die "git clone falhou após $tentativas tentativas: $url"
}

step "Iniciando fedoraPI (Fedora $FDC, log: $LOG)"

# --------------------------------------------------------------- #
# 1. REPOS      terra + rpmfusion + coprs + docker-ce + google    #
# --------------------------------------------------------------- #
step "Fase 1/13 — repos de terceiros"

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
  ok "terra-release já instalado — pulando"
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

for copr in sneexy/zen-browser \
            rivenirvana/morewaita-icon-theme chronoscrat/starship atim/resources \
            atim/lazydocker \
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
# coprs/docker-ce/terra/rpmfusion: já guardados acima; silêncio aqui.
ok "repos prontos"

# --------------------------------------------------------------- #
# 2. LIMPEZA DO SISTEMA (bloatware)                                #
# --------------------------------------------------------------- #
step "Fase 2/13 — removendo bloatware pré-instalado"
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
step "Fase 3/13 — instalando pacotes (dnf)"
mapfile -t PKGS < <(read_list "$LISTS/packages.txt")
[ "${#PKGS[@]}" -gt 0 ] || die "packages.txt vazio"
# idempotência: só instala os que ainda não estão presentes
PKGS_FALTANDO=()
for p in "${PKGS[@]:-}"; do
  [ -z "$p" ] && continue
  rpm_installed "$p" || PKGS_FALTANDO+=("$p")
done

# Um nome inexistente no repositório aborta a transação INTEIRA — foi o que
# aconteceu com "adw-gtk3" (o pacote se chama adw-gtk3-theme). Antes de
# instalar, separe o que o dnf realmente resolve e reporte o resto como aviso,
# em vez de perder todos os outros pacotes da lista. Uma única chamada de
# repoquery para a lista toda: um por pacote deixaria a fase lenta demais.
if [ "${#PKGS_FALTANDO[@]}" -gt 0 ]; then
  mapfile -t _resolvidos < <(
    # o \n é obrigatório: sem ele o repoquery concatena os nomes sem separador
    # ("adw-gtk3-themeresources") e o grep -qx nunca casa.
    dnf -q repoquery --available --qf '%{name}\n' "${PKGS_FALTANDO[@]}" 2>/dev/null |
      sort -u
  )
  _ausentes=()
  _instalaveis=()
  for p in "${PKGS_FALTANDO[@]}"; do
    if printf '%s\n' "${_resolvidos[@]:-}" | grep -qx "$p"; then
      _instalaveis+=("$p")
    else
      _ausentes+=("$p")
    fi
  done
  if [ "${#_ausentes[@]}" -gt 0 ]; then
    warn "packages.txt pede ${#_ausentes[@]} pacote(s) inexistente(s): ${_ausentes[*]}"
    warn "ignorados nesta rodada — corrija o nome em lists/packages.txt"
  fi
  if [ "${#_instalaveis[@]}" -gt 0 ]; then
    PKGS_FALTANDO=("${_instalaveis[@]}")
  else
    PKGS_FALTANDO=()
  fi
fi

if [ "${#PKGS_FALTANDO[@]}" -eq 0 ]; then
  ok "pacotes já instalados — pulando"
else
  dnf install -y "${PKGS_FALTANDO[@]}"
  ok "${#PKGS_FALTANDO[@]} pacote(s) instalados"
fi

# --- virtualização (virt-manager) ------------------------------------ #
# O gnome-boxes foi removido como bloatware, então o stack de virtualização
# (libvirt + qemu-kvm) precisa vir por conta própria. KVM exige /dev/kvm e
# CPU com virtualização (a 5500U tem AMD-V).
if ! rpm_installed virt-manager; then
  try_warn dnf install -y virt-manager libvirt-daemon-driver-qemu \
    libvirt-client-qemu qemu-kvm virt-install
  ok "virt-manager + libvirt + qemu-kvm instalados"
else
  ok "virt-manager já instalado — pulando"
fi
# lazydocker: TUI para docker (COPR atim/lazydocker, habilitado na fase 1)
if ! rpm_installed lazydocker; then
  try_warn dnf install -y lazydocker
else
  ok "lazydocker já instalado — pulando"
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
step "Fase 4/13 — codecs e aceleração de vídeo"
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
# svt-av1-libs: decodificação de AV1 por software (o hardware do 5500U não tem
# decoder AV1). É o que o Sunshine precisa para enviar vídeo AV1. No Fedora o
# pacote se chama svt-av1-libs — "libsvtav1" é o nome do RPM Fusion.
if ! rpm_installed svt-av1-libs; then
  try_warn dnf install -y svt-av1-libs
else
  ok "svt-av1-libs (AV1) já instalado — pulando"
fi
phase_end "$_f0" "codecs/VA-API prontos"

# --------------------------------------------------------------- #
# 5. SERVIÇOS                                                      #
# --------------------------------------------------------------- #
step "Fase 5/13 — serviços systemd"
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

# --- dnsmasq como resolvedor local (via NetworkManager) --------------- #
# O systemd-resolved e o dnsmasq disputam o /etc/resolv.conf: enquanto o
# resolved roda, ele reescreve o resolv.conf com os upstreams do link e o
# dnsmasq (que fica escutando em 127.0.0.1:53) nunca é consultado. A sequência
# que funciona de fato é:
#   1. plugin do NM (dns=dnsmasq) — o NM passa a gerenciar o DNS e escreve
#      127.0.0.1 em /run/NetworkManager/resolv.conf
#   2. derrubar e mascarar o resolved, senão ele sobrescreve o resolv.conf
#   3. apontar /etc/resolv.conf para o arquivo do NM
if rpm_installed dnsmasq; then
  if [ ! -f /etc/NetworkManager/conf.d/00-use-dnsmasq.conf ]; then
    install -d -m 755 /etc/NetworkManager/conf.d
    cat > /etc/NetworkManager/conf.d/00-use-dnsmasq.conf <<'EOF'
[main]
dns=dnsmasq
EOF
    ok "NetworkManager configurado para usar o dnsmasq"
  else
    ok "NetworkManager já usa o dnsmasq — pulando"
  fi
  # configuração do dnsmasq: cache maior e upstream próprio (não lê o
  # /etc/resolv.conf, que aponta para ele mesmo)
  if [ ! -f /etc/NetworkManager/dnsmasq.d/00-fedorapi.conf ]; then
    install -d -m 755 /etc/NetworkManager/dnsmasq.d
    cat > /etc/NetworkManager/dnsmasq.d/00-fedorapi.conf <<'EOF'
# Upstream próprio: o /etc/resolv.conf aponta para o dnsmasq, então não pode
# ser lido por ele (loop).
no-resolv
server=1.1.1.1
server=9.9.9.9
server=8.8.8.8
cache-size=1500
EOF
    ok "dnsmasq: cache 1500 e upstream Cloudflare/Quad9/Google"
  else
    ok "dnsmasq já configurado — pulando"
  fi
  try_warn systemctl enable --now dnsmasq
  # o NM só reescreve /run/NetworkManager/resolv.conf depois de reiniciar
  try_warn systemctl restart NetworkManager
  # o resolved precisa sair: com ele ativo, o /etc/resolv.conf volta a apontar
  # para os upstreams do link e o dnsmasq fica órfão escutando em :53
  if systemctl is-active --quiet systemd-resolved; then
    try_warn systemctl disable --now systemd-resolved
    try_warn systemctl mask systemd-resolved
    ok "systemd-resolved desligado e mascarado (disputava a porta 53 com o dnsmasq)"
  else
    ok "systemd-resolved já está fora do caminho — pulando"
  fi
  if [ "$(readlink -f /etc/resolv.conf)" != "/run/NetworkManager/resolv.conf" ]; then
    try_warn ln -sf /run/NetworkManager/resolv.conf /etc/resolv.conf
    ok "/etc/resolv.conf apontado para o arquivo do NetworkManager"
  else
    ok "/etc/resolv.conf já aponta para o NetworkManager — pulando"
  fi
  if grep -qx 'nameserver 127.0.0.1' /run/NetworkManager/resolv.conf 2>/dev/null; then
    ok "dnsmasq é o resolvedor do sistema (resolv.conf -> 127.0.0.1)"
  else
    warn "resolv.conf do NM não aponta para 127.0.0.1 — revise o plugin do NetworkManager"
  fi
else
  warn "dnsmasq não instalado — resolvedor local não configurado"
fi
phase_end "$_f0" "serviços habilitados"

# --------------------------------------------------------------- #
# 6. FLATPAKS                                                       #
# --------------------------------------------------------------- #
step "Fase 6/13 — Flathub + flatpaks"
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

# adw-gtk3 como tema GTK padrao. Duas vias complementares, ambas oficiais do
# upstream (lassekongo83/adw-gtk3):
#   1) flatpak: as extensoes Gtk3theme do Flathub sao lidas pelo
#      xdg-desktop-portal-gtk do host, que ja pega o nome em
#      org.gnome.desktop.interface gtk-theme. Nao usamos
#      'flatpak override --filesystem=xdg-data/themes' porque o upstream diz
#      para escolher UMA das duas vias, e a do Flathub e a que cobre os apps
#      GTK3 sem precisar mascarar as extensoes.
#   2) nativo: o rpm adw-gtk3 (instalado na fase 3) põe /usr/share/themes/
#      adw-gtk3{,-dark} no disco — é de lá que o accent-sync copia para
#      ~/.local/share/themes, caminho que os flatpaks enxergam.
for t in adw-gtk3 adw-gtk3-dark; do
  if flatpak_installed "org.gtk.Gtk3theme.$t"; then
    ok "tema flatpak $t já instalado — pulando"
  else
    try_warn flatpak install -y --system --noninteractive "flathub/org.gtk.Gtk3theme.$t"
  fi
done
# O nome do tema segue o color-scheme: quem troca light/dark no painel do GNOME
# continua coerente. O accent-sync cuida so do accent (e da copia dos temas),
# entao esta e a unica vez que o gtk-theme precisa ser escrito.
if as_user gsettings get org.gnome.desktop.interface color-scheme | grep -q prefer-dark; then
  as_user gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
else
  as_user gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3'
fi
# Faz o accent-sync copiar agora os temas pro ~/.local/share/themes (ele so
# recopia quando a assinatura do rpm muda; numa install nova nunca rodou).
if [ -x "$SUH/.local/bin/accent-sync" ]; then
  try_warn as_user "$SUH/.local/bin/accent-sync"
fi
phase_end "$_f0" "flatpaks instalados (${#FPKS[@]} refs)"

# --------------------------------------------------------------- #
# 7. DOTFILES    (clone do repo dotfiles — fonte única)           #
# --------------------------------------------------------------- #
step "Fase 7/13 — dotfiles (clone EmanuProds/dotfiles)"
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
# Overrides de .desktop (ex.: "Monitor do sistema" no lugar do "Resources" do
# pacote). O Dotfiles é a fonte única; o script só copia e ajusta o dono.
if [ -d "$CLONES/dotfiles/home/.local/share/applications" ]; then
  install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" \
    "$SUH/.local/share/applications"
  cp -a "$CLONES/dotfiles/home/.local/share/applications/." \
    "$SUH/.local/share/applications/"
  chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.local/share/applications"
  try_warn update-desktop-database "$SUH/.local/share/applications"
fi
chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" \
  "$SUH/.config" "$SUH/.bashrc" "$SUH/.shell_aliases" 2>/dev/null || true
# Ativação do mise/starship no .bashrc. O dotfiles já traz o .bashrc correto
# (ativação do mise antes do return interativo) e a fase 7 copia esse arquivo
# acima; aqui só garantimos o starship, caso o dotfiles venha sem ele.
if ! grep -q 'starship init bash' "$SUH/.bashrc" 2>/dev/null; then
  printf '\ncommand -v starship >/dev/null 2>&1 && eval "$(starship init bash)"\n' >> "$SUH/.bashrc"
  chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.bashrc"
fi

# BASH_ENV: bash -c SÓ lê o .bashrc se BASH_ENV apontar para ele. Sem isso, um LLM
# que rode `npm ...` num shell não-interativo recebe "command not found".
# /etc/environment é lido pelo PAM em todo login (não só no terminal).
if ! grep -q '^BASH_ENV=' /etc/environment 2>/dev/null; then
  printf 'BASH_ENV=%s/.bashrc\n' "$SUH" >> /etc/environment
  ok "BASH_ENV apontando para o .bashrc (shell não-interativo enxerga o mise)"
fi
# Symlinks em /usr/local/bin: última rede para processos que ignoram o BASH_ENV
# (cron, units systemd, IDEs). O shim é um executável real, então funciona igual.
if [ -d "$SUH/.local/share/mise/shims" ]; then
  for shim in npm node bun bunx gh go pipx omniroute; do
    [ -e "$SUH/.local/share/mise/shims/$shim" ] || continue
    ln -sfn "$SUH/.local/share/mise/shims/$shim" "/usr/local/bin/$shim"
  done
  ok "shims do mise expostos em /usr/local/bin"
fi

# ssh-agent: o Fedora já traz /usr/lib/systemd/user/ssh-agent.socket (com
# SocketMode=0600 e DirectoryMode=0700). Basta habilitar — NÃO criamos uma unit
# própria em ~/.config/systemd/user, que sobreporia a do vendor e perderia essas
# permissões. enable sem --now: o socket sobe no próximo login.
if [ -f /usr/lib/systemd/user/ssh-agent.socket ]; then
  try_warn as_user systemctl --user enable ssh-agent.socket
  ok "ssh-agent: socket do systemd habilitado (inicia no próximo login)"
else
  warn "ssh-agent.socket não encontrado no /usr/lib/systemd/user — agente não habilitado"
fi
# O SSH_AUTH_SOCK precisa existir no shell não-interativo (script/LLM/cron).
# O systemd do usuário exporta %t/ssh-agent.socket na sessão; para o resto,
# garantimos o link em /run/user/<uid>/ssh-agent.socket -> que é o %t.
if [ -S "/run/user/$UID_R/ssh-agent.socket" ]; then
  ok "ssh-agent: socket presente em %t"
fi
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
step "Fase 8/13 - restaurando GNOME (dconf dump do repo dotfiles)"
try_warn as_user dconf load / < "$CLONES/dotfiles/dconf/gnome-settings.ini"

# App Folders do GNOME: agrupa apps no overview (estilo Arch/CachyOS).
# Configuração por usuário via gsettings (idempotente: reescreve a lista completa).
# TODAS as pastas usam LISTA EXPLICITA de apps (categories=@as [] + excluded-apps=@as []),
# nao casamento por categoria — robusto a mudanças de .desktop dos apps.
AF="org.gnome.desktop.app-folders"
ASF="org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders"
try_warn as_user gsettings set "$AF" folder-children   "['Multimidia', 'Ferramentas', 'Utilitarios', 'Escritorio', 'Jogos', 'Wine', 'Sistema']"

# Listas de apps por pasta (copiadas do estado real da máquina, já sem duplicatas).
# O gsettings aceita arrays JSON: apps=['app1.desktop', 'app2.desktop', ...]
readonly MULTIMIDIA_APPS="['io.github.seadve.Kooha.desktop', 'gimp.desktop', 'org.inkscape.Inkscape.desktop', 'org.pitivi.Pitivi.desktop', 'org.kde.drawy.desktop', 'io.gitlab.theevilskeleton.Upscaler.desktop', 'org.nickvision.tubeconverter.desktop']"
readonly FERRAMENTAS_APPS="['virt-manager.desktop', 'io.gitlab.adhami3310.Impression.desktop', 'org.gnome.baobab.desktop', 'it.mijorus.gearlever.desktop', 'io.github.flattool.Warehouse.desktop', 'com.mattjakeman.ExtensionManager.desktop', 'page.codeberg.libre_menu_editor.LibreMenuEditor.desktop', 'org.fedoraproject.MediaWriter.desktop']"
readonly UTILITARIOS_APPS="['org.gnome.Calendar.desktop', 'org.gnome.Weather.desktop', 'org.gnome.clocks.desktop', 'org.gnome.Decibels.desktop', 'org.gnome.Showtime.desktop', 'org.gnome.Snapshot.desktop', 'org.gnome.Loupe.desktop', 'org.gnome.Papers.desktop', 'org.gnome.FileRoller.desktop', 'org.gnome.Characters.desktop', 'org.gnome.font-viewer.desktop', 'org.gnome.Maps.desktop']"
readonly ESCRITORIO_APPS="['io.github.diegoivan.pdf_metadata_editor.desktop', 'org.gnome.SimpleScan.desktop', 'com.calibre_ebook.calibre.desktop', 'com.calibre_ebook.calibre.lrfviewer.desktop', 'com.calibre_ebook.calibre.ebook-edit.desktop', 'com.calibre_ebook.calibre.ebook-viewer.desktop']"
readonly JOGOS_APPS="['steam.desktop', 'epic_games_launcher.desktop', 'net.retrodeck.retrodeck.Configurator.desktop', 'com.heroicgameslauncher.hgl.desktop', 'io.github.radiolamp.mangojuice.desktop']"
readonly WINE_APPS="['com.vysp3r.ProtonPlus.desktop', 'com.github.Matoking.protontricks.desktop', 'winetricks.desktop', 'wine-winecfg.desktop', 'wine-winefile.desktop', 'wine-uninstaller.desktop', 'wine-regedit.desktop']"
readonly SISTEMA_APPS="['org.gnome.tweaks.desktop', 'io.github.flattool.Ignition.desktop', 'net.nokyan.Resources.Devel.desktop', 'org.gnome.DiskUtility.desktop', 'com.github.tchx84.Flatseal.desktop', 'io.github.realmazharhussain.GdmSettings.desktop', 'btrfs-assistant.desktop', 'org.cachyos.scx-manager.desktop', 'org.gnome.Logs.desktop']"

# Multimídia (era 'Editores') — apps de criação de mídia
try_warn as_user gsettings set "$ASF/Multimidia/" name 'Multimídia'
try_warn as_user gsettings set "$ASF/Multimidia/" translate false
try_warn as_user gsettings set "$ASF/Multimidia/" categories "@as []"
try_warn as_user gsettings set "$ASF/Multimidia/" apps "$MULTIMIDIA_APPS"
try_warn as_user gsettings set "$ASF/Multimidia/" excluded-apps "@as []"

# Ferramentas — apps de sistema/ferramentas avançadas
try_warn as_user gsettings set "$ASF/Ferramentas/" name 'Ferramentas'
try_warn as_user gsettings set "$ASF/Ferramentas/" translate false
try_warn as_user gsettings set "$ASF/Ferramentas/" categories "@as []"
try_warn as_user gsettings set "$ASF/Ferramentas/" apps "$FERRAMENTAS_APPS"
try_warn as_user gsettings set "$ASF/Ferramentas/" excluded-apps "@as []"

# Utilitários — apps básicos do GNOME (sem duplicatas das outras pastas)
try_warn as_user gsettings set "$ASF/Utilitarios/" name 'Utilities.directory'
try_warn as_user gsettings set "$ASF/Utilitarios/" translate true
try_warn as_user gsettings set "$ASF/Utilitarios/" categories "@as []"
try_warn as_user gsettings set "$ASF/Utilitarios/" apps "$UTILITARIOS_APPS"
try_warn as_user gsettings set "$ASF/Utilitarios/" excluded-apps "@as []"

# Escritório (era 'Escritorio' com 'Office.directory')
try_warn as_user gsettings set "$ASF/Escritorio/" name 'Office.directory'
try_warn as_user gsettings set "$ASF/Escritorio/" translate true
try_warn as_user gsettings set "$ASF/Escritorio/" categories "@as []"
try_warn as_user gsettings set "$ASF/Escritorio/" apps "$ESCRITORIO_APPS"
try_warn as_user gsettings set "$ASF/Escritorio/" excluded-apps "@as []"

# Jogos
try_warn as_user gsettings set "$ASF/Jogos/" name 'Game.directory'
try_warn as_user gsettings set "$ASF/Jogos/" translate true
try_warn as_user gsettings set "$ASF/Jogos/" categories "@as []"
try_warn as_user gsettings set "$ASF/Jogos/" apps "$JOGOS_APPS"
try_warn as_user gsettings set "$ASF/Jogos/" excluded-apps "@as []"

# Wine
try_warn as_user gsettings set "$ASF/Wine/" name 'Wine.directory'
try_warn as_user gsettings set "$ASF/Wine/" translate true
try_warn as_user gsettings set "$ASF/Wine/" categories "@as []"
try_warn as_user gsettings set "$ASF/Wine/" apps "$WINE_APPS"
try_warn as_user gsettings set "$ASF/Wine/" excluded-apps "@as []"

# Sistema (lista explícita — a categoria antiga não existia e deixava a pasta vazia)
try_warn as_user gsettings set "$ASF/Sistema/" name 'Sistema'
try_warn as_user gsettings set "$ASF/Sistema/" translate false
try_warn as_user gsettings set "$ASF/Sistema/" categories "@as []"
try_warn as_user gsettings set "$ASF/Sistema/" apps "$SISTEMA_APPS"
try_warn as_user gsettings set "$ASF/Sistema/" excluded-apps "@as []"

# Limpa qualquer pasta-UUID órfã que o GNOME tenha criado manualmente
for _uuid in $(as_user gsettings get "$AF" folder-children 2>/dev/null |
  grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' || true); do
  as_user gsettings reset-recursively "$ASF/$_uuid/" 2>/dev/null || true
done

# prova de vida: cada pasta tem que ter apps, senão o GNOME esconde
for _pasta in Multimidia Ferramentas Utilitarios Escritorio Jogos Wine Sistema; do
  if [ "$(as_user gsettings get "$ASF/$_pasta/" apps 2>/dev/null | grep -o '\.desktop' | wc -l)" -gt 0 ]; then
    ok "pasta '$_pasta' com apps"
  else
    warn "pasta '$_pasta' ficou sem apps — o GNOME vai escondê-la"
  fi
done
ok "dconf restaurado (pastas explícitas: Multimídia, Ferramentas, Utilitários, Escritório, Jogos, Wine, Sistema)"

# --------------------------------------------------------------- #
# 9. EXTENSÕES DO GNOME  (D-Bus: InstallRemoteExtension)          #
# --------------------------------------------------------------- #
mapfile -t EXT_UUIDS < <(read_list "$LISTS/extensions.txt")
step "Fase 9/13 — extensões GNOME (${#EXT_UUIDS[@]} UUIDs)"
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
step "Fase 10/13 — mise (node/bun/go/usage/pipx/gh) + LSPs npm"
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
step "Fase 11/13 — opencode (do dotfiles) + accent-sync/titlebar (repos próprios)"

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

# Adwaita Colors: gera variantes do tema de ícones (Adwaita-blue, -teal, ...)
# que seguem a cor de destaque do GNOME; trabalha em conjunto com o MoreWaita.
# Requer o MoreWaita instalado (pacote morewaita-icon-theme, Fase 3).
# idempotência: só reinstala se alguma variante estiver faltando OU se o
# MoreWaita ainda não estiver na cadeia Inherits (integração não aplicada).
needs_ac=0
if [ ! -d "$SUH/.local/share/icons/Adwaita-blue" ] && [ ! -d "/usr/share/icons/Adwaita-blue" ]; then
  needs_ac=1
elif ! grep -q 'MoreWaita' "$SUH/.local/share/icons/Adwaita-teal/index.theme" 2>/dev/null; then
  needs_ac=1
fi
if [ "$needs_ac" -eq 1 ]; then
  clone_repo "https://github.com/dpejoh/Adwaita-colors" "$CLONES/adwaita-colors"
  # instala (user dir por padrão; com -g seria system-wide)
  if [ -x "$CLONES/adwaita-colors/setup" ]; then
    try_warn "$CLONES/adwaita-colors/setup" -i -f
    # integra o MoreWaita (gera as pastas coloridas para os ícones extras)
    [ -x "$CLONES/adwaita-colors/morewaita.sh" ] && try_warn bash "$CLONES/adwaita-colors/morewaita.sh"
    # atualiza o cache de ícones para o GNOME/Tweaks enxergarem as variantes
    try_warn gtk-update-icon-cache -f "$SUH/.local/share/icons/Adwaita-teal"
    ok "adwaita-colors instalado (variantes por cor de destaque)"
  fi
else
  ok "adwaita-colors já instalado e integrado — pulando"
fi
install -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" \
  "$CLONES/accent-sync/accent-sync" "$SUH/.local/bin/accent-sync"
install -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" \
  "$CLONES/titlebar/opencode-desktop-titlebar-patch" "$SUH/.local/bin/opencode-desktop-titlebar-patch"
# wrapper para o patch achar o node do mise (validação de sintaxe pós-patch)
install -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" /dev/stdin "$SUH/.local/bin/opencode-desktop-titlebar-patch-wrapper" <<'EOF'
#!/usr/bin/env bash
export PATH="/home/emanuel/.local/share/mise/installs/node/lts/bin:$PATH"
exec /home/emanuel/.local/bin/opencode-desktop-titlebar-patch "$@"
EOF
# units do accent-sync (user) + titlebar (sistema, pois /opt/OpenCode é root)
install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$SUH/.config/systemd/user"
install -m 644 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$CLONES/accent-sync/units/"* "$SUH/.config/systemd/user/"
as_user systemctl --user daemon-reload || true
try_warn as_user systemctl --user enable --now accent-sync.path

# titlebar patch: systemd system (PathChanged=/opt/OpenCode/resources/app.asar)
# Wrappados em try_warn: sudo pede senha; se falhar (ex.: cancelado/non-interativo),
# o script não deve abortar — o serviço será criado no próximo run.
try_warn sudo tee /etc/systemd/system/opencode-titlebar-patch.service <<'EOF'
[Unit]
Description=Reaplica o patch de title bar do OpenCode Desktop
After=network-online.target

[Service]
Type=oneshot
ExecStart=%h/.local/bin/opencode-desktop-titlebar-patch-wrapper
RemainAfterExit=no
EOF
try_warn sudo tee /etc/systemd/system/opencode-titlebar-patch.path <<'EOF'
[Unit]
Description=Dispara o patch quando o app.asar do OpenCode Desktop muda

[Path]
PathChanged=/opt/OpenCode/resources/app.asar
Unit=opencode-titlebar-patch.service

[Install]
WantedBy=multi-user.target
EOF
try_warn sudo systemctl daemon-reload
try_warn sudo systemctl enable --now opencode-titlebar-patch.path
# prova de vida: patch já aplicado?
if sudo "$SUH/.local/bin/opencode-desktop-titlebar-patch-wrapper" --check >/dev/null 2>&1; then
  ok "titlebar patch aplicado e serviço de monitoramento ativo"
else
  warn "titlebar patch não aplicado — rodará no próximo upgrade do opencode"
fi

# OpenCode Desktop (app oficial em .rpm, pelo processo do site opencode.ai/download)
if ! rpm -q opencode-desktop >/dev/null 2>&1; then
  desk_url=$(curl -fsSL "https://api.github.com/repos/anomalyco/opencode/releases/latest" \
    | grep -oE '"browser_download_url": *"[^"]+"' | cut -d'"' -f4 \
    | grep -E 'opencode-desktop-linux-x86_64\.rpm$' | head -1 || true)
  [ -n "$desk_url" ] && try_warn dnf install -y "$desk_url" \
    || warn "opencode-desktop: asset .rpm x86_64 não achado no release"
else
  ok "opencode-desktop já instalado — pulando"
fi

# omniroute: gateway de IA. Instala global via npm (mise) e cria unit de usuário
# que só inicia no próximo login (enable sem --now, por pedido explícito).
if ! npm_global_installed omniroute; then
  # O npm global do mise fica no prefixo dele; o shim (que cria o comando no PATH)
  # só é regenerado por 'mise reshim' — e o wrapper do npm chama 'mise' por nome,
  # então o mise precisa estar no PATH para o reshim rodar.
  try_warn as_user bash -c 'export PATH="$HOME/.local/bin:$PATH"; \
    "$HOME/.local/bin/mise" exec -- npm i -g \
      --allow-scripts=omniroute,keytar,onnxruntime-node,@parcel/watcher,@swc/core,protobufjs,esbuild \
      omniroute && "$HOME/.local/bin/mise" reshim'
else
  ok "omniroute já instalado globalmente — pulando"
fi
if [ ! -f "$SUH/.config/systemd/user/omniroute.service" ]; then
  cat > "$SUH/.config/systemd/user/omniroute.service" <<'EOF'
[Unit]
Description=OmniRoute (gateway de IA local)
After=network-online.target

[Service]
Type=simple
ExecStart=%h/.local/share/mise/shims/omniroute
Environment=PORT=20128
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
  chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.config/systemd/user/omniroute.service"
  as_user systemctl --user daemon-reload || true
  # enable SEM --now: fica para o próximo login, não sobe agora
  try_warn as_user systemctl --user enable omniroute.service
  ok "omniroute: unit criada e habilitada (inicia no próximo login)"
fi

# Sunshine: autostart em background, launcher escondido e config criada.
# O pacote do upstream chama-se "Sunshine" (S maiúsculo) — por isso o teste
# do rpm não pode ser por "sunshine".
if ! rpm_installed Sunshine; then
  warn "Sunshine ainda não instalado (fase 13 instala o .rpm)"
else
  install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$SUH/.config/autostart"
  cat > "$SUH/.config/autostart/sunshine.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Sunshine
Exec=/usr/bin/sunshine
Icon=video-display
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
  chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.config/autostart/sunshine.desktop"
  # esconde o launcher do menu (mantém o serviço/CLI intactos)
  if [ -f /usr/share/applications/dev.lizardbyte.app.Sunshine.desktop ]; then
    sed -i '/^NoDisplay=/d' /usr/share/applications/dev.lizardbyte.app.Sunshine.desktop 2>/dev/null || true
    printf 'NoDisplay=true\n' >> /usr/share/applications/dev.lizardbyte.app.Sunshine.desktop
  fi
  # configuração: o Sunshine sem config não sobe (falta credencial/porta).
  # A senha e o usuário ficam com placeholders — troque antes de usar.
  if [ ! -f /etc/sunshine/sunshine.conf ]; then
    install -d -m 755 /etc/sunshine
    cat > /etc/sunshine/sunshine.conf <<'EOF'
# Sunshine — game streaming (gerado pelo fedoraPI.sh)
# TROQUE a senha e o usuário abaixo antes de usar.
port = 47989
address = 0.0.0.0
sunshine_username = eumanu
sunshine_password = TROQUE_ESTA_SENHA
upnp = disabled
pkey = /etc/sunshine/sunshine.pem
log_path = /var/log/sunshine.log
EOF
    chmod 600 /etc/sunshine/sunshine.conf
    ok "sunshine: /etc/sunshine/sunshine.conf criado (ajuste a senha!)"
  else
    ok "sunshine: config já existe — pulando"
  fi
  ok "sunshine: autostart criado, launcher oculto e config pronta"
fi

# Ghostty como terminal padrão + esconde o gnome-terminal do menu.
if command_exists ghostty; then
  if command -v update-desktop-database >/dev/null 2>&1; then
    try_warn as_user update-desktop-database "$SUH/.local/share/applications"
  fi
  # Dois erros reais nesta parte, ambos medidos:
  #  1. o .desktop do ghostty vem do rpm em /usr/share/applications — o caminho
  #     em ~/.local/share que estava aqui não existe, e update-alternatives
  #     falha em silêncio quando o alvo não existe;
  #  2. o nome do grupo precisa ser o canônico do Fedora (x-terminal-emulator).
  #     Um nome solto tipo "x-gnome-terminal-provider.default" dá exit=2 e nada
  #     é registrado.
  GHOSTTY_DESKTOP=/usr/share/applications/com.mitchellh.ghostty.desktop
  if [ -f "$GHOSTTY_DESKTOP" ]; then
    if rpm_installed alternatives; then
      # O update-alternatives do Fedora exige que o link PRIMÁRIO do grupo
      # x-terminal-emulator seja /usr/bin/zzz-c (o prefixo "zzz" ordena a
      # preferência). Passar /etc/alternatives/... sai com 2 e a mensagem
      # "the primary link for x-terminal-emulator must be /usr/bin/zzz-c".
      #
      # Este comando estava SEM try_warn e COM 2>&1: quando falhava, o set -e
      # encerrava o script sem imprimir nada. Foi o que matou a execução no
      # meio da fase 11, duas vezes, sem deixar rastro no log.
      if try_warn update-alternatives --install /usr/bin/zzz-c x-terminal-emulator \
        "$GHOSTTY_DESKTOP" 40; then
        ok "x-terminal-emulator -> ghostty"
      else
        warn "update-alternatives não registrou o ghostty como emulador de terminal"
      fi
    else
      warn "pacote 'alternatives' ausente — terminal padrão não registrado"
    fi
    # org.gnome.desktop.terminal NÃO é usado aqui: esse schema vem do
    # gnome-terminal, que não está instalado nesta máquina, então o gsettings
    # falharia com "Nenhum esquema".
  else
    warn "ghostty instalado mas $GHOSTTY_DESKTOP não existe"
  fi
  # esconde o terminal antigo, se existir
  if [ -f /usr/share/applications/org.gnome.Terminal.desktop ]; then
    sed -i '/^NoDisplay=/d' /usr/share/applications/org.gnome.Terminal.desktop 2>/dev/null || true
    printf 'NoDisplay=true\n' >> /usr/share/applications/org.gnome.Terminal.desktop
  fi
  ok "ghostty: terminal padrão + gnome-terminal oculto"
else
  warn "ghostty não está no PATH — terminal padrão não configurado"
fi

# resources (COPR atim/resources, beta): oculta os launchers que o substituem.
# O override "Monitor do sistema" (mesmo appID do pacote) vem do Dotfiles, copiado
# na fase 7 — aqui só escondemos os originais do sistema, senão os dois
# aparecem no menu. O NoDisplay em /usr/share é perdido a cada dnf update, então
# reaplicamos a cada run.
if rpm_installed resources; then
  for orig in /usr/share/applications/net.nokyan.Resources.Devel.desktop \
              /usr/share/applications/org.gnome.SystemMonitor.desktop; do
    [ -f "$orig" ] || continue
    sed -i '/^NoDisplay=/d' "$orig" 2>/dev/null || true
    printf 'NoDisplay=true\n' >> "$orig"
  done
  ok "resources: launchers originais ocultos (override vem do dotfiles)"
else
  warn "resources não instalado (COPR atim/resources) — Monitor do sistema não configurado"
fi

ok "opencode + helpers + units ok (memory.db nasce do zero; migre ~/.opencode/memory.db* do Arch se quiser histórico)"

# --------------------------------------------------------------- #
# 12. TUNING DE KERNEL E SISTEMA (performance + secure boot)       #
# --------------------------------------------------------------- #
step "Fase 12/13 — tuning de kernel e sistema"
_f0=$FAIL_COUNT

# --- split-lock: desativa a mitigação do bug de split-lock --------- #
# O Ryzen 5 5500U é afetado pelo bug: a mitigação (split_lock_detect)
# desativa o mitigation bus lock, o que custa ~5-10% em jogos com
# muitos threads. O CachyOS usa o param de kernel 'split_lock_detect=off'.
if grubby --info=ALL 2>/dev/null | grep -q 'split_lock_detect=off'; then
  ok "split_lock_detect=off já no cmdline — pulando"
else
  try_warn grubby --update-kernel=ALL --args="split_lock_detect=off"
  ok "split_lock_detect=off aplicado (reboot necessário)"
fi

# --- BBR3 + MTU probing + min_free_kbytes ---------------------------- #
# BBR3: o kernel CachyOS traz o módulo tcp_bbr3 (nome do algoritmo 'bbr3',
# não 'bbr'). Exige qdisc=fq. MTU probing: PMTU black hole em redes PPP/
# VPN. min_free_kbytes: 1% da RAM total, recalculado a cada boot (assim
# acompanha upgrade/downgrade de RAM) — a mesma ideia do free_mem_fix do
# LinuxToys.
install -d -m 755 /etc/sysctl.d
cat > /etc/sysctl.d/90-fedorapi-tuning.conf <<'EOF'
# --- BBR3 (kernel CachyOS) ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr3
# --- MTU probing (recupera de PMTU black hole em VPN/PPP) ---
net.ipv4.tcp_mtu_probing = 1
EOF
# carrega o módulo e o algoritmo agora (vale já para a sessão atual)
modprobe tcp_bbr3 2>/dev/null || true
try_warn sysctl --system
if [ "$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)" = "bbr3" ]; then
  ok "BBR3 ativo + MTU probing ligado"
else
  warn "BBR3 não ficou como congestion control (o módulo carregou? $(ls /lib/modules/$(uname -r)/kernel/net/ipv4/tcp_bbr3.ko.zst 2>/dev/null | wc -l) arquivo(s) encontrado(s))"
fi

# vm.min_free_kbytes = 1% da RAM, recalculado a cada boot.
# O cálculo fica num script próprio: embutir o awk no ExecStart exige escaping
# de aspas dentro do unit, e o systemd executa o ExecStart via shell — as
# aspas escapadas viram literais e o awk falha.
cat > /tmp/set-min-free-mem.sh <<'EOF'
#!/bin/sh
# Define vm.min_free_kbytes como 1% da RAM total.
# 1% acompanha upgrades/downgrades de RAM sem precisar recalcular na mão.
set -e
kbytes=$(awk '/MemTotal/ {printf "%.0f", $2 * 0.01}' /proc/meminfo)
sysctl -w "vm.min_free_kbytes=$kbytes"
EOF
try_warn install -m 755 /tmp/set-min-free-mem.sh /usr/local/bin/set-min-free-mem.sh
rm -f /tmp/set-min-free-mem.sh
if [ ! -f /etc/systemd/system/set-min-free-mem.service ]; then
  cat > /etc/systemd/system/set-min-free-mem.service <<'EOF'
[Unit]
Description=Define vm.min_free_kbytes como 1% da RAM total
DefaultDependencies=no
After=local-fs.target
Before=sysinit.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/set-min-free-mem.sh

[Install]
WantedBy=sysinit.target
EOF
  try_warn systemctl daemon-reload
  try_warn systemctl enable set-min-free-mem.service
fi
try_warn systemctl restart set-min-free-mem.service
# O awk fica em aspas SIMPLES e as aspas internas sem escape: dentro de "$( )"
# o \" vira barra invertida LITERAL e o awk morre com "barra invertida não é o
# último caractere da linha". O valor já era setado certo pelo script acima —
# era só a mensagem que saía vazia e derrubava o set -e.
_min_free_kb=$(awk '/MemTotal/ {printf "%.0f", $2 * 0.01}' /proc/meminfo)
if [ "${_min_free_kb:-0}" -gt 0 ] 2>/dev/null; then
  ok "min_free_kbytes = 1% da RAM (${_min_free_kb} kB)"
else
  warn "não foi possível ler a RAM de /proc/meminfo — min_free_kbytes pode estar errado"
fi

# --- cache de shader (AMD/RADV) -------------------------------------- #
# A GPU é a iGPU Radeon do 5500U, então vale o par AMD do shader-booster:
# MESA_SHADER_CACHE_MAX_SIZE limita o tamanho do cache (12G) e AMD_VULKAN_ICD
# força o RADV. Sem isso, shaders são recompilados a cada boot.
if grep -q 'MESA_SHADER_CACHE_MAX_SIZE' /etc/environment 2>/dev/null; then
  ok "cache de shader já configurado — pulando"
else
  if ! grep -q '^AMD_VULKAN_ICD=' /etc/environment 2>/dev/null; then
    printf 'AMD_VULKAN_ICD=RADV\n' >> /etc/environment
  fi
  if ! grep -q '^MESA_SHADER_CACHE_MAX_SIZE=' /etc/environment 2>/dev/null; then
    printf 'MESA_SHADER_CACHE_MAX_SIZE=12G\n' >> /etc/environment
  fi
  ok "cache de shader AMD ampliado para 12G (reboot necessário)"
fi

# --- ananicy-cpp: regras do CachyOS ---------------------------------- #
if rpm_installed ananicy-cpp; then
  if [ -d /etc/ananicy.d/00-default ]; then
    ok "ananicy-cpp com regras do CachyOS ativas"
  else
    warn "ananicy-cpp instalado mas sem regras em /etc/ananicy.d/00-default"
  fi
else
  warn "ananicy-cpp não instalado"
fi

# --- WiFi Realtek: confere o driver em uso ----------------------------- #
# A placa é a RTL8822CE (PCI 10ec:c822) — NÃO é a 8821CE. O 8822CE tem
# suporte nativo no kernel (rtw88_8822ce, desde o 5.2), então não é preciso
# nenhum driver externo. Se o módulo não estiver carregado, carrega.
if lspci 2>/dev/null | grep -qiE '10ec:c8(22|2f)'; then
  if ! lsmod | grep -q '^rtw88_8822ce'; then
    try_warn modprobe rtw88_8822ce
  fi
  if lsmod | grep -q '^rtw88_8822ce'; then
    ok "WiFi Realtek 8822CE: driver nativo rtw88_8822ce carregado (sem DKMS)"
  else
    warn "WiFi 8822CE detectado mas o rtw88_8822ce não carregou — verifique o firmware"
  fi
fi

# --- snapper: limites de snapshot ------------------------------------- #
# O pacote python3-dnf-plugin-snapper NÃO serve aqui: ele se registra em
# /etc/dnf/plugins, que é o diretório de plugins do libdnf (dnf4), e no
# Fedora 44 o /usr/bin/dnf é symlink para dnf5 — nenhuma lib do dnf5 lê
# aquele caminho. O equivalente funcional é o libdnf5-plugin-actions, que já
# vem instalado (é o que faz o cachy-default.actions funcionar).
#
# helper idempotente: reescreve a chave sem duplicar nem tocar nas demais
SNAPPER_CFG=/etc/snapper/configs/root
set_snapper_kv() {
  local key=$1 val=$2
  if grep -qE "^${key}=" "$SNAPPER_CFG"; then
    sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$SNAPPER_CFG"
  else
    printf '%s="%s"\n' "$key" "$val" >> "$SNAPPER_CFG"
  fi
}
if [ -f "$SNAPPER_CFG" ]; then
  # 5 no total. NUMBER_LIMIT e NUMBER_LIMIT_IMPORTANT iguais: se o segundo
  # fosse maior, os "importantes" (que têm par pre/post) estourariam o teto.
  set_snapper_kv NUMBER_LIMIT 5
  set_snapper_kv NUMBER_LIMIT_IMPORTANT 5
  # 300s em vez do padrão 3600: com 1h vários dnf no mesmo dia passariam do
  # teto. Com 300s o ponto derollback recém-criado nunca é apagado.
  set_snapper_kv NUMBER_MIN_AGE 300
  # Timeline desligado: o pacote snapper-timeline não existe no Fedora 44, então
  # TIMELINE_CREATE=yes não criaria nada — só confunde na leitura da config.
  set_snapper_kv TIMELINE_CREATE no
  set_snapper_kv TIMELINE_CLEANUP no
  for k in TIMELINE_LIMIT_HOURLY TIMELINE_LIMIT_DAILY TIMELINE_LIMIT_WEEKLY \
           TIMELINE_LIMIT_MONTHLY TIMELINE_LIMIT_QUARTERLY TIMELINE_LIMIT_YEARLY; do
    set_snapper_kv "$k" 0
  done
  set_snapper_kv EMPTY_PRE_POST_CLEANUP yes
  set_snapper_kv EMPTY_PRE_POST_MIN_AGE 0
  set_snapper_kv NUMBER_CLEANUP yes
  ok "snapper: teto de 5, min_age 300s, timeline desligado"
else
  warn "sem /etc/snapper/configs/root — limites do snapper não aplicados"
fi

# --- hook: snapshot automático em transação do dnf --------------------- #
# Fala com o snapperd por D-Bus em vez da CLI, como faz o plugin do dnf4.
# O "pre" grava o número em /run e o "post" fecha o par; sem o pre, um "post"
# solto não teria rollback associado.
cat > /tmp/snapper-dnf-hook.sh <<'HOOKEOF'
#!/bin/bash
set -u
CFG="${SNAPPER_CONFIG:-root}"
STATE_DIR=/run/snapper-dnf-hook
PRE_FILE="$STATE_DIR/pre-number"
mkdir -p "$STATE_DIR"
snap_call() {
  gdbus call --system --dest org.opensuse.Snapper \
    --object-path /org/opensuse/Snapper --method "$@"
}
snapshot_number() { printf '%s' "$1" | sed -n 's/.*uint32 \([0-9]\+\).*/\1/p'; }
run_cleanup() {
  # 3 tentativas: logo após criar o snapshot o snapperd ainda pode estar
  # terminando o trabalho interno e a chamada falha de forma transitória.
  local n
  for n in 1 2 3; do
    if snapper -c "$CFG" cleanup number 2>&1; then return 0; fi
    sleep 1
  done
  logger -t snapper-dnf-hook "aviso: cleanup number falhou após 3 tentativas"
  return 1
}
case "${1:-}" in
  pre)
    if out=$(snap_call org.opensuse.Snapper.CreatePreSnapshot \
      "$CFG" "dnf: antes da transação" number "{}"); then
      num=$(snapshot_number "$out")
      [ -n "$num" ] && printf '%s' "$num" > "$PRE_FILE"
      logger -t snapper-dnf-hook "pre-snapshot #$num criado"
    else
      logger -t snapper-dnf-hook "falha ao criar o pre-snapshot: ${out##*: }"
    fi ;;
  post)
    num=$(cat "$PRE_FILE" 2>/dev/null)
    [ -n "$num" ] || exit 0
    if out=$(snap_call org.opensuse.Snapper.CreatePostSnapshot \
      "$CFG" "$num" "dnf: depois da transação" number "{}"); then
      post=$(snapshot_number "$out")
      logger -t snapper-dnf-hook "post-snapshot #$post criado (par #$num)"
      rm -f "$PRE_FILE"
      run_cleanup
    else
      logger -t snapper-dnf-hook "falha ao criar o post-snapshot: ${out##*: }"
      rm -f "$PRE_FILE"
    fi ;;
esac
exit 0
HOOKEOF
try_warn install -m 755 /tmp/snapper-dnf-hook.sh /usr/local/bin/snapper-dnf-hook.sh
rm -f /tmp/snapper-dnf-hook.sh

# A direção fica VAZIA de propósito: "in" casaria só com instalação e "out" só
# com remoção, e um update de kernel passa pelas duas. Vazio = ambos os casos.
# Os argumentos do comando são separados por espaço, então o "pre"/"post" aqui
# são o $1 do script.
cat > /etc/dnf/libdnf5-plugins/actions.d/10-snapper.actions <<'ACTIONSEOF'
# Snapshots automaticos do snapper em transacoes do dnf5.
# Formato: callback:filtro:direcao:opcoes:comando (libdnf5-actions(8))
pre_transaction:*:::/usr/local/bin/snapper-dnf-hook.sh pre
post_transaction:*:::/usr/local/bin/snapper-dnf-hook.sh post
ACTIONSEOF

# prova de vida: os dois artefatos precisam estar no lugar
if [ -x /usr/local/bin/snapper-dnf-hook.sh ] &&
   [ -f /etc/dnf/libdnf5-plugins/actions.d/10-snapper.actions ]; then
  ok "hook de snapshot do dnf5 instalado (pre + post, cleanup a cada transação)"
  ok "acompanhe com: journalctl -t snapper-dnf-hook -f"
else
  warn "hook de snapshot do dnf5 incompleto"
fi

# --- grub-btrfs: submenu de snapshots no boot ------------------------ #
# O grub-btrfs do COPR kylegospo tem dois defeitos no Fedora:
#   1. o grub-btrfs.path do rpm vem com "Requires=\x2esnapshots.mount" (o
#      caractere \x2e literal no lugar do ponto), então a unit nunca ativa;
#   2. o script procura /boot/grub (Arch), mas no Fedora é /boot/grub2 — o
#      /etc/default/grub-btrfs/config do rpm já corrige esse ponto.
# Além disso, sem config do snapper não existe snapshot nenhum. A ordem aqui:
# config do snapper -> snapshot baseline -> path corrigido -> regenera grub.cfg.
if ! rpm_installed grub-btrfs; then
  try_warn dnf copr enable -y kylegospo/grub-btrfs
  try_warn dnf install -y grub-btrfs
fi
if rpm_installed grub-btrfs; then
  if ! snapper list-configs 2>/dev/null | grep -q '^root'; then
    try_warn snapper create-config /
    ok "config 'root' do snapper criada (subvolume /)"
  else
    ok "config 'root' do snapper já existe — pulando"
  fi
  # sem pelo menos um snapshot o submenu sai vazio. A linha "current" é um
  # pseudo-snapshot do snapper, por isso o filtro.
  if [ "$(snapper -c root list 2>/dev/null | grep -E 'single|pre|post' | grep -vc current)" -lt 1 ]; then
    try_warn snapper -c root create --description "baseline fedoraPI.sh" \
      --cleanup-algorithm number
    ok "snapshot baseline criado"
  else
    ok "snapshots do snapper já existem — pulando"
  fi
  # path corrigido: sem o Requires=\x2esnapshots.mount quebrado e sem depender
  # de /.snapshots.mount, que não existe nesta máquina
  if [ ! -f /etc/systemd/system/grub-btrfs.path ]; then
    cat > /etc/systemd/system/grub-btrfs.path <<'EOF'
[Unit]
Description=Monitors for new btrfs snapshots (override local do fedoraPI.sh)
DefaultDependencies=no

[Path]
PathModified=/.snapshots
Unit=grub-btrfs.service

[Install]
WantedBy=multi-user.target
EOF
    try_warn systemctl daemon-reload
    ok "grub-btrfs.path corrigido (o do rpm tem \\x2e no lugar do ponto)"
  else
    ok "grub-btrfs.path já corrigido — pulando"
  fi
  try_warn systemctl enable --now grub-btrfs.path
  # regenera o menu com o submenu de snapshots (backup antes, é arquivo crítico)
  if try_warn cp -a /boot/grub2/grub.cfg "/boot/grub2/grub.cfg.bak-$(date +%Y%m%d-%H%M%S)"; then
    try_warn grub2-mkconfig -o /boot/grub2/grub.cfg
  fi
  if grep -q "submenu 'Fedora Linux snapshots'" /boot/grub2/grub.cfg 2>/dev/null; then
    ok "submenu 'Fedora Linux snapshots' no menu do GRUB"
  else
    warn "grub.cfg sem o submenu de snapshots — revise 'grub2-mkconfig'"
  fi
  # com menu_auto_hide=1 o menu some (aparece só em erro), o que esconderia o
  # submenu de snapshots. No Fedora o comando é 'grub2-editenv - unset NOME':
  # o - é o nome do arquivo padrão e o comando vem antes dos argumentos.
  if grub2-editenv list 2>/dev/null | grep -q '^menu_auto_hide='; then
    try_warn grub2-editenv - unset menu_auto_hide
    ok "menu_auto_hide removido (menu do GRUB sempre visível)"
  else
    ok "menu do GRUB já sempre visível — pulando"
  fi
else
  warn "grub-btrfs não instalado — sem submenu de snapshots"
fi

# --- Secure Boot: chaves + assinatura do kernel/bootloader ----------- #
# O sbctl não está no Fedora: vem do COPR chenxiaolong/sbctl. O rpm do sbctl
# traz de brinde o plugin de kernel-install (/usr/lib/kernel/install.d/91-sbctl.install)
# e file triggers do rpm — é ele que reassina shim/grub quando um rpm os
# atualiza (verificado: um 'dnf reinstall grub2-efi-x64 shim-x64' reassinou
# os 13 binários da ESP sozinho). O que o script faz:
#   1. instala o sbctl pelo COPR
#   2. cria as chaves (se ainda não existirem) e enrolled nas variáveis EFI
#   3. assina cada kernel e cada binário da ESP, gravando no banco do sbctl
#      (-s) para que os triggers do rpm saibam o que reassinar
#   4. mostra o estado. LIGAR o Secure Boot é passo manual na BIOS do Lenovo
#      (o script não alcança o firmware): se estiver desligado NÃO é erro —
#      o sistema só não está validando as assinaturas.
if ! command -v sbctl >/dev/null 2>&1; then
  try_warn dnf copr enable -y chenxiaolong/sbctl
  try_warn dnf install -y sbctl
fi
if command -v sbctl >/dev/null 2>&1; then
  if [ ! -f /var/lib/sbctl/keys/db/db.pem ]; then
    try_warn sbctl create-keys
    ok "chaves do Secure Boot criadas"
  else
    ok "chaves do Secure Boot já existem — pulando"
  fi
  # grava as chaves nas variáveis EFI; em Setup Mode isso apenas prepara o
  # firmware. Se a máquina não for EFI (sem /sys/firmware/efi/efivars), pula.
  if [ -d /sys/firmware/efi/efivars ]; then
    # sbctl falha quando a máquina já saiu do Setup Mode ("Your system is not
    # in Setup Mode!") — e nesse caso as chaves JÁ estão enrolled. Só trate
    # como falha se a mensagem for outra coisa.
    if _out=$(sbctl enroll-keys 2>&1); then
      ok "chaves enrolled nas variáveis EFI (Setup Mode agora desativado)"
    elif printf '%s' "$_out" | grep -q "not in Setup Mode"; then
      ok "chaves já enrolled (máquina já saiu do Setup Mode) — nada a fazer"
    else
      warn "sbctl enroll-keys falhou: ${_out}"
    fi
  else
    warn "sem /sys/firmware/efi/efivars — máquina não está em UEFI, chaves não enrolled"
  fi
  # assina kernels e ESP (idempotente: o sbctl avisa "already signed" e segue)
  for f in /boot/vmlinuz-*; do
    [ -f "$f" ] || continue
    try_warn sbctl sign -s "$f"
  done
  for f in /boot/efi/EFI/*/*.efi /boot/efi/EFI/*/*.EFI /boot/efi/EFI/BOOT/*.efi; do
    [ -f "$f" ] || continue
    try_warn sbctl sign -s "$f"
  done
  unsigned=$(sbctl verify 2>/dev/null | grep -c 'not signed' || true)
  if [ "${unsigned:-0}" -eq 0 ]; then
    ok "cadeia de boot inteira assinada (shim -> grub -> kernel)"
  else
    warn "$unsigned arquivo(s) da ESP sem assinatura — revise com 'sbctl verify'"
  fi
  # 'sbctl status' imprime "Secure Boot:\t✓ Enabled" ou "\t✗ Disabled" — o
  # ✓ é o único sinal confiável, porque "Disabled" contém "Enabled".
  sb_line=$(sbctl status 2>/dev/null | grep -E '^Secure Boot' | head -1 || true)
  # sb_line já vem como "Secure Boot:\tEnabled" — prefixar de novo duplicava.
  ok "Secure Boot: $(printf '%s' "${sb_line:-estado desconhecido}" | tr -s '\t' ' ' | sed 's/^Secure Boot: *//; s/^$/estado desconhecido/')"
  if ! printf '%s' "$sb_line" | grep -q '✓'; then
    warn "Secure Boot continua DESLIGADO — ative na BIOS do Lenovo (Security > Secure Boot) e reinicie"
  fi
else
  warn "sbctl não instalado — Secure Boot não configurado (veja o log acima)"
fi
phase_end "$_f0" "tuning de kernel aplicado"

# --------------------------------------------------------------- #
# 13. FASES DE RUNTIME (rpm do gh / AppImage / zip / curl|sh)     #
# --------------------------------------------------------------- #
step "Fase 13/13 — fases pós-dnf (phases.txt runtime)"
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

# --------------------------------------------------------------- #
# RESTAURAÇÃO DE BACKUPS (zip em ~/Downloads/backups/)            #
# --------------------------------------------------------------- #
step "Restauração de backups (~/Downloads/backups/)"
BACKUP_DIR="$SUH/Downloads/backups"
if [ ! -d "$BACKUP_DIR" ]; then
  ok "pasta $BACKUP_DIR não existe — pulando"
elif [ ! -t 0 ]; then
  # Esta fase é interativa (read). Sem TTY o 'read' devolve 1 e o set -e
  # encerraria o script inteiro — melhor pular com aviso.
  warn "fase de backups é interativa e o stdin não é um TTY — pulando"
  warn "rode o fedoraPI.sh num terminal para restaurar os zips"
else
  shopt -s nullglob
  for zip in "$BACKUP_DIR"/*.zip; do
    [ -f "$zip" ] || continue
    base=$(basename "$zip" .zip)
    echo
    echo "=== Processando: $base ==="

    # Extrai para temp
    tmpd=$(mktemp -d -t "bkp-$base-XXXXXX")
    if ! unzip -q "$zip" -d "$tmpd"; then
      warn "falha ao extrair $zip"
      rm -rf "$tmpd"
      continue
    fi

    # Detecta estrutura: pasta única ou arquivos na raiz
    entries=("$tmpd"/*)
    if [ ${#entries[@]} -eq 1 ] && [ -d "${entries[0]}" ]; then
      # Pasta única — entra nela
      workdir="${entries[0]}"
    else
      # Arquivos/pastas soltos na raiz
      workdir="$tmpd"
    fi

    # Lista itens (pastas e arquivos) para seleção
    mapfile -t items < <(find "$workdir" -mindepth 1 -maxdepth 1 -print0 | xargs -0 -n1 basename | sort)
    if [ ${#items[@]} -eq 0 ]; then
      warn "zip vazio: $zip"
      rm -rf "$tmpd"
      continue
    fi

    echo "Itens em $base:"
    for i in "${!items[@]}"; do
      item_path="$workdir/${items[i]}"
      if [ -d "$item_path" ]; then
        count=$(find "$item_path" -type f | wc -l)
        printf "  [%2d] %s/  (%d arquivos)\n" $((i+1)) "${items[i]}" "$count"
      else
        printf "  [%2d] %s\n" $((i+1)) "${items[i]}"
      fi
    done

    # Seleção estilo checkbox (números separados por espaço)
    echo -n "Escolha itens para restaurar (ex.: 1 3 5, Enter=todos, q=pular): "
    read -r sel || sel=""
    if [[ "$sel" =~ ^[qQ]$ ]]; then
      echo "Pulando $zip"
      rm -rf "$tmpd"
      continue
    fi

    chosen=()
    if [ -z "$sel" ]; then
      # Enter = todos
      chosen=("${items[@]}")
    else
      for num in $sel; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#items[@]} ]; then
          chosen+=("${items[num-1]}")
        else
          warn "número inválido: $num (ignorado)"
        fi
      done
    fi

    if [ ${#chosen[@]} -eq 0 ]; then
      echo "Nenhum item selecionado — pulando $zip"
      rm -rf "$tmpd"
      continue
    fi

    # Para cada item escolhido: pergunta destino (usa pasta do zip como sugestão)
    for item in "${chosen[@]}"; do
      src="$workdir/$item"
      if [ ! -e "$src" ]; then
        warn "não encontrado: $src"
        continue
      fi

      # Sugestão de destino baseada no nome do item
      if [ -d "$src" ]; then
        suggested="$SUH/$item"
      else
        suggested="$SUH/$(basename "$item")"
      fi

      echo -n "Destino para '$item' [$suggested]: "
      read -r dest || dest=""
      dest="${dest:-$suggested}"
      dest="${dest/#\~/$SUH}"

      # Cria diretório pai se necessário
      try_warn mkdir -p "$(dirname "$dest")"

      # Move (usa rsync para preservar atributos e mostrar progresso)
      echo "Movendo $item -> $dest"
      if rsync -a --info=progress2 "$src/" "$dest/" 2>/dev/null || rsync -a "$src/" "$dest/"; then
        ok "restaurado: $item -> $dest"
      else
        warn "falha ao mover $item"
      fi
    done

    # Remove o zip original
    if try_warn rm -f "$zip"; then
      ok "zip $zip removido"
    else
      warn "não foi possível remover $zip (conferir permissões)"
    fi

    # Limpa temp
    rm -rf "$tmpd"
  done
  shopt -u nullglob
fi
ok "restauração de backups concluída"
