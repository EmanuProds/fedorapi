#!/bin/bash
# fedorapi oracle — fails closed: any failure => exit != 0
# Validates the script, the lists and the PUBLISHED state of the three source repos
# (dotfiles, accent-sync, opencode-desktop-titlebar).
set -u
# repo root discovered from the oracle itself: the old hardcoded absolute path
# no longer exists and failed every gate
R="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES="https://github.com/EmanuProds/dotfiles.git"
ACCENT="https://github.com/EmanuProds/accent-sync.git"
TITLEBAR="https://github.com/EmanuProds/opencode-desktop-titlebar.git"
CACHE="/tmp/fedorapi-oracle"
fail=0
ok()  { echo "OK   : $1"; }
bad() { echo "FAIL : $1"; fail=1; }

# --- 1. lists present and non-empty
for f in lists/packages.txt lists/removals.txt \
         lists/phases.txt lists/repos.txt lists/extensions.txt lists/flatpak.txt \
         lists/services.txt lists/mise.txt lists/npm.txt; do
  [ -s "$R/$f" ] && ok "list $f" || bad "list $f missing/empty"
done

# --- 2. install.sh script
bash -n "$R/install.sh" && ok "install.sh syntax" || bad "install.sh syntax"
grep -q 'set -euo pipefail' "$R/install.sh" && ok "set -euo pipefail" || bad "missing set -euo pipefail"
! grep -qE '\bdialog\b' "$R/install.sh" && ok "no dialog" || bad "dialog present"
# colors/plymouth/URLs may live in lib/ (modular structure)
for v in 'e\[1;31m' 'e\[1;33m' 'e\[1;32m'; do
  grep -rqE "$v" "$R/lib" "$R/install.sh" && ok "color $v defined" || bad "color $v missing"
done
grep -rq 'VerticalAlignment' "$R/lib" "$R/install.sh" && ok "plymouth VerticalAlignment" || bad "plymouth tweak missing"
# GDM: phase 16 must exist and apply the interface scale on the login screen
[ -f "$R/lib/phases/16.sh" ] && ok "phase 16 (GDM)" || bad "phase 16 (GDM) missing"
grep -q 'text-scaling-factor' "$R/lib/phases/16.sh" && ok "GDM applies text-scaling-factor" || bad "GDM without text-scaling-factor"
grep -q '99-gdm-scale' "$R/lib/phases/16.sh" && ok "GDM keyfile 99- (beats the extension's 95-)" || bad "GDM keyfile 99- missing"
grep -q 'monitors.xml' "$R/lib/phases/16.sh" && ok "GDM copies monitors.xml" || bad "GDM without monitors.xml copy"
grep -q 'system-db:gdm' "$R/lib/phases/16.sh" && ok "GDM creates dconf profile" || bad "GDM without dconf profile"
grep -q '"16:GDM' "$R/install.sh" && ok "install.sh registers phase 16" || bad "install.sh without phase 16"
# Phase 6: VM networking/firewall (masquerade + Docker/Tailscale forwarding + DNS)
[ -f "$R/lib/phases/06.sh" ] && ok "phase 06 (virtualization)" || bad "phase 06 missing"
grep -q 'masquerade' "$R/lib/phases/06.sh" && ok "phase 06: firewalld masquerade" || bad "phase 06 without masquerade"
grep -q 'usermod -aG libvirt' "$R/lib/phases/06.sh" && ok "phase 06: user added to libvirt group" || bad "phase 06 without libvirt group"
grep -q 'libvirt-vm-forward' "$R/lib/phases/06.sh" && ok "phase 06: libvirt-vm-forward persistence" || bad "phase 06 without libvirt-vm-forward"
grep -q "forwarder addr" "$R/lib/phases/06.sh" && ok "phase 06: dnsmasq DNS forwarders" || bad "phase 06 without DNS forwarders"
# Git: phase 17 asks the user for the global identity (no fixed value in the repo)
[ -f "$R/lib/phases/17.sh" ] && ok "phase 17 (git)" || bad "phase 17 (git) missing"
grep -q 'user.name' "$R/lib/phases/17.sh" && ok "git: asks for user.name" || bad "git without user.name"
grep -q 'user.email' "$R/lib/phases/17.sh" && ok "git: asks for user.email" || bad "git without user.email"
grep -q 'as_user git config --global' "$R/lib/phases/17.sh" \
  && ok "git: writes to SUDO_USER's ~/.gitconfig" || bad "git config without as_user"
grep -q 'ssh-add' "$R/lib/phases/17.sh" && ok "git: adds the key to ssh-agent" || bad "git without ssh-add"
grep -q 'ssh-agent -s' "$R/lib/phases/17.sh" && ok "git: starts ssh-agent when needed" || bad "git without ssh-agent -s"
grep -q 'ssh -T.*git@github.com' "$R/lib/phases/17.sh" \
  && ok "git: tests ssh -T git@github.com" || bad "git without ssh -T git@github.com test"
grep -q 'git-credentials' "$R/lib/phases/17.sh" && ok "git: HTTPS credentials (~/.git-credentials)" || bad "git without ~/.git-credentials"
grep -q 'credential.helper' "$R/lib/phases/17.sh" && ok "git: enables credential.helper store" || bad "git without credential.helper"
grep -q '\[y/n\]' "$R/lib/phases/17.sh" && ok "git: asks the y/n credentials question" || bad "git without y/n question"
grep -q '"17:Git' "$R/install.sh" && ok "install.sh registers phase 17" || bad "install.sh without phase 17"
! grep -rq 'pip install' "$R/lib" "$R/install.sh" && ok "no pip install (PEP 668)" || bad "pip install present"
for repo in "$DOTFILES" "$ACCENT" "$TITLEBAR"; do
  grep -rq "$repo" "$R/lib" "$R/install.sh" && ok "URL in the script: $(basename "$repo" .git)" \
    || bad "URL missing in the script: $repo"
done
# fedorapi must no longer carry duplicated dotfiles/scripts
for d in src phases opencode units gnome; do
  [ ! -e "$R/$d" ] && ok "$d/ removed (comes by clone)" || bad "$d/ still exists (duplicated)"
done

# --- 3. published repos: alive and with the expected content
rm -rf "$CACHE"; mkdir -p "$CACHE"
clone() { git clone --depth 1 --quiet "$1" "$2" 2>/dev/null; }
clone "$DOTFILES" "$CACHE/dotfiles"   && ok "clone dotfiles"   || bad "dotfiles clone failed"
clone "$ACCENT"   "$CACHE/accent"     && ok "clone accent-sync" || bad "accent-sync clone failed"
clone "$TITLEBAR" "$CACHE/titlebar"   && ok "clone titlebar"    || bad "titlebar clone failed"

# dotfiles: home, dconf, opencode config + skills, no hardcoded path
[ -s "$CACHE/dotfiles/home/.bashrc" ] && ok "dotfiles .bashrc" || bad "dotfiles .bashrc missing"
! grep -q '/home/emanuel' "$CACHE/dotfiles/home/.bashrc" && ok "dotfiles .bashrc without hardcoded path" \
  || bad "dotfiles .bashrc with hardcoded path"
grep -q 'export GOPATH="\$HOME/.go"' "$CACHE/dotfiles/home/.bashrc" \
  && ok "dotfiles .bashrc sets GOPATH" || bad "dotfiles .bashrc without GOPATH"
[ -s "$CACHE/dotfiles/home/.config/go/env" ] && ok "dotfiles go/env" || bad "dotfiles go/env missing"
[ -s "$CACHE/dotfiles/home/.config/environment.d/go.conf" ] && ok "dotfiles environment.d/go.conf" \
  || bad "dotfiles environment.d/go.conf missing"
[ -s "$CACHE/dotfiles/home/.config/ghostty/config" ] && ok "dotfiles ghostty" || bad "dotfiles ghostty missing"
[ -s "$CACHE/dotfiles/home/.config/zed/settings.json" ] && ok "dotfiles zed" || bad "dotfiles zed missing"
[ -s "$CACHE/dotfiles/home/.local/share/photogimp/GIMP/3.0/gimprc" ] && ok "dotfiles photogimp" || bad "dotfiles photogimp missing"
[ -s "$CACHE/dotfiles/home/.local/share/photogimp/GIMP/3.0/shortcutsrc" ] && ok "dotfiles photogimp shortcuts" || bad "dotfiles photogimp shortcuts missing"
[ -s "$CACHE/dotfiles/home/.local/share/themes/adw-inkscape/gtk-3.0/gtk.css" ] && ok "dotfiles adw-inkscape" || bad "dotfiles adw-inkscape missing"
[ -s "$CACHE/dotfiles/home/.config/inkscape/ui/style.css" ] && ok "dotfiles inkscape style.css" || bad "dotfiles inkscape style.css missing"
[ -s "$CACHE/dotfiles/home/.config/inkscape/preferences.xml" ] && ok "dotfiles inkscape preferences" || bad "dotfiles inkscape preferences missing"
! grep -q '/home/emanuel' "$CACHE/dotfiles/home/.config/inkscape/preferences.xml" \
  && ok "dotfiles inkscape preferences without hardcoded path" \
  || bad "dotfiles inkscape preferences with hardcoded path"
# Webapps (PWA): launchers + icons + WebApps folder in the overview
n_ffpwa=$(find "$CACHE/dotfiles/home/.local/share/applications" -name 'FFPWA-*.desktop' 2>/dev/null | wc -l)
[ "$n_ffpwa" -ge 10 ] && ok "dotfiles webapps FFPWA ($n_ffpwa launchers)" || bad "dotfiles webapps FFPWA ($n_ffpwa launchers)"
n_ffpwa_ico=$(find "$CACHE/dotfiles/home/.local/share/icons/hicolor" -name 'FFPWA-*.png' 2>/dev/null | wc -l)
[ "$n_ffpwa_ico" -ge 10 ] && ok "dotfiles FFPWA icons ($n_ffpwa_ico pngs)" || bad "dotfiles FFPWA icons ($n_ffpwa_ico pngs)"
grep -q 'folders/WebApps' "$CACHE/dotfiles/dconf/gnome-settings.ini" \
  && ok "dotfiles WebApps folder in dconf" || bad "dotfiles without WebApps folder in dconf"
[ -s "$CACHE/dotfiles/dconf/gnome-settings.ini" ] && ok "dotfiles dconf dump" || bad "dconf dump missing"
! grep -qiE 'password|secret|token|api_key' "$CACHE/dotfiles/dconf/gnome-settings.ini" \
  && ok "dconf without secrets" || bad "dconf may contain secrets"
python3 -c "import json;json.load(open('$CACHE/dotfiles/opencode/config/opencode.json'))" \
  && ok "dotfiles opencode.json parse" || bad "dotfiles opencode.json invalid"
! grep -q '/home/emanuel' "$CACHE/dotfiles/opencode/config/opencode.json" \
  && ok "official json without hardcoded path" || bad "official json with hardcoded path"
! grep -qE '^[[:space:]]*"(model|default_agent|agents|shell)"[[:space:]]*:' "$CACHE/dotfiles/opencode/config/opencode.json" \
  && ok "official json without model/agents/shell" || bad "official json has model/agents/shell"
grep -q '"skills"' "$CACHE/dotfiles/opencode/config/opencode.json" && ok "json with skills" || bad "skills missing in json"
grep -q '"lsp"' "$CACHE/dotfiles/opencode/config/opencode.json" && ok "json with lsp" || bad "lsp missing in json"
! grep -q 'config/opencode/skills' "$CACHE/dotfiles/opencode/config/opencode.json" \
  && ok "json points skills to ~/.agents/skills" || bad "json still points to opencode/skills"
grep -q '"context7"' "$CACHE/dotfiles/opencode/config/opencode.json" && ok "mcp context7" || bad "context7 missing"
# what must NOT exist in the dotfiles repo
for f in opencode/docs opencode/config/AGENTS.full.md \
         opencode/config/opencode.pessoal.json opencode/skills opencode/secrets; do
  [ ! -e "$CACHE/dotfiles/$f" ] && ok "not in repo: $f" || bad "$f still in dotfiles repo"
done
n_skills=$(ls "$CACHE/dotfiles/skills" 2>/dev/null | wc -l)
[ "$n_skills" -ge 184 ] && ok "skills at repo root ($n_skills >= 184)" || bad "skills ($n_skills/184)"
[ -s "$CACHE/dotfiles/opencode/plugins/memory-store.ts" ] && ok "memory-store.ts" || bad "memory-store.ts missing"
[ -s "$CACHE/dotfiles/opencode/lib/jev-client.ts" ] && ok "jev-client.ts" || bad "jev-client.ts missing (memory plugin does not load)"
[ -s "$CACHE/dotfiles/opencode/plugins/scope-guard.ts" ] && ok "scope-guard.ts" || bad "scope-guard.ts missing (no scope gate)"
[ -s "$CACHE/dotfiles/opencode/tests/scope-guard.test.ts" ] && ok "scope-guard.test.ts" || bad "scope-guard.test.ts missing"
[ -s "$CACHE/dotfiles/opencode/config/cli.json" ] && ok "cli.json" || bad "cli.json missing"
for a in core-impl core-review web-impl web-review db-impl db-review contracts-impl contracts-review; do
  [ -s "$CACHE/dotfiles/opencode/agents/$a.md" ] && ok "agent $a" || bad "agent $a missing"
done
grep -q '"permissions"' "$CACHE/dotfiles/opencode/config/opencode.json" && ok "json with permissions" || bad "permissions missing in json"
grep -q 'subagent_depth' "$CACHE/dotfiles/opencode/config/opencode.json" && ok "json with subagent_depth" || bad "subagent_depth missing in json"
grep -q 'opencode-plugin-v2' "$CACHE/dotfiles/opencode/config/opencode.json" && ok "json with omniroute plugin" || bad "omniroute plugin missing in json"
grep -q 'opencode-plugin-v2' "$CACHE/dotfiles/opencode/config/package.json" && ok "package.json with omniroute plugin" || bad "omniroute plugin missing in package.json"
[ -s "$CACHE/dotfiles/opencode/config/AGENTS.md" ] && ok "slim AGENTS.md" || bad "slim AGENTS.md missing"
[ -s "$CACHE/dotfiles/opencode/config/env.example" ] && ok "env.example" || bad "env.example missing"
[ ! -e "$CACHE/dotfiles/.env" ] && ok "no real .env in dotfiles" || bad "REAL .env in dotfiles (SECRET)"

# accent-sync: helper + units
[ -x "$CACHE/accent/accent-sync" ] && ok "accent-sync executable" || bad "accent-sync without +x bit"
grep -q 'PathChanged=%h/.config/dconf/user' "$CACHE/accent/units/accent-sync.path" \
  && ok "accent-sync.path dconf trigger" || bad "accent-sync.path without dconf trigger"
grep -q 'ExecStart=%h/.local/bin/accent-sync' "$CACHE/accent/units/accent-sync.service" \
  && ok "accent-sync.service ExecStart" || bad "accent-sync.service wrong ExecStart"

# titlebar: patch + units + compilation
python3 -m py_compile "$CACHE/titlebar/opencode-desktop-titlebar-patch" \
  && ok "py_compile of the patch (clone)" || bad "py_compile of the patch (clone)"
grep -q 'app.asar' "$CACHE/titlebar/units/opencode-titlebar-patch.path" \
  && ok "titlebar path unit" || bad "titlebar path unit"
[ "$(grep -c 'Type=oneshot' "$CACHE/titlebar/units/opencode-titlebar-patch.service")" -eq 1 ] \
  && ok "single Type service" || bad "duplicated service"
grep -q 'rpm", "-ql"' "$CACHE/titlebar/opencode-desktop-titlebar-patch" \
  && ok "patch detects rpm (Fedora)" || bad "patch without rpm detection"
[ -s "$CACHE/titlebar/pacman-hook.hook" ] && ok "pacman-hook.hook (Arch)" || bad "pacman-hook.hook missing"

# patch: applies and is idempotent on a scratch copy (real asar NEVER touched)
asar_real=$(pacman -Ql opencode-desktop-bin 2>/dev/null | grep -E 'app\.asar$' | head -1 | cut -d' ' -f2 | tr -d '\n')
if [ -n "$asar_real" ] && [ -f "$asar_real" ]; then
  tmp=$(mktemp /tmp/asar-scratch.XXXX)
  cp "$asar_real" "$tmp"
  OPENCODE_ASAR_OVERRIDE="$tmp" OPENCODE_PATCH_HOME=/tmp \
    python3 "$CACHE/titlebar/opencode-desktop-titlebar-patch" apply >/dev/null 2>&1 \
    && ok "patch apply (scratch) exit 0" || bad "patch apply failed"
  OPENCODE_ASAR_OVERRIDE="$tmp" OPENCODE_PATCH_HOME=/tmp \
    python3 "$CACHE/titlebar/opencode-desktop-titlebar-patch" --check >/dev/null 2>&1 \
    && ok "patch idempotent (--check exit 0)" || bad "patch not idempotent"
  rm -f "$tmp"
else
  echo "SKIP : real asar not found on this machine (gate skipped in isolation)"
fi
# --- 4. dconf dump: clean, no personal state or absolute paths
DC="$CACHE/dotfiles/dconf/gnome-settings.ini"
DC_CFG=$(grep -vE '^\s*(#|$)' "$DC")
python3 -c "
import configparser, sys
cp = configparser.ConfigParser(strict=False, interpolation=None)
cp.optionxform = str
cp.read('$DC', encoding='utf-8')
print('sections:', len(cp.sections()))
" >/dev/null 2>&1 && ok "dconf parse ok ($(echo "$DC_CFG" | grep -c '^\[') sections)" || bad "dconf does not parse"
echo "$DC_CFG" | grep -q '/home/' && bad "dconf has absolute path" || ok "dconf without absolute paths"
echo "$DC_CFG" | grep -qE '^\[org/gnome/portal' && bad "dconf with portal permissions" || ok "dconf without portal permissions"
# net/nokyan/Resources and io/github/seadve/Kooha are left out of the list: they are installed via Terra
echo "$DC_CFG" | grep -qE '^\[(org/gnome/(evolution|papers|weather|Weather|Showtime|Ptyxis|clocks|system|software|app-folders|Resources)|org/virt-manager)' && bad "dconf with missing app schema" || ok "dconf without missing app schemas"
echo "$DC_CFG" | grep -q 'picture-uri' && bad "dconf still pins wallpaper" || ok "dconf without pinned wallpaper"
echo "$DC_CFG" | grep -q '^favorite-apps=' && ok "dconf preserves the dock" || bad "dconf lost the dock (favorite-apps)"
echo "$DC_CFG" | grep -q "^\[org/gnome/desktop/interface\]" && ok "dconf with GNOME interface" || bad "dconf without GNOME interface"
# each enabled UUID must be in the installed extensions list
python3 - "$R" "$DC" <<'PYEOF2' && ok "dconf: enabled extensions ⊂ extensions.txt" || bad "dconf enables an extension that is not installed"
import re, sys
ext = {l.split("#")[0].strip() for l in open(sys.argv[1] + "/lists/extensions.txt", encoding="utf-8") if l.split("#")[0].strip()}
txt = open(sys.argv[2], encoding="utf-8").read()
m = re.search(r"^enabled-extensions=\[(.*?)\]", txt, re.M)
not_installed = [u for u in re.findall(r"'([^']+)'", m.group(1)) if u not in ext] if m else ["<no enabled-extensions list>"]
if not_installed:
    print("   not installed:", ", ".join(not_installed)); sys.exit(1)
PYEOF2

exit $fail
