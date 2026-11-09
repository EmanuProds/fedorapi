# Phase 15: GIMP PhotoGIMP (Photoshop-like patch) + Inkscape config.

_f0=$FAIL_COUNT

# --- PhotoGIMP ---
# The upstream PhotoGIMP payload (Diolinux/PhotoGIMP) ships in .config/GIMP/3.0/.
# The installed GIMP uses a versioned folder (3.2 on current Fedora), so the
# payload is copied into the config folder detected by GIMP itself.
PG_PAYLOAD="$CLONES/dotfiles/home/.local/share/photogimp/GIMP/3.0"
if [ -d "$PG_PAYLOAD" ]; then
  # Detect the real config folder of the installed GIMP (same method as the upstream install.sh).
  GIMP_CFG_DIR=$(as_user gimp --no-interface --console-messages \
    --batch-interpreter=plug-in-script-fu-eval \
    --batch '(begin (display "GIMP_CONFIG_DIR=") (display gimp-directory) (newline))' \
    --quit 2>/dev/null | sed -n 's/^GIMP_CONFIG_DIR=//p' | head -1)
  if [ -z "$GIMP_CFG_DIR" ]; then
    # Fallback: infer from the user directory (GIMP 3.x XDG default).
    GIMP_CFG_DIR="$SUH/.config/GIMP/3.2"
    warn "GIMP: could not detect the config folder, using $GIMP_CFG_DIR"
  fi
  # Back up the current config before overwriting.
  if [ -d "$GIMP_CFG_DIR" ]; then
    try_warn cp -a "$GIMP_CFG_DIR" "$GIMP_CFG_DIR.fedorapi-backup"
  fi
  install -d -m 755 -o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")" "$GIMP_CFG_DIR"
  cp -a "$PG_PAYLOAD/." "$GIMP_CFG_DIR/"
  chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$GIMP_CFG_DIR"
  ok "PhotoGIMP applied to $GIMP_CFG_DIR"
else
  warn "PhotoGIMP: payload missing in dotfiles"
fi

# --- Inkscape ---
# style.css (ui/) and preferences.xml already come in home/.config/inkscape (copied
# in phase 09). Here we only ensure the adw-inkscape GTK theme and the xml property.
if [ -d "$SUH/.config/inkscape/ui" ]; then
  ok "Inkscape: ui/style.css applied"
fi
if [ -d "$SUH/.local/share/themes/adw-inkscape" ]; then
  ok "Inkscape: adw-inkscape theme available"
fi

phase_end "$_f0" "PhotoGIMP and Inkscape configured"
