# Shared helpers for fedorapi.

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LISTS="$SCRIPT_DIR/lists"
readonly DOTFILES_REPO="https://github.com/EmanuProds/dotfiles.git"
readonly ACCENT_SYNC_REPO="https://github.com/EmanuProds/accent-sync.git"
readonly TITLEBAR_REPO="https://github.com/EmanuProds/opencode-desktop-titlebar.git"
readonly CLONES="/tmp/fedorapi-clones"
readonly LOG="/tmp/fedorapi.log"
readonly FDC="$(rpm -E %fedora)"

exec 3>&1
: > "$LOG"
exec >"$LOG" 2>&1

readonly C_RED=$'\e[1;31m' C_GRN=$'\e[1;32m' C_YEL=$'\e[1;33m' C_BLU=$'\e[1;34m' C_OFF=$'\e[0m'
step() { printf '\n%s== %s ==%s\n' "$C_BLU" "$*" "$C_OFF" >&3; printf '\n== %s ==\n' "$*"; }
ok()   { printf '%s[OK]%s %s\n'   "$C_GRN" "$C_OFF" "$*" >&3; printf '[OK] %s\n' "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YEL" "$C_OFF" "$*" >&3; printf '[WARN] %s\n' "$*"; }
die()  { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_OFF" "$*" >&3; printf '[FAIL] %s\n' "$*" >&2; exit 1; }

FAIL_COUNT=0
mark_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); }
try_warn() { "$@" || { warn "non-critical: $*"; mark_fail; }; }

set -o errtrace
trap 'rc=$?; printf "\n[FATAL] line %s returned %s\n" "$LINENO" "$rc" >&3; printf "[FATAL] line %s returned %s\n" "$LINENO" "$rc"; exit "$rc"' ERR

phase_end() {
  local before="$1" text="$2"
  if [ "$FAIL_COUNT" -eq "$before" ]; then ok "$text"; else warn "$((FAIL_COUNT - before)) step(s) failed"; fi
}

[ "$(id -u)" -eq 0 ] || die "run with sudo"
SUDO_USER="${SUDO_USER:-}"
[ -n "$SUDO_USER" ] || die "SUDO_USER undefined"
readonly SUH="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
readonly UID_R="$(id -u "$SUDO_USER")"

read_list() { grep -vE '^\s*(#|$)' "$1" | sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//' | grep -vE '^$'; }

rpm_installed()      { rpm -q "$1" >/dev/null 2>&1; }
flatpak_installed()  { flatpak list --system --columns=application 2>/dev/null | grep -qx "$1"; }
flatpak_appid() {
  local ref="$1"
  case "${ref%%/*}" in flathub|fedora|oci) ref="${ref#*/}" ;; esac
  printf '%s' "${ref%%/*}"
}
service_enabled() { systemctl is-enabled "$1" >/dev/null 2>&1; }
command_exists()  { command -v "$1" >/dev/null 2>&1; }
npm_global_installed() { "$SUH/.bun/bin/bun" pm -g ls --depth=0 2>/dev/null | grep -q "$1@"; }
omniroute_installed() { [ -x "$SUH/.bun/bin/omniroute" ] || command -v omniroute >/dev/null 2>&1; }
gopls_installed() { [ -x "$SUH/.go/bin/gopls" ] || command -v gopls >/dev/null 2>&1; }

# bun skips the @opencode/cli postinstall, leaving a 229-byte "not run" stub at
# bin/opencode.exe. Repair it in place so `opencode` works without a reinstall.
opencode_cli_heal() {
  local dir="$SUH/.bun/install/global/node_modules/@opencode/cli"
  local bin="$dir/bin/opencode.exe" post="$dir/postinstall.mjs"
  local native="$SUH/.bun/install/global/node_modules/@opencode/cli-linux-x64"

  if [ ! -x "$SUH/.bun/bin/bun" ] || [ ! -f "$post" ]; then
    warn "opencode CLI: bun or postinstall.mjs not found — repair skipped"
    return 0
  fi
  if [ -f "$bin" ] && ! grep -q 'postinstall script was not run' "$bin" 2>/dev/null; then
    return 0
  fi

  ok "opencode CLI: install stub found — repairing"
  if [ ! -x "$native/bin/opencode" ]; then
    try_warn run_spin "installing opencode native binary" \
      as_user "$SUH/.bun/bin/bun" add -g --silent @opencode/cli-linux-x64
  fi
  try_warn run_spin "running opencode postinstall" as_user "$SUH/.bun/bin/bun" "$post"

  if as_user "$SUH/.bun/bin/opencode" --version >/dev/null 2>&1; then
    ok "opencode CLI working ($(as_user "$SUH/.bun/bin/opencode" --version 2>/dev/null))"
  else
    warn "opencode CLI still broken — rerun phase 03 or check $LOG"
    mark_fail
  fi
}

sbctl_keys_enrolled() {
  local tmp_root tmp k exported a b
  tmp_root=$(mktemp -d /var/tmp/sbctl-check-XXXXXX) || return 2
  tmp="$tmp_root/export"
  if ! sbctl --disable-landlock export-enrolled-keys --dir "$tmp" --format der >/dev/null 2>&1; then
    rm -rf "$tmp_root"; return 2
  fi
  for k in PK KEK db; do
    case "$k" in PK) d=PK ;; KEK) d=KEK ;; db) d=DB ;; esac
    exported=$(find "$tmp/$d" -name '*.der' 2>/dev/null | head -1)
    if [ -z "$exported" ] || [ ! -f "/var/lib/sbctl/keys/$k/$k.pem" ]; then rm -rf "$tmp_root"; return 1; fi
    a=$(openssl x509 -inform der -in "$exported" -noout -fingerprint -sha1 2>/dev/null | cut -d= -f2)
    b=$(openssl x509 -in "/var/lib/sbctl/keys/$k/$k.pem" -noout -fingerprint -sha1 2>/dev/null | cut -d= -f2)
    if [ -z "$a" ] || [ "$a" != "$b" ]; then rm -rf "$tmp_root"; return 1; fi
  done
  rm -rf "$tmp_root"; return 0
}

sbctl_has_option_rom() {
  local rom
  for rom in /sys/bus/pci/devices/*/rom; do [ -e "$rom" ] && [ -s "$rom" ] && return 0; done
  return 1
}

as_user() {
  runuser -u "$SUDO_USER" -- env \
    HOME="$SUH" XDG_RUNTIME_DIR="/run/user/$UID_R" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_R/bus" \
    PATH="$SUH/.bun/bin:$SUH/.local/bin:$SUH/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin" \
    "$@"
}

clone_repo() {
  local url="$1" dest="$2" i
  rm -rf "$dest"
  for i in 1 2 3; do
    if run_spin "cloning $(basename "$dest")" timeout 120 git clone --depth 1 --quiet "$url" "$dest" 2>/dev/null; then
      ok "clone: $(basename "$dest")"
      return 0
    fi
    warn "git clone failed (attempt $i/3): $url"
    sleep 5
  done
  die "git clone failed: $url"
}

# Per-phase interactive prompt (10s timeout with countdown, auto-yes). TTY only.
ask_phase() {
  local num="$1" desc="$2" ans i
  if [ ! -t 0 ]; then return 0; fi
  printf '\n%s[Phase %s]%s %s — run? [Y/n] ' "$C_BLU" "$num" "$C_OFF" "$desc" >&3
  printf '\n[Phase %s] %s — run? [Y/n] ' "$num" "$desc"
  for ((i=10; i>=1; i--)); do
    printf '\r%s[Phase %s]%s %s — run? [Y/n] (%d) ' "$C_BLU" "$num" "$C_OFF" "$desc" "$i" >&3
    if read -r -t 1 ans; then
      case "$ans" in n|N|no|NO) printf '\n' >&3; return 1 ;; esac
      printf '\n' >&3; return 0
    fi
  done
  printf '\n' >&3
  return 0
}

# Animated spinner: runs a command with a spinner in the terminal.
run_spin() {
  local msg="$1"; shift
  local pid spinner='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r%s %s' "${spinner:i:1}" "$msg" >&3
    i=$(( (i+1) % ${#spinner} ))
    sleep 0.1
  done
  wait "$pid"
  local rc=$?
  printf '\r\033[K' >&3
  return $rc
}

set_snapper_kv() {
  local key=$1 val=$2 cfg=/etc/snapper/configs/root
  if grep -qE "^${key}=" "$cfg"; then
    sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$cfg"
  else
    printf '%s="%s"\n' "$key" "$val" >> "$cfg"
  fi
}
