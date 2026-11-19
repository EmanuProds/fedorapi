# Phase 6: virtualization (virt-manager + libvirt + qemu-kvm) + VM networking/firewall fix.

_f0=$FAIL_COUNT

# --- 6.1: install virt-manager + libvirt + qemu-kvm ---
if ! rpm_installed virt-manager; then
  try_warn dnf install -y virt-manager libvirt-daemon-driver-qemu libvirt-client-qemu qemu-kvm virt-install
  ok "virt-manager + libvirt + qemu-kvm installed"
else
  ok "virt-manager already installed — skipping"
fi

# --- 6.1b: add the running user to the libvirt group (no password prompt) ---
# Without this, virt-manager asks for an admin password on every launch.
if id -nG "$SUDO_USER" 2>/dev/null | grep -qw libvirt; then
  ok "$SUDO_USER already in the libvirt group — skipping"
else
  try_warn usermod -aG libvirt "$SUDO_USER"
  ok "$SUDO_USER added to the libvirt group (re-login required)"
fi

# --- 6.2: firewalld masquerade for the libvirt zone (NAT for VMs) ---
# Without masquerade, VMs get an IP but cannot reach the internet.
if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
  if firewall-cmd --zone=libvirt --query-masquerade >/dev/null 2>&1; then
    ok "firewalld: libvirt zone masquerade already enabled"
  else
    try_warn firewall-cmd --zone=libvirt --add-masquerade
    try_warn firewall-cmd --zone=libvirt --add-masquerade --permanent
    ok "firewalld: libvirt zone masquerade enabled"
  fi
else
  warn "firewalld not active — skipping masquerade (enable firewalld first)"
fi

# --- 6.3: allow forwarding for virbr0 around Docker/Tailscale ip-filter rules ---
# Docker and Tailscale install an `ip filter` table (priority 0) with
# FORWARD policy=drop, which silently drops virbr0 traffic before firewalld
# (priority filter+10) can masquerade it. Add ACCEPT rules in DOCKER-USER when
# available, otherwise directly in FORWARD.
if iptables -L DOCKER-USER -n >/dev/null 2>&1; then
  if iptables -C DOCKER-USER -i virbr0 -j ACCEPT >/dev/null 2>&1; then
    ok "iptables: DOCKER-USER virbr0 (in) rule already present"
  else
    try_warn iptables -I DOCKER-USER -i virbr0 -j ACCEPT
    ok "iptables: DOCKER-USER virbr0 (in) rule added"
  fi
  if iptables -C DOCKER-USER -o virbr0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT >/dev/null 2>&1; then
    ok "iptables: DOCKER-USER virbr0 (out) rule already present"
  else
    try_warn iptables -I DOCKER-USER -o virbr0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ok "iptables: DOCKER-USER virbr0 (out) rule added"
  fi
else
  # No Docker: Tailscale (or another) may still own the ip-filter FORWARD chain.
  if iptables -L FORWARD -n >/dev/null 2>&1; then
    if iptables -C FORWARD -i virbr0 -j ACCEPT >/dev/null 2>&1; then
      ok "iptables: FORWARD virbr0 (in) rule already present"
    else
      try_warn iptables -I FORWARD -i virbr0 -j ACCEPT
      ok "iptables: FORWARD virbr0 (in) rule added"
    fi
    if iptables -C FORWARD -o virbr0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT >/dev/null 2>&1; then
      ok "iptables: FORWARD virbr0 (out) rule already present"
    else
      try_warn iptables -I FORWARD -o virbr0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      ok "iptables: FORWARD virbr0 (out) rule added"
    fi
  else
    warn "no iptables FORWARD chain found — skipping (no firewall filtering active)"
  fi
fi

# --- 6.4: persistent systemd unit to re-apply the forwarding rules on boot ---
_UNIT=/etc/systemd/system/libvirt-vm-forward.service
if [ ! -f "$_UNIT" ]; then
  cat > "$_UNIT" <<'UNITEOF'
[Unit]
Description=Allow forwarding for libvirt virtual networks (virbr0) around Docker/Tailscale rules
After=docker.service libvirtd.service tailscaled.service
Wants=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c "if iptables -L DOCKER-USER -n >/dev/null 2>&1; then iptables -C DOCKER-USER -i virbr0 -j ACCEPT 2>/dev/null || iptables -I DOCKER-USER -i virbr0 -j ACCEPT; else iptables -C FORWARD -i virbr0 -j ACCEPT 2>/dev/null || iptables -I FORWARD -i virbr0 -j ACCEPT; fi"
ExecStart=/bin/sh -c "if iptables -L DOCKER-USER -n >/dev/null 2>&1; then iptables -C DOCKER-USER -o virbr0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || iptables -I DOCKER-USER -o virbr0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT; else iptables -C FORWARD -o virbr0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || iptables -I FORWARD -o virbr0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT; fi"

[Install]
WantedBy=multi-user.target
UNITEOF
  try_warn systemctl daemon-reload
  ok "libvirt-vm-forward.service unit created"
else
  ok "libvirt-vm-forward.service already exists — skipping creation"
fi
if service_enabled libvirt-vm-forward.service; then
  ok "libvirt-vm-forward.service already enabled"
else
  try_warn systemctl enable --now libvirt-vm-forward.service
fi

# --- 6.5: libvirt default network: add upstream DNS forwarders ---
# libvirt's dnsmasq otherwise has no upstream resolver -> VMs get no DNS.
_NET_XML=/etc/libvirt/qemu/networks/default.xml
if [ -f "$_NET_XML" ]; then
  if grep -q "<forwarder" "$_NET_XML" 2>/dev/null; then
    ok "libvirt default network already has DNS forwarders — skipping"
  else
    python3 - "$_NET_XML" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
if "<dns>" not in s:
    anchor = "<mac address='52:54:00:b9:1d:e1'/>"
    dns = anchor + "\n  <dns>\n    <forwarder addr='8.8.8.8'/>\n    <forwarder addr='1.1.1.1'/>\n  </dns>"
    s = s.replace(anchor, dns, 1)
    open(p, "w").write(s)
PYEOF
    ok "libvirt default network: DNS forwarders 8.8.8.8/1.1.1.1 added (persistent)"
  fi
  # Apply to the running network if active (best effort, non-fatal).
  if virsh net-info default 2>/dev/null | grep -q "Active:.*yes"; then
    # Restarting the network briefly drops VMs; only do it if no VM is running.
    if [ -z "$(virsh list --state-running --name 2>/dev/null)" ]; then
      try_warn virsh net-destroy default
      try_warn virsh net-start default
      ok "libvirt default network restarted to apply DNS forwarders"
    else
      warn "VMs are running — DNS forwarders will apply on next network restart"
    fi
  fi
else
  warn "libvirt default network XML not found — skipping DNS forwarder fix"
fi

phase_end "$_f0" "virtualization + VM networking/firewall configured"
