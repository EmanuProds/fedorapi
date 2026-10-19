# Fase 7: serviços systemd.

_f0=$FAIL_COUNT
if ! command -v tailscale >/dev/null 2>&1; then
  try_warn dnf config-manager addrepo --overwrite --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
  try_warn dnf install -y tailscale
fi
while IFS= read -r svc; do
  [ -z "$svc" ] && continue
  if service_enabled "$svc"; then ok "$svc já habilitado — pulando"; else try_warn systemctl enable --now "$svc"; fi
done < <(read_list "$LISTS/services.txt")
phase_end "$_f0" "serviços habilitados"
