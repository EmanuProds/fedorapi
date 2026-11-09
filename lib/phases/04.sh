# Phase 4: dnf packages + opencode desktop + omniroute + sunshine + ghostty + resources + runtime (rpm/appimage/sh).

mapfile -t PKGS < <(read_list "$LISTS/packages.txt")
[ "${#PKGS[@]}" -gt 0 ] || die "packages.txt empty"

PKGS_MISSING=()
for p in "${PKGS[@]:-}"; do [ -z "$p" ] && continue; rpm_installed "$p" || PKGS_MISSING+=("$p"); done

if [ "${#PKGS_MISSING[@]}" -gt 0 ]; then
  mapfile -t _resolved < <(dnf -q repoquery --available --qf '%{name}\n' "${PKGS_MISSING[@]}" 2>/dev/null | sort -u)
  _absent=(); _installable=()
  for p in "${PKGS_MISSING[@]}"; do
    if printf '%s\n' "${_resolved[@]:-}" | grep -qx "$p"; then _installable+=("$p"); else _absent+=("$p"); fi
  done
  [ "${#_absent[@]}" -eq 0 ] || warn "packages.txt asks for ${#_absent[@]} nonexistent package(s): ${_absent[*]}"
  if [ "${#_installable[@]}" -gt 0 ]; then PKGS_MISSING=("${_installable[@]}"); else PKGS_MISSING=(); fi
fi

if [ "${#PKGS_MISSING[@]}" -eq 0 ]; then
  ok "packages already installed — skipping"
else
  run_spin "installing ${#PKGS_MISSING[@]} package(s)" dnf install -y "${PKGS_MISSING[@]}"
  ok "${#PKGS_MISSING[@]} package(s) installed"
fi

if ! rpm_installed lazydocker; then try_warn run_spin "installing lazydocker" dnf install -y lazydocker; else ok "lazydocker already installed — skipping"; fi

# Docker: make sure the user can access the socket without sudo
if getent group docker >/dev/null 2>&1; then
  if ! id -nG "$SUDO_USER" 2>/dev/null | grep -qw docker; then
    usermod -aG docker "$SUDO_USER"
    ok "docker: user $SUDO_USER added to the docker group (requires logout/login)"
  else
    ok "docker: user already in the docker group — skipping"
  fi
else
  warn "docker: group 'docker' does not exist — docker-ce not installed?"
fi

# opencode desktop
readonly OPENCODE_DESKTOP_URL="https://opencode.ai/update/api/latest/desktop/opencode/opencode-desktop-linux-x86_64.rpm"
if rpm_installed opencode; then
  ok "opencode desktop already installed — skipping"
else
  try_warn run_spin "installing opencode desktop" dnf install -y "$OPENCODE_DESKTOP_URL"
  if rpm_installed opencode; then ok "opencode desktop installed"; else warn "opencode desktop not installed"; fi
fi

# omniroute (bun global, via mise)
if omniroute_installed; then
  ok "omniroute already installed — skipping"
else
  try_warn run_spin "installing omniroute" as_user bash -c 'export PATH="$HOME/.local/bin:$PATH"; "$HOME/.local/bin/mise" exec -- bun add -g --allow-scripts=omniroute,keytar,onnxruntime-node,@parcel/watcher,@swc/core,protobufjs,esbuild omniroute && "$HOME/.local/bin/mise" reshim'
  if omniroute_installed; then ok "omniroute installed"; else warn "omniroute not installed"; fi
fi

# sunshine (config if installed)
if ! rpm_installed Sunshine; then
  warn "Sunshine not installed yet (the .rpm runtime may install it)"
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

# runtime items from phases.txt (rpm/appimage/sh) — integrated here
while IFS='|' read -r kind name url extra; do
  case "$kind" in
    rpm)
      rpm_url=$(curl -fsSL "$url" 2>/dev/null | grep -oE '"browser_download_url": *"[^"]+"' | cut -d'"' -f4 | grep -E "$extra" | head -1 || true)
      if [ -n "$rpm_url" ]; then
        curl -fsSL "$rpm_url" -o "/tmp/$name.rpm" && dnf install -y "/tmp/$name.rpm"
        rm -f "/tmp/$name.rpm"; ok "$name: rpm installed"
      else warn "$name: asset not found in the release"; fi
      ;;
    appimage)
      as_user mkdir -p "$SUH/.appimages"
      if curl -fsS --retry 2 "$url" -o "/tmp/$name.appimage"; then
        install -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "/tmp/$name.appimage" "$SUH/.appimages/$extra"
        ok "$name: AppImage at ~/.appimages/$extra"
      else warn "$name: download failed"; fi
      rm -f "/tmp/$name.appimage"
      ;;
    sh)
      if curl -fsSL "$url" | bash; then ok "$name: installer ran"
      else warn "$name: installer failed"; fi
      ;;
  esac
done < <(grep -vE '^[[:space:]]*(#|$)' "$LISTS/phases.txt" | grep -v '|zip|')

# FirefoxPWA: runtime for PWA webapps (Firefox/Zen)
if rpm_installed firefoxpwa; then
  as_user mkdir -p "$SUH/.local/share/firefoxpwa"
  if [ ! -d "$SUH/.local/share/firefoxpwa/runtime" ]; then
    try_warn run_spin "installing the FirefoxPWA runtime" as_user firefoxpwa runtime install
  else
    ok "FirefoxPWA: runtime already installed — skipping"
  fi
  # Reminder to restore the webapp sessions backup
  if [ -t 0 ]; then
    printf '\n%s[FirefoxPWA]%s Manually restore the ~/.local/share/firefoxpwa backup (runtime + sites/sessions) if available. Press Enter to continue...' "$C_BLU" "$C_OFF" >&3
    read -r _ </dev/tty 2>/dev/null || true
  fi
else
  warn "firefoxpwa not installed — runtime not configured"
fi
