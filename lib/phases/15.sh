# Fase 15: GIMP PhotoGIMP (patch Photoshop-like) + config do Inkscape.

_f0=$FAIL_COUNT

# --- PhotoGIMP ---
# O payload do PhotoGIMP upstream (Diolinux/PhotoGIMP) vem em .config/GIMP/3.0/.
# O GIMP instalado usa uma pasta versionada (3.2 no Fedora atual), então o
# payload é copiado para a pasta de config detectada pelo proprio GIMP.
PG_PAYLOAD="$CLONES/dotfiles/home/.local/share/photogimp/GIMP/3.0"
if [ -d "$PG_PAYLOAD" ]; then
  # Detecta a pasta de config real do GIMP instalado (mesmo metodo do install.sh upstream).
  GIMP_CFG_DIR=$(as_user gimp --no-interface --console-messages \
    --batch-interpreter=plug-in-script-fu-eval \
    --batch '(begin (display "GIMP_CONFIG_DIR=") (display gimp-directory) (newline))' \
    --quit 2>/dev/null | sed -n 's/^GIMP_CONFIG_DIR=//p' | head -1)
  if [ -z "$GIMP_CFG_DIR" ]; then
    # Fallback: deduz do diretorio do usuario (padrao XDG do GIMP 3.x).
    GIMP_CFG_DIR="$SUH/.config/GIMP/3.2"
    warn "GIMP: nao foi possivel detectar a pasta de config, usando $GIMP_CFG_DIR"
  fi
  # Backup da config atual antes de sobrescrever.
  if [ -d "$GIMP_CFG_DIR" ]; then
    try_warn cp -a "$GIMP_CFG_DIR" "$GIMP_CFG_DIR.fedorapi-backup"
  fi
  install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$GIMP_CFG_DIR"
  cp -a "$PG_PAYLOAD/." "$GIMP_CFG_DIR/"
  chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$GIMP_CFG_DIR"
  ok "PhotoGIMP aplicado em $GIMP_CFG_DIR"
else
  warn "PhotoGIMP: payload ausente no dotfiles"
fi

# --- Inkscape ---
# style.css (ui/) e preferences.xml ja vem em home/.config/inkscape (copiado
# na fase 09). Aqui so garantimos o tema GTK adw-inkscape e a property xml.
if [ -d "$SUH/.config/inkscape/ui" ]; then
  ok "Inkscape: ui/style.css aplicado"
fi
if [ -d "$SUH/.local/share/themes/adw-inkscape" ]; then
  ok "Inkscape: tema adw-inkscape disponivel"
fi

phase_end "$_f0" "PhotoGIMP e Inkscape configurados"
