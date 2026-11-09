# Phase 9: dotfiles (clone of the repo).

clone_repo "$DOTFILES_REPO" "$CLONES/dotfiles"
install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$SUH/.config"
for f in .bashrc .shell_aliases; do
  install -m 644 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$CLONES/dotfiles/home/$f" "$SUH/$f"
done
install -m 644 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$CLONES/dotfiles/home/gdm/watermark.png" "$SUH/.config/watermark.png"
cp -a "$CLONES/dotfiles/home/.config/." "$SUH/.config/"
if [ -d "$CLONES/dotfiles/home/.local/share/applications" ]; then
  install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$SUH/.local/share/applications"
  cp -a "$CLONES/dotfiles/home/.local/share/applications/." "$SUH/.local/share/applications/"
  chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.local/share/applications"
  try_warn update-desktop-database "$SUH/.local/share/applications"
fi
# Custom (hicolor) icons from dotfiles
if [ -d "$CLONES/dotfiles/home/.local/share/icons" ]; then
  install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$SUH/.local/share/icons"
  cp -a "$CLONES/dotfiles/home/.local/share/icons/." "$SUH/.local/share/icons/"
  chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.local/share/icons"
  try_warn gtk-update-icon-cache -f "$SUH/.local/share/icons/hicolor"
fi
# Custom GTK themes (adw-inkscape etc.)
if [ -d "$CLONES/dotfiles/home/.local/share/themes" ]; then
  install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$SUH/.local/share/themes"
  cp -a "$CLONES/dotfiles/home/.local/share/themes/." "$SUH/.local/share/themes/"
  chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.local/share/themes"
  ok "GTK themes from dotfiles installed"
fi
chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.config" "$SUH/.bashrc" "$SUH/.shell_aliases" 2>/dev/null || true
if ! grep -q 'starship init bash' "$SUH/.bashrc" 2>/dev/null; then
  printf '\ncommand -v starship >/dev/null 2>&1 && eval "$(starship init bash)"\n' >> "$SUH/.bashrc"
  chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.bashrc"
fi
# Go: ensure the GOPATH block in ~/.go is in place before the interactive return
# (robustness in case the published dotfiles still lack the config).
if ! grep -q 'export GOPATH="\$HOME/.go"' "$SUH/.bashrc" 2>/dev/null; then
  python3 - "$SUH/.bashrc" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
block = '''# Go: GOPATH/GOMODCACHE in ~/.go (not the default ~/go).
export GOPATH="$HOME/.go"
export GOMODCACHE="$GOPATH/pkg/mod"
export BASH_ENV="$HOME/.bashrc"
case ":$PATH:" in
    *":$GOPATH/bin:"*) ;;
    *) export PATH="$GOPATH/bin:$PATH" ;;
esac

'''
marker = '[[ $- != *i* ]] && return'
if marker in s:
    s = s.replace(marker, block + marker, 1)
else:
    s = block + s
open(p, 'w').write(s)
PY
  chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.bashrc"
fi
if ! grep -q '^BASH_ENV=' /etc/environment 2>/dev/null; then
  printf 'BASH_ENV=%s/.bashrc\n' "$SUH" >> /etc/environment
  ok "BASH_ENV configured"
fi
if [ -d "$SUH/.local/share/mise/shims" ]; then
  for shim in npm node bun bunx gh go pipx omniroute; do
    [ -e "$SUH/.local/share/mise/shims/$shim" ] || continue
    ln -sfn "$SUH/.local/share/mise/shims/$shim" "/usr/local/bin/$shim"
  done
  ok "mise shims exposed in /usr/local/bin"
fi
if [ -f /usr/lib/systemd/user/ssh-agent.socket ]; then
  try_warn as_user systemctl --user enable ssh-agent.socket
  ok "ssh-agent: socket enabled"
else
  warn "ssh-agent.socket not found"
fi
ok "dotfiles in place"
