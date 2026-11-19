# Phase 12: customization (OpenCode + helpers + Plymouth + fonts).

# Ensure Topgrade updates OpenCode Desktop via the RPM updater (in-app updater
# is broken on Fedora). Patch the user topgrade.toml installed from dotfiles.
_TG="$SUH/.config/topgrade.toml"
if [ -f "$_TG" ] && ! grep -q 'opencode-desktop-update' "$_TG"; then
  sed -i '/^\[commands\]/a "OpenCode Desktop" = "opencode-desktop-update"' "$_TG"
  chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$_TG"
  ok "topgrade: OpenCode Desktop custom command added"
fi


# Go: GOPATH/GOMODCACHE in ~/.go (global go from dnf).
if command -v go >/dev/null 2>&1; then
  as_user mkdir -p "$SUH/.go" "$SUH/.go/bin" "$SUH/.config/go" "$SUH/.config/environment.d"
  if [ -d "$SUH/go" ]; then
    as_user bash -c 'shopt -s dotglob nullglob; for f in "$HOME/go"/*; do [ -e "$f" ] && mv -f "$f" "$HOME/.go/"; done; rmdir "$HOME/go" 2>/dev/null || true'
  fi
  try_warn as_user go env -w GOPATH="$SUH/.go" GOMODCACHE="$SUH/.go/pkg/mod"
  cat > "$SUH/.config/environment.d/go.conf" <<EOF
# Go workspace in ~/.go (instead of the default ~/go)
GOPATH=$SUH/.go
GOMODCACHE=$SUH/.go/pkg/mod
BASH_ENV=$SUH/.bashrc
PATH=$SUH/.go/bin:\${PATH}
EOF
  chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.config/environment.d/go.conf"
  printf 'GOMODCACHE=%s/.go/pkg/mod\nGOPATH=%s/.go\n' "$SUH" "$SUH" > "$SUH/.config/go/env"
  chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.config/go/env"
  ok "Go: GOPATH configured in ~/.go"
fi

# Plymouth tweak
SPINNER_CONF="/usr/share/plymouth/themes/spinner/spinner.plymouth"
if [ -f "$SPINNER_CONF" ] && grep -q '\[two-step\]' "$SPINNER_CONF"; then
  try_warn rm -f /usr/share/plymouth/themes/spinner/watermark.png
  grep -q '^VerticalAlignment=.5$' "$SPINNER_CONF" || try_warn sed -i 's/^VerticalAlignment=.7$/VerticalAlignment=.5/' "$SPINNER_CONF"
  try_warn sed -i 's/^HorizontalAlignment=.7$/HorizontalAlignment=.5/' "$SPINNER_CONF"
  try_warn plymouth-set-default-theme spinner
  try_warn plymouth-set-default-theme -R spinner
  ok "plymouth spinner centered and enabled"
else
  warn "spinner.plymouth without a [two-step] section — tweak skipped"
fi

# OpenCode skeleton
for d in agents commands lib plugins tests; do
  [ -d "$CLONES/dotfiles/opencode/$d" ] && cp -a "$CLONES/dotfiles/opencode/$d" "$SUH/.config/opencode/"
done
for f in opencode.json cli.json AGENTS.md env.example package.json; do
  install -m 644 "$CLONES/dotfiles/opencode/config/$f" "$SUH/.config/opencode/$f"
done
install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$SUH/.agents"
install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$SUH/.agents/skills"
cp -a "$CLONES/dotfiles/skills/." "$SUH/.agents/skills/"
chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.config" "$SUH/.agents"
run_spin "installing opencode dependencies" as_user bash -c 'export PATH="$HOME/.bun/bin:$PATH"; cd "$HOME/.config/opencode" && bun install --silent' || warn "opencode bun install partial"

# accent-sync + titlebar helpers
clone_repo "$ACCENT_SYNC_REPO" "$CLONES/accent-sync"
clone_repo "$TITLEBAR_REPO" "$CLONES/titlebar"

needs_ac=0
if [ ! -d "$SUH/.local/share/icons/Adwaita-blue" ] && [ ! -d "/usr/share/icons/Adwaita-blue" ]; then needs_ac=1
elif ! grep -q 'MoreWaita' "$SUH/.local/share/icons/Adwaita-teal/index.theme" 2>/dev/null; then needs_ac=1; fi
if [ "$needs_ac" -eq 1 ]; then
  clone_repo "https://github.com/dpejoh/Adwaita-colors" "$CLONES/adwaita-colors"
  if [ -x "$CLONES/adwaita-colors/setup" ]; then
    try_warn "$CLONES/adwaita-colors/setup" -i -f
    [ -x "$CLONES/adwaita-colors/morewaita.sh" ] && try_warn bash "$CLONES/adwaita-colors/morewaita.sh"
    try_warn gtk-update-icon-cache -f "$SUH/.local/share/icons/Adwaita-teal"
    ok "adwaita-colors installed"
  fi
else
  ok "adwaita-colors already installed — skipping"
fi

install -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$CLONES/accent-sync/accent-sync" "$SUH/.local/bin/accent-sync"

# gtk-theme-sync (auto adwaita colors + icon-theme following accent)
clone_repo "https://github.com/EmanuProds/gtk-theme-sync.git" "$CLONES/gtk-theme-sync"
if [ -f "$CLONES/gtk-theme-sync/gtk_theme_sync.py" ]; then
  install -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$CLONES/gtk-theme-sync/gtk_theme_sync.py" "$SUH/.local/bin/gtk-theme-sync"
  install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$SUH/.config/systemd/user"
  install -m 644 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$CLONES/gtk-theme-sync/units/gtk-theme-sync.service" "$SUH/.config/systemd/user/"
  as_user systemctl --user daemon-reload || true
  try_warn as_user systemctl --user enable --now gtk-theme-sync.service
  ok "gtk-theme-sync installed and enabled"
fi
install -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$CLONES/titlebar/opencode-desktop-titlebar-patch" "$SUH/.local/bin/opencode-desktop-titlebar-patch"
install -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" /dev/stdin "$SUH/.local/bin/opencode-desktop-titlebar-patch-wrapper" <<EOF
#!/usr/bin/env bash
export PATH="$SUH/.local/bin:\$PATH"
exec "$SUH/.local/bin/opencode-desktop-titlebar-patch" "\$@"
EOF
install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$SUH/.config/systemd/user"
install -m 644 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$CLONES/accent-sync/units/"* "$SUH/.config/systemd/user/"
as_user systemctl --user daemon-reload || true
try_warn as_user systemctl --user enable --now accent-sync.path

try_warn tee /etc/systemd/system/opencode-titlebar-patch.service >/dev/null <<'EOF'
[Unit]
Description=Reapplies the OpenCode Desktop title bar patch
After=network-online.target

[Service]
Type=oneshot
ExecStart=%h/.local/bin/opencode-desktop-titlebar-patch-wrapper
RemainAfterExit=no
EOF
try_warn tee /etc/systemd/system/opencode-titlebar-patch.path >/dev/null <<'EOF'
[Unit]
Description=Triggers the patch when the OpenCode Desktop app.asar changes

[Path]
PathChanged=/opt/OpenCode/resources/app.asar
Unit=opencode-titlebar-patch.service

[Install]
WantedBy=multi-user.target
EOF
try_warn systemctl daemon-reload
try_warn systemctl enable --now opencode-titlebar-patch.path
if sudo "$SUH/.local/bin/opencode-desktop-titlebar-patch-wrapper" --check >/dev/null 2>&1; then
  ok "titlebar patch applied and service active"
else
  warn "titlebar patch not applied — it will run on the next upgrade"
fi

# omniroute unit (if not created / or outdated path)
if [ ! -f "$SUH/.config/systemd/user/omniroute.service" ] || grep -q 'mise/shims/omniroute' "$SUH/.config/systemd/user/omniroute.service"; then
  cat > "$SUH/.config/systemd/user/omniroute.service" <<'EOF'
[Unit]
Description=OmniRoute (local AI gateway)
After=network-online.target

[Service]
Type=simple
ExecStart=%h/.bun/bin/omniroute
Environment=PORT=20128
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
  chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.config/systemd/user/omniroute.service"
  as_user systemctl --user daemon-reload || true
  try_warn as_user systemctl --user enable omniroute.service
  ok "omniroute: unit created/updated and enabled"
fi

# sunshine config (if installed)
if rpm_installed Sunshine; then
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
  if [ -f /usr/share/applications/dev.lizardbyte.app.Sunshine.desktop ]; then
    sed -i '/^NoDisplay=/d' /usr/share/applications/dev.lizardbyte.app.Sunshine.desktop 2>/dev/null || true
    printf 'NoDisplay=true\n' >> /usr/share/applications/dev.lizardbyte.app.Sunshine.desktop
  fi
  if [ ! -f /etc/sunshine/sunshine.conf ]; then
    install -d -m 755 /etc/sunshine
    cat > /etc/sunshine/sunshine.conf <<'EOF'
port = 47989
address = 0.0.0.0
sunshine_username = eumanu
sunshine_password = CHANGE_THIS_PASSWORD
upnp = disabled
pkey = /etc/sunshine/sunshine.pem
log_path = /var/log/sunshine.log
EOF
    chmod 600 /etc/sunshine/sunshine.conf
    ok "sunshine: config created (change the password!)"
  else
    ok "sunshine: config already exists — skipping"
  fi
fi

# ghostty default terminal
if command_exists ghostty; then
  GHOSTTY_DESKTOP=/usr/share/applications/com.mitchellh.ghostty.desktop
  if [ -f "$GHOSTTY_DESKTOP" ] && rpm_installed alternatives; then
    if try_warn update-alternatives --install /usr/bin/zzz-c x-terminal-emulator "$GHOSTTY_DESKTOP" 40; then
      ok "x-terminal-emulator -> ghostty"
    else
      warn "update-alternatives did not register ghostty"
    fi
  fi
  if [ -f /usr/share/applications/org.gnome.Terminal.desktop ]; then
    sed -i '/^NoDisplay=/d' /usr/share/applications/org.gnome.Terminal.desktop 2>/dev/null || true
    printf 'NoDisplay=true\n' >> /usr/share/applications/org.gnome.Terminal.desktop
  fi
  ok "ghostty: default terminal configured"
else
  warn "ghostty is not in PATH"
fi

# resources hidden launchers
if rpm_installed resources; then
  for orig in /usr/share/applications/net.nokyan.Resources.Devel.desktop /usr/share/applications/org.gnome.SystemMonitor.desktop; do
    [ -f "$orig" ] || continue
    sed -i '/^NoDisplay=/d' "$orig" 2>/dev/null || true
    printf 'NoDisplay=true\n' >> "$orig"
  done
  ok "resources: original launchers hidden"
else
  warn "resources not installed"
fi

# fonts (JetBrains Mono) from phases.txt (type zip)
while IFS='|' read -r kind name url extra; do
  [ "$kind" = "zip" ] || continue
  curl -fsSL "$url" -o "/tmp/$name.zip"
  install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$SUH/.local/share/fonts"
  as_user unzip -oq "/tmp/$name.zip" -d "$SUH/.local/share/fonts/"
  try_warn as_user fc-cache -f
  try_warn as_user gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 11'
  rm -f "/tmp/$name.zip"; ok "$name: zip applied"
done < <(grep -vE '^[[:space:]]*(#|$)' "$LISTS/phases.txt")

# markdown-oxide LSP (Rust, GitHub binary)
if [ ! -x "$SUH/.local/bin/markdown-oxide" ]; then
  _md_url=$(curl -s "https://api.github.com/repos/Feel-ix-343/markdown-oxide/releases/latest" | python3 -c "import json,sys; d=json.load(sys.stdin); print([a['browser_download_url'] for a in d.get('assets',[]) if a['name'].endswith('x86_64-unknown-linux-gnu') and not a['name'].endswith('.tar.gz')][0])" 2>/dev/null)
  try_warn run_spin "downloading markdown-oxide" curl -fsSL "$_md_url" -o "$SUH/.local/bin/markdown-oxide"
  chmod +x "$SUH/.local/bin/markdown-oxide" 2>/dev/null || true
  chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.local/bin/markdown-oxide" 2>/dev/null || true
  if [ -x "$SUH/.local/bin/markdown-oxide" ]; then ok "markdown-oxide installed"; else warn "markdown-oxide not installed"; fi
else
  ok "markdown-oxide already installed — skipping"
fi

# Refresh the icon cache (flatpak hicolor + active theme) to avoid broken/generic
# icons in GNOME Shell after installing flatpaks/themes.
if [ -d /var/lib/flatpak/exports/share/icons/hicolor ]; then
  try_warn gtk-update-icon-cache -f /var/lib/flatpak/exports/share/icons/hicolor
fi
ACTIVE_THEME=$(as_user gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
if [ -n "$ACTIVE_THEME" ] && [ -d "$SUH/.local/share/icons/$ACTIVE_THEME" ]; then
  try_warn gtk-update-icon-cache -f "$SUH/.local/share/icons/$ACTIVE_THEME"
fi
ok "customization complete"
