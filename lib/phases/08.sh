# Fase 8: Flathub + flatpaks.

_f0=$FAIL_COUNT
command -v flatpak >/dev/null 2>&1 || dnf install -y flatpak
try_warn flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
mapfile -t FPKS < <(read_list "$LISTS/flatpak.txt")
for app in "${FPKS[@]:-}"; do
  [ -z "$app" ] && continue
  appid="$(flatpak_appid "$app")"
  if flatpak_installed "$appid"; then ok "$appid já instalado — pulando"; continue; fi
  case "$app" in flathub/*|fedora/*|oci:*) target="$app" ;; *) target="flathub/$app" ;; esac
  try_warn run_spin "instalando $appid" flatpak install -y --system --noninteractive "$target"
done
for t in adw-gtk3 adw-gtk3-dark; do
  if flatpak_installed "org.gtk.Gtk3theme.$t"; then ok "tema flatpak $t já instalado — pulando"
  else try_warn run_spin "instalando tema $t" flatpak install -y --system --noninteractive "flathub/org.gtk.Gtk3theme.$t"; fi
done
if as_user gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | grep -q prefer-dark; then
  as_user gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
else
  as_user gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3'
fi
[ -x "$SUH/.local/bin/accent-sync" ] && try_warn as_user "$SUH/.local/bin/accent-sync"
phase_end "$_f0" "flatpaks instalados"