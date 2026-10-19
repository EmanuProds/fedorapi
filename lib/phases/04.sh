# Fase 4: pacotes dnf + opencode desktop + omniroute + sunshine + ghostty + resources + runtime (rpm/appimage/sh).

mapfile -t PKGS < <(read_list "$LISTS/packages.txt")
[ "${#PKGS[@]}" -gt 0 ] || die "packages.txt vazio"

PKGS_FALTANDO=()
for p in "${PKGS[@]:-}"; do [ -z "$p" ] && continue; rpm_installed "$p" || PKGS_FALTANDO+=("$p"); done

if [ "${#PKGS_FALTANDO[@]}" -gt 0 ]; then
  mapfile -t _resolvidos < <(dnf -q repoquery --available --qf '%{name}\n' "${PKGS_FALTANDO[@]}" 2>/dev/null | sort -u)
  _ausentes=(); _instalaveis=()
  for p in "${PKGS_FALTANDO[@]}"; do
    if printf '%s\n' "${_resolvidos[@]:-}" | grep -qx "$p"; then _instalaveis+=("$p"); else _ausentes+=("$p"); fi
  done
  [ "${#_ausentes[@]}" -eq 0 ] || warn "packages.txt pede ${#_ausentes[@]} pacote(s) inexistente(s): ${_ausentes[*]}"
  if [ "${#_instalaveis[@]}" -gt 0 ]; then PKGS_FALTANDO=("${_instalaveis[@]}"); else PKGS_FALTANDO=(); fi
fi

if [ "${#PKGS_FALTANDO[@]}" -eq 0 ]; then
  ok "pacotes já instalados — pulando"
else
  run_spin "instalando ${#PKGS_FALTANDO[@]} pacote(s)" dnf install -y "${PKGS_FALTANDO[@]}"
  ok "${#PKGS_FALTANDO[@]} pacote(s) instalados"
fi

if ! rpm_installed lazydocker; then try_warn run_spin "instalando lazydocker" dnf install -y lazydocker; else ok "lazydocker já instalado — pulando"; fi

# opencode desktop
readonly OPENCODE_DESKTOP_URL="https://opencode.ai/update/api/latest/desktop/opencode/opencode-desktop-linux-x86_64.rpm"
if rpm_installed opencode; then
  ok "opencode desktop já instalado — pulando"
else
  try_warn run_spin "instalando opencode desktop" dnf install -y "$OPENCODE_DESKTOP_URL"
  if rpm_installed opencode; then ok "opencode desktop instalado"; else warn "opencode desktop não instalado"; fi
fi

# omniroute (npm global, via mise)
if omniroute_installed; then
  ok "omniroute já instalado — pulando"
else
  try_warn run_spin "instalando omniroute" as_user bash -c 'export PATH="$HOME/.local/bin:$PATH"; "$HOME/.local/bin/mise" exec -- npm i -g --allow-scripts=omniroute,keytar,onnxruntime-node,@parcel/watcher,@swc/core,protobufjs,esbuild omniroute && "$HOME/.local/bin/mise" reshim'
  if omniroute_installed; then ok "omniroute instalado"; else warn "omniroute não instalado"; fi
fi

# sunshine (config se instalado)
if ! rpm_installed Sunshine; then
  warn "Sunshine ainda não instalado (runtime .rpm pode instalá-lo)"
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

# runtime items do phases.txt (rpm/appimage/sh) — integrados aqui
while IFS='|' read -r kind name url extra; do
  case "$kind" in
    rpm)
      rpm_url=$(curl -fsSL "$url" 2>/dev/null | grep -oE '"browser_download_url": *"[^"]+"' | cut -d'"' -f4 | grep -E "$extra" | head -1 || true)
      if [ -n "$rpm_url" ]; then
        curl -fsSL "$rpm_url" -o "/tmp/$name.rpm" && dnf install -y "/tmp/$name.rpm"
        rm -f "/tmp/$name.rpm"; ok "$name: rpm instalado"
      else warn "$name: asset não achado no release"; fi
      ;;
    appimage)
      as_user mkdir -p "$SUH/.appimages"
      if curl -fsS --retry 2 "$url" -o "/tmp/$name.appimage"; then
        install -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "/tmp/$name.appimage" "$SUH/.appimages/$extra"
        ok "$name: AppImage em ~/.appimages/$extra"
      else warn "$name: download falhou"; fi
      rm -f "/tmp/$name.appimage"
      ;;
    sh)
      if curl -fsSL "$url" | bash; then ok "$name: installer rodou"
      else warn "$name: installer falhou"; fi
      ;;
  esac
done < <(grep -vE '^[[:space:]]*(#|$)' "$LISTS/phases.txt" | grep -v '|zip|')

# FirefoxPWA: runtime para webapps PWA (Firefox/Zen)
if rpm_installed firefoxpwa; then
  as_user mkdir -p "$SUH/.local/share/firefoxpwa"
  if [ ! -d "$SUH/.local/share/firefoxpwa/runtime" ]; then
    try_warn run_spin "instalando runtime do FirefoxPWA" as_user firefoxpwa runtime install
  else
    ok "FirefoxPWA: runtime já instalado — pulando"
  fi
  # Aviso para restaurar backup das sessões dos webapps
  if [ -t 0 ]; then
    printf '\n%s[FirefoxPWA]%s Restaure manualmente o backup de ~/.local/share/firefoxpwa (runtime + sites/sessões) se disponível. Pressione Enter para continuar...' "$C_BLU" "$C_OFF" >&3
    read -r _ </dev/tty 2>/dev/null || true
  fi
else
  warn "firefoxpwa não instalado — runtime não configurado"
fi