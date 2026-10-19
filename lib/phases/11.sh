# Fase 11: extensões GNOME via D-Bus.

_f0=$FAIL_COUNT
EXT_DIR="$SUH/.local/share/gnome-shell/extensions"
mapfile -t EXT_UUIDS < <(read_list "$LISTS/extensions.txt")
for uuid in "${EXT_UUIDS[@]:-}"; do
  [ -z "$uuid" ] && continue
  [ -d "$EXT_DIR/$uuid" ] && continue
  as_user dbus-send --session --print-reply --dest=org.gnome.Shell.Extensions /org/gnome/Shell/Extensions org.gnome.Shell.Extensions.InstallRemoteExtension string:"$uuid" >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do [ -d "$EXT_DIR/$uuid" ] && break; sleep 1; done
  if [ ! -d "$EXT_DIR/$uuid" ]; then mark_fail; warn "extensão não instalou: $uuid"; fi
done
phase_end "$_f0" "extensões do GNOME instaladas"