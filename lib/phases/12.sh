# Fase 12: customization (OpenCode + helpers + Plymouth + fonts).

# Plymouth tweak
SPINNER_CONF="/usr/share/plymouth/themes/spinner/spinner.plymouth"
if [ -f "$SPINNER_CONF" ] && grep -q '\[two-step\]' "$SPINNER_CONF"; then
  try_warn rm -f /usr/share/plymouth/themes/spinner/watermark.png
  grep -q '^VerticalAlignment=.5$' "$SPINNER_CONF" || try_warn sed -i 's/^VerticalAlignment=.7$/VerticalAlignment=.5/' "$SPINNER_CONF"
  try_warn sed -i 's/^HorizontalAlignment=.7$/HorizontalAlignment=.5/' "$SPINNER_CONF"
  try_warn plymouth-set-default-theme spinner
  try_warn plymouth-set-default-theme -R spinner
  ok "plymouth spinner centralizado e ativado"
else
  warn "spinner.plymouth sem seção [two-step] — tweak ignorado"
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
run_spin "instalando dependências do opencode" as_user "$SUH/.local/bin/mise" exec -- npm install --silent --prefix "$SUH/.config/opencode" || warn "npm opencode parcial"

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
    ok "adwaita-colors instalado"
  fi
else
  ok "adwaita-colors já instalado — pulando"
fi

install -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$CLONES/accent-sync/accent-sync" "$SUH/.local/bin/accent-sync"
install -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$CLONES/titlebar/opencode-desktop-titlebar-patch" "$SUH/.local/bin/opencode-desktop-titlebar-patch"
install -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" /dev/stdin "$SUH/.local/bin/opencode-desktop-titlebar-patch-wrapper" <<'EOF'
#!/usr/bin/env bash
export PATH="/home/emanuel/.local/share/mise/installs/node/lts/bin:$PATH"
exec /home/emanuel/.local/bin/opencode-desktop-titlebar-patch "$@"
EOF
install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$SUH/.config/systemd/user"
install -m 644 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$CLONES/accent-sync/units/"* "$SUH/.config/systemd/user/"
as_user systemctl --user daemon-reload || true
try_warn as_user systemctl --user enable --now accent-sync.path

try_warn tee /etc/systemd/system/opencode-titlebar-patch.service >/dev/null <<'EOF'
[Unit]
Description=Reaplica o patch de title bar do OpenCode Desktop
After=network-online.target

[Service]
Type=oneshot
ExecStart=%h/.local/bin/opencode-desktop-titlebar-patch-wrapper
RemainAfterExit=no
EOF
try_warn tee /etc/systemd/system/opencode-titlebar-patch.path >/dev/null <<'EOF'
[Unit]
Description=Dispara o patch quando o app.asar do OpenCode Desktop muda

[Path]
PathChanged=/opt/OpenCode/resources/app.asar
Unit=opencode-titlebar-patch.service

[Install]
WantedBy=multi-user.target
EOF
try_warn systemctl daemon-reload
try_warn systemctl enable --now opencode-titlebar-patch.path
if sudo "$SUH/.local/bin/opencode-desktop-titlebar-patch-wrapper" --check >/dev/null 2>&1; then
  ok "titlebar patch aplicado e serviço ativo"
else
  warn "titlebar patch não aplicado — rodará no próximo upgrade"
fi

# omniroute unit (se não criada)
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
  try_warn as_user systemctl --user enable omniroute.service
  ok "omniroute: unit criada e habilitada"
fi

# sunshine config (se instalado)
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
sunshine_password = TROQUE_ESTA_SENHA
upnp = disabled
pkey = /etc/sunshine/sunshine.pem
log_path = /var/log/sunshine.log
EOF
    chmod 600 /etc/sunshine/sunshine.conf
    ok "sunshine: config criada (ajuste a senha!)"
  else
    ok "sunshine: config já existe — pulando"
  fi
fi

# ghostty terminal padrão
if command_exists ghostty; then
  GHOSTTY_DESKTOP=/usr/share/applications/com.mitchellh.ghostty.desktop
  if [ -f "$GHOSTTY_DESKTOP" ] && rpm_installed alternatives; then
    if try_warn update-alternatives --install /usr/bin/zzz-c x-terminal-emulator "$GHOSTTY_DESKTOP" 40; then
      ok "x-terminal-emulator -> ghostty"
    else
      warn "update-alternatives não registrou o ghostty"
    fi
  fi
  if [ -f /usr/share/applications/org.gnome.Terminal.desktop ]; then
    sed -i '/^NoDisplay=/d' /usr/share/applications/org.gnome.Terminal.desktop 2>/dev/null || true
    printf 'NoDisplay=true\n' >> /usr/share/applications/org.gnome.Terminal.desktop
  fi
  ok "ghostty: terminal padrão configurado"
else
  warn "ghostty não está no PATH"
fi

# resources launchers ocultos
if rpm_installed resources; then
  for orig in /usr/share/applications/net.nokyan.Resources.Devel.desktop /usr/share/applications/org.gnome.SystemMonitor.desktop; do
    [ -f "$orig" ] || continue
    sed -i '/^NoDisplay=/d' "$orig" 2>/dev/null || true
    printf 'NoDisplay=true\n' >> "$orig"
  done
  ok "resources: launchers originais ocultos"
else
  warn "resources não instalado"
fi

# fonts (JetBrains Mono) do phases.txt (tipo zip)
while IFS='|' read -r kind name url extra; do
  [ "$kind" = "zip" ] || continue
  curl -fsSL "$url" -o "/tmp/$name.zip"
  install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$SUH/.local/share/fonts"
  as_user unzip -oq "/tmp/$name.zip" -d "$SUH/.local/share/fonts/"
  try_warn as_user fc-cache -f
  try_warn as_user gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 11'
  rm -f "/tmp/$name.zip"; ok "$name: zip aplicado"
done < <(grep -vE '^[[:space:]]*(#|$)' "$LISTS/phases.txt")

# markdown-oxide LSP (Rust, binário do GitHub)
if [ ! -x "$SUH/.local/bin/markdown-oxide" ]; then
  _md_url=$(curl -s "https://api.github.com/repos/Feel-ix-343/markdown-oxide/releases/latest" | python3 -c "import json,sys; d=json.load(sys.stdin); print([a['browser_download_url'] for a in d.get('assets',[]) if a['name'].endswith('x86_64-unknown-linux-gnu') and not a['name'].endswith('.tar.gz')][0])" 2>/dev/null)
  try_warn run_spin "baixando markdown-oxide" curl -fsSL "$_md_url" -o "$SUH/.local/bin/markdown-oxide"
  chmod +x "$SUH/.local/bin/markdown-oxide" 2>/dev/null || true
  chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.local/bin/markdown-oxide" 2>/dev/null || true
  if [ -x "$SUH/.local/bin/markdown-oxide" ]; then ok "markdown-oxide instalado"; else warn "markdown-oxide não instalado"; fi
else
  ok "markdown-oxide já instalado — pulando"
fi

# Atualiza cache de ícones (flatpak hicolor + tema ativo) para evitar ícones
# quebrados/genéricos no GNOME Shell após instalar flatpaks/temas.
if [ -d /var/lib/flatpak/exports/share/icons/hicolor ]; then
  try_warn gtk-update-icon-cache -f /var/lib/flatpak/exports/share/icons/hicolor
fi
ACTIVE_THEME=$(as_user gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
if [ -n "$ACTIVE_THEME" ] && [ -d "$SUH/.local/share/icons/$ACTIVE_THEME" ]; then
  try_warn gtk-update-icon-cache -f "$SUH/.local/share/icons/$ACTIVE_THEME"
fi
ok "customization concluída"