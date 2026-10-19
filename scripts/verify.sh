#!/bin/bash
# Oracle do fedorapi — falha fechada: qualquer falha => exit != 0
# Valida o script, as listas e o estado PUBLICADO dos tres repos de origem
# (dotfiles, accent-sync, opencode-desktop-titlebar).
set -u
# raiz do repo descoberta a partir do próprio oracle: o path absoluto antigo
# ("Área de trabalho/...") não existe mais e reprovava todos os gates
R="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES="https://github.com/EmanuProds/dotfiles.git"
ACCENT="https://github.com/EmanuProds/accent-sync.git"
TITLEBAR="https://github.com/EmanuProds/opencode-desktop-titlebar.git"
CACHE="/tmp/fedorapi-oracle"
fail=0
ok()  { echo "OK   : $1"; }
bad() { echo "FAIL : $1"; fail=1; }

# --- 1. listas presentes e não vazias
for f in lists/packages.txt lists/removals.txt \
         lists/phases.txt lists/repos.txt lists/extensions.txt lists/flatpak.txt \
         lists/services.txt lists/mise.txt lists/npm.txt; do
  [ -s "$R/$f" ] && ok "lista $f" || bad "lista $f ausente/vazia"
done

# --- 2. script fedoraPI.sh
bash -n "$R/install.sh" && ok "install.sh sintaxe" || bad "install.sh sintaxe"
grep -q 'set -euo pipefail' "$R/install.sh" && ok "set -euo pipefail" || bad "sem set -euo pipefail"
! grep -qE '\bdialog\b' "$R/fedoraPI.sh" && ok "sem dialog" || bad "dialog presente"
# cores/plymouth/URLs podem estar em lib/ (estrutura modular)
for v in 'e\[1;31m' 'e\[1;33m' 'e\[1;32m'; do
  grep -rqE "$v" "$R/lib" "$R/install.sh" && ok "cor $v definida" || bad "cor $v faltando"
done
grep -rq 'VerticalAlignment' "$R/lib" "$R/install.sh" && ok "plymouth VerticalAlignment" || bad "plymouth tweak ausente"
# GDM: fase 16 deve existir e aplicar a escala de interface no login screen
[ -f "$R/lib/phases/16.sh" ] && ok "fase 16 (GDM)" || bad "fase 16 (GDM) ausente"
grep -q 'text-scaling-factor' "$R/lib/phases/16.sh" && ok "GDM aplica text-scaling-factor" || bad "GDM sem text-scaling-factor"
grep -q '99-gdm-scale' "$R/lib/phases/16.sh" && ok "GDM keyfile 99- (vence o 95- da extensão)" || bad "GDM keyfile 99- ausente"
grep -q 'monitors.xml' "$R/lib/phases/16.sh" && ok "GDM copia monitors.xml" || bad "GDM sem cópia de monitors.xml"
grep -q 'system-db:gdm' "$R/lib/phases/16.sh" && ok "GDM cria profile dconf" || bad "GDM sem profile dconf"
grep -q '"16:GDM' "$R/install.sh" && ok "install.sh registra fase 16" || bad "install.sh sem fase 16"
! grep -rq 'pip install' "$R/lib" "$R/install.sh" && ok "sem pip install (PEP 668)" || bad "pip install presente"
for repo in "$DOTFILES" "$ACCENT" "$TITLEBAR"; do
  grep -rq "$repo" "$R/lib" "$R/install.sh" && ok "URL no script: $(basename "$repo" .git)" \
    || bad "URL ausente no script: $repo"
done
# o fedorapi nao deve mais carregar dotfiles/scripts duplicados
for d in src phases opencode units gnome; do
  [ ! -e "$R/$d" ] && ok "$d/ removido (vem por clone)" || bad "$d/ ainda existe (duplicado)"
done

# --- 3. repos publicados: vivos e com o conteudo esperado
rm -rf "$CACHE"; mkdir -p "$CACHE"
clone() { git clone --depth 1 --quiet "$1" "$2" 2>/dev/null; }
clone "$DOTFILES" "$CACHE/dotfiles"   && ok "clone dotfiles"   || bad "clone dotfiles falhou"
clone "$ACCENT"   "$CACHE/accent"     && ok "clone accent-sync" || bad "clone accent-sync falhou"
clone "$TITLEBAR" "$CACHE/titlebar"   && ok "clone titlebar"    || bad "clone titlebar falhou"

# dotfiles: home, dconf, config do opencode + skills, sem caminho fixo
[ -s "$CACHE/dotfiles/home/.bashrc" ] && ok "dotfiles .bashrc" || bad "dotfiles .bashrc ausente"
! grep -q '/home/emanuel' "$CACHE/dotfiles/home/.bashrc" && ok "dotfiles .bashrc sem path hardcoded" \
  || bad "dotfiles .bashrc com path hardcoded"
grep -q 'export GOPATH="\$HOME/.go"' "$CACHE/dotfiles/home/.bashrc" \
  && ok "dotfiles .bashrc configura GOPATH" || bad "dotfiles .bashrc sem GOPATH"
[ -s "$CACHE/dotfiles/home/.config/go/env" ] && ok "dotfiles go/env" || bad "dotfiles go/env ausente"
[ -s "$CACHE/dotfiles/home/.config/environment.d/go.conf" ] && ok "dotfiles environment.d/go.conf" \
  || bad "dotfiles environment.d/go.conf ausente"
[ -s "$CACHE/dotfiles/home/.config/ghostty/config" ] && ok "dotfiles ghostty" || bad "dotfiles ghostty ausente"
[ -s "$CACHE/dotfiles/home/.config/zed/settings.json" ] && ok "dotfiles zed" || bad "dotfiles zed ausente"
[ -s "$CACHE/dotfiles/home/.local/share/photogimp/GIMP/3.0/gimprc" ] && ok "dotfiles photogimp" || bad "dotfiles photogimp ausente"
[ -s "$CACHE/dotfiles/home/.local/share/photogimp/GIMP/3.0/shortcutsrc" ] && ok "dotfiles photogimp shortcuts" || bad "dotfiles photogimp shortcuts ausente"
[ -s "$CACHE/dotfiles/home/.local/share/themes/adw-inkscape/gtk-3.0/gtk.css" ] && ok "dotfiles adw-inkscape" || bad "dotfiles adw-inkscape ausente"
[ -s "$CACHE/dotfiles/home/.config/inkscape/ui/style.css" ] && ok "dotfiles inkscape style.css" || bad "dotfiles inkscape style.css ausente"
[ -s "$CACHE/dotfiles/home/.config/inkscape/preferences.xml" ] && ok "dotfiles inkscape preferences" || bad "dotfiles inkscape preferences ausente"
! grep -q '/home/emanuel' "$CACHE/dotfiles/home/.config/inkscape/preferences.xml" \
  && ok "dotfiles inkscape preferences sem path hardcoded" \
  || bad "dotfiles inkscape preferences com path hardcoded"
# Webapps (PWA): launchers + icones + pasta WebApps no overview
n_ffpwa=$(find "$CACHE/dotfiles/home/.local/share/applications" -name 'FFPWA-*.desktop' 2>/dev/null | wc -l)
[ "$n_ffpwa" -ge 10 ] && ok "dotfiles webapps FFPWA ($n_ffpwa launchers)" || bad "dotfiles webapps FFPWA ($n_ffpwa launchers)"
n_ffpwa_ico=$(find "$CACHE/dotfiles/home/.local/share/icons/hicolor" -name 'FFPWA-*.png' 2>/dev/null | wc -l)
[ "$n_ffpwa_ico" -ge 10 ] && ok "dotfiles icones FFPWA ($n_ffpwa_ico pngs)" || bad "dotfiles icones FFPWA ($n_ffpwa_ico pngs)"
grep -q 'folders/WebApps' "$CACHE/dotfiles/dconf/gnome-settings.ini" \
  && ok "dotfiles pasta WebApps no dconf" || bad "dotfiles sem pasta WebApps no dconf"
[ -s "$CACHE/dotfiles/dconf/gnome-settings.ini" ] && ok "dotfiles dconf dump" || bad "dconf dump ausente"
! grep -qiE 'password|secret|token|api_key' "$CACHE/dotfiles/dconf/gnome-settings.ini" \
  && ok "dconf sem secrets" || bad "dconf pode conter secrets"
python3 -c "import json;json.load(open('$CACHE/dotfiles/opencode/config/opencode.json'))" \
  && ok "dotfiles opencode.json parse" || bad "dotfiles opencode.json invalido"
! grep -q '/home/emanuel' "$CACHE/dotfiles/opencode/config/opencode.json" \
  && ok "json oficial sem path hardcoded" || bad "json oficial com path hardcoded"
! grep -qE '"(model|default_agent|agents|shell)"' "$CACHE/dotfiles/opencode/config/opencode.json" \
  && ok "json oficial sem model/agents/shell" || bad "json oficial tem model/agents/shell"
grep -q '"skills"' "$CACHE/dotfiles/opencode/config/opencode.json" && ok "json com skills" || bad "skills ausente no json"
grep -q '"lsp"' "$CACHE/dotfiles/opencode/config/opencode.json" && ok "json com lsp" || bad "lsp ausente no json"
! grep -q 'config/opencode/skills' "$CACHE/dotfiles/opencode/config/opencode.json" \
  && ok "json aponta skills para ~/.agents/skills" || bad "json ainda aponta para opencode/skills"
grep -q '"context7"' "$CACHE/dotfiles/opencode/config/opencode.json" && ok "mcp context7" || bad "context7 ausente"
# o que NAO deve existir no repo de dotfiles
for f in opencode/agents opencode/docs opencode/lib opencode/config/AGENTS.full.md \
         opencode/config/opencode.pessoal.json opencode/skills; do
  [ ! -e "$CACHE/dotfiles/$f" ] && ok "fora do repo: $f" || bad "$f ainda no repo dotfiles"
done
n_skills=$(ls "$CACHE/dotfiles/skills" 2>/dev/null | wc -l)
[ "$n_skills" -ge 184 ] && ok "skills na raiz do repo ($n_skills >= 184)" || bad "skills ($n_skills/184)"
[ -s "$CACHE/dotfiles/opencode/plugins/memory-store.ts" ] && ok "memory-store.ts" || bad "memory-store.ts ausente"
[ -s "$CACHE/dotfiles/opencode/config/AGENTS.md" ] && ok "AGENTS.md slim" || bad "AGENTS.md slim ausente"
[ -s "$CACHE/dotfiles/opencode/config/env.example" ] && ok "env.example" || bad "env.example ausente"
[ ! -e "$CACHE/dotfiles/.env" ] && ok "sem .env real no dotfiles" || bad ".env REAL no dotfiles (SEGREDO)"

# accent-sync: auxiliar + units
[ -x "$CACHE/accent/accent-sync" ] && ok "accent-sync executável" || bad "accent-sync sem bit +x"
grep -q 'PathChanged=%h/.config/dconf/user' "$CACHE/accent/units/accent-sync.path" \
  && ok "accent-sync.path trigger dconf" || bad "accent-sync.path sem trigger do dconf"
grep -q 'ExecStart=%h/.local/bin/accent-sync' "$CACHE/accent/units/accent-sync.service" \
  && ok "accent-sync.service ExecStart" || bad "accent-sync.service ExecStart errado"

# titlebar: patch + units + compilacao
python3 -m py_compile "$CACHE/titlebar/opencode-desktop-titlebar-patch" \
  && ok "py_compile do patch (clone)" || bad "py_compile do patch (clone)"
grep -q 'app.asar' "$CACHE/titlebar/units/opencode-titlebar-patch.path" \
  && ok "titlebar path unit" || bad "titlebar path unit"
[ "$(grep -c 'Type=oneshot' "$CACHE/titlebar/units/opencode-titlebar-patch.service")" -eq 1 ] \
  && ok "service Type único" || bad "service duplicado"
grep -q 'rpm", "-ql"' "$CACHE/titlebar/opencode-desktop-titlebar-patch" \
  && ok "patch detecta rpm (Fedora)" || bad "patch sem detecção rpm"
[ -s "$CACHE/titlebar/pacman-hook.hook" ] && ok "pacman-hook.hook (Arch)" || bad "pacman-hook.hook ausente"

# patch: aplica e é idempotente numa cópia scratch (asar real NUNCA tocado)
asar_real=$(pacman -Ql opencode-desktop-bin 2>/dev/null | grep -E 'app\.asar$' | head -1 | cut -d' ' -f2 | tr -d '\n')
if [ -n "$asar_real" ] && [ -f "$asar_real" ]; then
  tmp=$(mktemp /tmp/asar-scratch.XXXX)
  cp "$asar_real" "$tmp"
  OPENCODE_ASAR_OVERRIDE="$tmp" OPENCODE_PATCH_HOME=/tmp \
    python3 "$CACHE/titlebar/opencode-desktop-titlebar-patch" apply >/dev/null 2>&1 \
    && ok "patch apply (scratch) exit 0" || bad "patch apply falhou"
  OPENCODE_ASAR_OVERRIDE="$tmp" OPENCODE_PATCH_HOME=/tmp \
    python3 "$CACHE/titlebar/opencode-desktop-titlebar-patch" --check >/dev/null 2>&1 \
    && ok "patch idempotente (--check exit 0)" || bad "patch não idempotente"
  rm -f "$tmp"
else
  echo "SKIP : asar real não encontrado nesta máquina (gate ignorado isoladamente)"
fi
# --- 4. dump do dconf: limpo, sem estado pessoal nem caminhos absolutos
DC="$CACHE/dotfiles/dconf/gnome-settings.ini"
DC_CFG=$(grep -vE '^\s*(#|$)' "$DC")
python3 -c "
import configparser, sys
cp = configparser.ConfigParser(strict=False, interpolation=None)
cp.optionxform = str
cp.read('$DC', encoding='utf-8')
print('secoes:', len(cp.sections()))
" >/dev/null 2>&1 && ok "dconf parse ok ($(echo "$DC_CFG" | grep -c '^\[') seções)" || bad "dconf não parseia"
echo "$DC_CFG" | grep -q '/home/' && bad "dconf tem caminho absoluto" || ok "dconf sem caminhos absolutos"
echo "$DC_CFG" | grep -qE '^\[org/gnome/portal' && bad "dconf com permissões de portal" || ok "dconf sem permissões de portal"
# net/nokyan/Resources e io/github/seadve/Kooha ficam de fora da lista: sao instalados via Terra
echo "$DC_CFG" | grep -qE '^\[(org/gnome/(evolution|papers|weather|Weather|Showtime|Ptyxis|clocks|system|software|app-folders|Resources)|org/virt-manager)' && bad "dconf com schema de app ausente" || ok "dconf sem schemas de apps ausentes"
echo "$DC_CFG" | grep -q 'picture-uri' && bad "dconf ainda fixa papel de parede" || ok "dconf sem papel de parede fixo"
echo "$DC_CFG" | grep -q '^favorite-apps=' && ok "dconf preserva o dock" || bad "dconf perdeu o dock (favorite-apps)"
echo "$DC_CFG" | grep -q "^\[org/gnome/desktop/interface\]" && ok "dconf com interface do GNOME" || bad "dconf sem interface do GNOME"
# cada UUID habilitado precisa estar na lista de extensões instalada
python3 - "$R" "$DC" <<'PYEOF2' && ok "dconf: extensões habilitadas ⊂ extensions.txt" || bad "dconf habilita extensão não instalada"
import re, sys
ext = {l.split("#")[0].strip() for l in open(sys.argv[1] + "/lists/extensions.txt", encoding="utf-8") if l.split("#")[0].strip()}
txt = open(sys.argv[2], encoding="utf-8").read()
m = re.search(r"^enabled-extensions=\[(.*?)\]", txt, re.M)
forbidos = [u for u in re.findall(r"'([^']+)'", m.group(1)) if u not in ext] if m else ["<sem lista enabled-extensions>"]
if forbidos:
    print("   nao instaladas:", ", ".join(forbidos)); sys.exit(1)
PYEOF2

exit $fail
