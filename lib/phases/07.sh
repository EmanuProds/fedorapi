# Fase 7: serviços systemd + dnsmasq como resolvedor local.

_f0=$FAIL_COUNT
if ! command -v tailscale >/dev/null 2>&1; then
  try_warn dnf config-manager addrepo --overwrite --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
  try_warn dnf install -y tailscale
fi
while IFS= read -r svc; do
  [ -z "$svc" ] && continue
  if service_enabled "$svc"; then ok "$svc já habilitado — pulando"; else try_warn systemctl enable --now "$svc"; fi
done < <(read_list "$LISTS/services.txt")

if rpm_installed dnsmasq; then
  warn "dnsmasq substitui o systemd-resolved: split DNS e MagicDNS (Tailscale) podem parar de funcionar"
  if [ ! -f /etc/NetworkManager/conf.d/00-use-dnsmasq.conf ]; then
    install -d -m 755 /etc/NetworkManager/conf.d
    printf '[main]\ndns=dnsmasq\n' > /etc/NetworkManager/conf.d/00-use-dnsmasq.conf
    ok "NetworkManager configurado para usar dnsmasq"
  else ok "NetworkManager já usa dnsmasq — pulando"; fi
  if [ ! -f /etc/NetworkManager/dnsmasq.d/00-fedorapi.conf ]; then
    install -d -m 755 /etc/NetworkManager/dnsmasq.d
    cat > /etc/NetworkManager/dnsmasq.d/00-fedorapi.conf <<'EOF'
no-resolv
server=1.1.1.1
server=9.9.9.9
server=8.8.8.8
cache-size=1500
EOF
    ok "dnsmasq configurado"
  else ok "dnsmasq já configurado — pulando"; fi
  if ! rpm_installed dnsmasq; then
    warn "dnsmasq não instalado — pulando"
  else
    # O dnsmasq roda como plugin do NetworkManager (dns=dnsmasq no NM),
    # não como serviço standalone. Habilitar dnsmasq.service conflita na
    # porta 53 (já ocupada pelo dnsmasq do NM). Apenas garantir que o
    # systemd-resolved não dispute a porta.
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
      systemctl stop systemd-resolved 2>/dev/null || true
      systemctl disable systemd-resolved 2>/dev/null || true
      systemctl mask systemd-resolved 2>/dev/null || true
    fi
    ok "dnsmasq gerenciado pelo NetworkManager (plugin) — sem serviço standalone"
  fi
  try_warn systemctl restart NetworkManager
  if systemctl is-active --quiet systemd-resolved; then
    try_warn systemctl disable --now systemd-resolved
    try_warn systemctl mask systemd-resolved
    ok "systemd-resolved desligado e mascarado"
  else ok "systemd-resolved já fora do caminho — pulando"; fi
  if [ "$(readlink -f /etc/resolv.conf)" != "/run/NetworkManager/resolv.conf" ]; then
    try_warn ln -sf /run/NetworkManager/resolv.conf /etc/resolv.conf
    ok "/etc/resolv.conf apontado para o NetworkManager"
  else ok "/etc/resolv.conf já aponta para o NM — pulando"; fi
  if grep -qx 'nameserver 127.0.0.1' /run/NetworkManager/resolv.conf 2>/dev/null; then ok "dnsmasq é o resolvedor do sistema"
  else warn "resolv.conf do NM não aponta para 127.0.0.1"; fi
else
  warn "dnsmasq não instalado"
fi
phase_end "$_f0" "serviços habilitados"