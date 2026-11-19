# Phase 13: tuning (cachy kernel glue + split-lock + lockdown + BBR3 + min_free + shader + ananicy + wifi + snapper + grub-btrfs + secure boot + fwupd).

_f0=$FAIL_COUNT

# cachy kernel glue (moved out of packages)
if ! rpm -q cachyos-settings >/dev/null 2>&1; then
  if rpm -q zram-generator-defaults >/dev/null 2>&1; then try_warn dnf swap -y zram-generator-defaults cachyos-settings
  else try_warn dnf install -y cachyos-settings; fi
fi
try_warn dracut -f
try_warn setsebool -P domain_kernel_load_modules on
mkdir -p /etc/dnf/libdnf5-plugins/actions.d
cat > /etc/dnf/libdnf5-plugins/actions.d/cachy-default.actions <<'EOF'
post_transaction:kernel*:in::/usr/bin/sh -c /usr/bin/grubby\ --set-default=/boot/$(ls\ /boot\ |\ grep\ vmlinuz.*cachy\ |\ sort\ -V\ |\ tail\ -1)
EOF
kdef=$(ls /boot 2>/dev/null | grep 'vmlinuz.*cachy' | sort -V | tail -1 || true)
if [ -n "$kdef" ]; then try_warn grubby --set-default="/boot/$kdef"; ok "default kernel: $kdef"; else warn "no cachy kernel in /boot"; fi

# split-lock
if grubby --info=ALL 2>/dev/null | grep -q 'split_lock_detect=off'; then
  ok "split_lock_detect=off already applied — skipping"
else
  try_warn grubby --update-kernel=ALL --args="split_lock_detect=off"
  ok "split_lock_detect=off applied"
fi

# lockdown
if [ -e /sys/kernel/security/lockdown ]; then
  if grep -qw 'integrity' /sys/kernel/security/lockdown 2>/dev/null; then ok "lockdown=integrity already active — skipping"
  elif grubby --info=ALL 2>/dev/null | grep -qw 'lockdown=integrity'; then ok "lockdown=integrity in cmdline — skipping"
  else try_warn grubby --update-kernel=ALL --args="lockdown=integrity"; ok "lockdown=integrity applied"; fi
  warn "lockdown blocks unsigned modules, kexec, perf and bpf"
else
  warn "no /sys/kernel/security/lockdown"
fi

# suspend-to-idle
if grep -qw 'suspend_latency_idle=1' /proc/cmdline 2>/dev/null; then
  ok "suspend-to-idle already applied — skipping"
else
  try_warn grubby --update-kernel=ALL --args="suspend_latency_idle=1"
  ok "suspend-to-idle enabled"
fi

# BBR3
install -d -m 755 /etc/sysctl.d
cat > /etc/sysctl.d/90-fedorapi-tuning.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr3
net.ipv4.tcp_mtu_probing = 1
EOF
modprobe tcp_bbr3 2>/dev/null || true
try_warn sysctl --system
if [ "$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)" = "bbr3" ]; then ok "BBR3 active + MTU probing on"
else warn "BBR3 did not stick as congestion control"; fi

# min_free_kbytes
cat > /usr/local/bin/set-min-free-mem.sh <<'EOF'
#!/bin/sh
set -e
kbytes=$(awk '/MemTotal/ {printf "%.0f", $2 * 0.01}' /proc/meminfo)
sysctl -w "vm.min_free_kbytes=$kbytes"
EOF
chmod 755 /usr/local/bin/set-min-free-mem.sh
if [ ! -f /etc/systemd/system/set-min-free-mem.service ]; then
  cat > /etc/systemd/system/set-min-free-mem.service <<'EOF'
[Unit]
Description=Sets vm.min_free_kbytes to 1% of total RAM
DefaultDependencies=no
After=local-fs.target
Before=sysinit.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/set-min-free-mem.sh

[Install]
WantedBy=sysinit.target
EOF
  try_warn systemctl daemon-reload
  try_warn systemctl enable set-min-free-mem.service
fi
try_warn systemctl restart set-min-free-mem.service
_min_free_kb=$(awk '/MemTotal/ {printf "%.0f", $2 * 0.01}' /proc/meminfo)
if [ "${_min_free_kb:-0}" -gt 0 ] 2>/dev/null; then ok "min_free_kbytes = 1% of RAM (${_min_free_kb} kB)"
else warn "could not read RAM"; fi

# shader cache
if grep -q 'MESA_SHADER_CACHE_MAX_SIZE' /etc/environment 2>/dev/null; then
  ok "shader cache already configured — skipping"
else
  grep -q '^AMD_VULKAN_ICD=' /etc/environment 2>/dev/null || printf 'AMD_VULKAN_ICD=RADV\n' >> /etc/environment
  grep -q '^MESA_SHADER_CACHE_MAX_SIZE=' /etc/environment 2>/dev/null || printf 'MESA_SHADER_CACHE_MAX_SIZE=12G\n' >> /etc/environment
  ok "AMD shader cache enlarged to 12G"
fi

# ananicy
if rpm_installed ananicy-cpp; then
  if [ -d /etc/ananicy.d/00-default ]; then ok "ananicy-cpp with CachyOS rules active"
  else warn "ananicy-cpp installed but without rules"; fi
else warn "ananicy-cpp not installed"; fi

# wifi
if lspci 2>/dev/null | grep -qiE '10ec:c8(22|2f)'; then
  lsmod | grep -q '^rtw88_8822ce' || try_warn modprobe rtw88_8822ce
  if lsmod | grep -q '^rtw88_8822ce'; then ok "WiFi Realtek 8822CE: native driver loaded"
  else warn "WiFi 8822CE detected but the driver did not load"; fi
fi

# snapper
SNAPPER_CFG=/etc/snapper/configs/root
if [ -f "$SNAPPER_CFG" ]; then
  set_snapper_kv NUMBER_LIMIT 5
  set_snapper_kv NUMBER_LIMIT_IMPORTANT 5
  set_snapper_kv NUMBER_MIN_AGE 300
  set_snapper_kv TIMELINE_CREATE no
  set_snapper_kv TIMELINE_CLEANUP no
  for k in TIMELINE_LIMIT_HOURLY TIMELINE_LIMIT_DAILY TIMELINE_LIMIT_WEEKLY TIMELINE_LIMIT_MONTHLY TIMELINE_LIMIT_QUARTERLY TIMELINE_LIMIT_YEARLY; do set_snapper_kv "$k" 0; done
  set_snapper_kv EMPTY_PRE_POST_CLEANUP yes
  set_snapper_kv EMPTY_PRE_POST_MIN_AGE 0
  set_snapper_kv NUMBER_CLEANUP yes
  ok "snapper: cap of 5, timeline off"
else
  warn "no /etc/snapper/configs/root"
fi

# dnf5 hook
cat > /usr/local/bin/snapper-dnf-hook.sh <<'HOOKEOF'
#!/bin/bash
set -u
CFG="${SNAPPER_CONFIG:-root}"
STATE_DIR=/run/snapper-dnf-hook
PRE_FILE="$STATE_DIR/pre-number"
mkdir -p "$STATE_DIR"
snap_call() { gdbus call --system --dest org.opensuse.Snapper --object-path /org/opensuse/Snapper --method "$@"; }
snapshot_number() { printf '%s' "$1" | sed -n 's/.*uint32 \([0-9]\+\).*/\1/p'; }
run_cleanup() {
  local n
  for n in 1 2 3; do snapper -c "$CFG" cleanup number 2>&1 && return 0; sleep 1; done
  logger -t snapper-dnf-hook "warning: cleanup number failed"
  return 1
}
case "${1:-}" in
  pre)
    if out=$(snap_call org.opensuse.Snapper.CreatePreSnapshot "$CFG" "dnf: before transaction" number "{}"); then
      num=$(snapshot_number "$out"); [ -n "$num" ] && printf '%s' "$num" > "$PRE_FILE"
      logger -t snapper-dnf-hook "pre-snapshot #$num created"
    else logger -t snapper-dnf-hook "failed to create pre-snapshot"; fi ;;
  post)
    num=$(cat "$PRE_FILE" 2>/dev/null); [ -n "$num" ] || exit 0
    if out=$(snap_call org.opensuse.Snapper.CreatePostSnapshot "$CFG" "$num" "dnf: after transaction" number "{}"); then
      post=$(snapshot_number "$out"); logger -t snapper-dnf-hook "post-snapshot #$post created"
      rm -f "$PRE_FILE"; run_cleanup
    else logger -t snapper-dnf-hook "failed to create post-snapshot"; rm -f "$PRE_FILE"; fi ;;
esac
exit 0
HOOKEOF
chmod 755 /usr/local/bin/snapper-dnf-hook.sh
cat > /etc/dnf/libdnf5-plugins/actions.d/10-snapper.actions <<'ACTIONSEOF'
pre_transaction:*:::/usr/local/bin/snapper-dnf-hook.sh pre
post_transaction:*:::/usr/local/bin/snapper-dnf-hook.sh post
ACTIONSEOF
if [ -x /usr/local/bin/snapper-dnf-hook.sh ] && [ -f /etc/dnf/libdnf5-plugins/actions.d/10-snapper.actions ]; then
  ok "dnf5 snapshot hook installed"
else
  warn "dnf5 snapshot hook incomplete"
fi

# grub-btrfs
if ! rpm_installed grub-btrfs; then
  try_warn dnf copr enable -y kylegospo/grub-btrfs
  try_warn dnf install -y grub-btrfs
fi
if rpm_installed grub-btrfs; then
  if ! snapper list-configs 2>/dev/null | grep -q '^root'; then
    try_warn snapper create-config /
    ok "snapper 'root' config created"
  else ok "snapper 'root' config already exists — skipping"; fi
  if [ "$(snapper -c root list 2>/dev/null | grep -E 'single|pre|post' | grep -vc current)" -lt 1 ]; then
    try_warn snapper -c root create --description "baseline install.sh" --cleanup-algorithm number
    ok "baseline snapshot created"
  else ok "snapper snapshots already exist — skipping"; fi
  if [ ! -f /etc/systemd/system/grub-btrfs.path ]; then
    cat > /etc/systemd/system/grub-btrfs.path <<'EOF'
[Unit]
Description=Monitors for new btrfs snapshots
DefaultDependencies=no

[Path]
PathModified=/.snapshots
Unit=grub-btrfs.service

[Install]
WantedBy=multi-user.target
EOF
    try_warn systemctl daemon-reload
    ok "grub-btrfs.path fixed"
  else ok "grub-btrfs.path already fixed — skipping"; fi
  try_warn systemctl enable --now grub-btrfs.path
  if try_warn cp -a /boot/grub2/grub.cfg "/boot/grub2/grub.cfg.bak-$(date +%Y%m%d-%H%M%S)"; then
    try_warn grub2-mkconfig -o /boot/grub2/grub.cfg
  fi
  if grep -q "submenu 'Fedora Linux snapshots'" /boot/grub2/grub.cfg 2>/dev/null; then ok "snapshots submenu in GRUB"
  else warn "grub.cfg without snapshots submenu"; fi
  # Keep menu_auto_hide=1 (Fedora default: menu hidden, appears with SHIFT/F8)
  if ! grub2-editenv list 2>/dev/null | grep -q '^menu_auto_hide=1'; then
    try_warn grub2-editenv - set menu_auto_hide=1
    try_warn grub2-mkconfig -o /boot/grub2/grub.cfg
    ok "menu_auto_hide=1 enabled (Fedora default)"
  else ok "menu_auto_hide=1 already active — skipping"; fi
else
  warn "grub-btrfs not installed"
fi

# Secure Boot: skip if already enabled.
_sb_status=$(sbctl status 2>/dev/null | grep -E '^Secure Boot' || true)
if printf '%s' "$_sb_status" | grep -q '✓'; then
  ok "Secure Boot already enabled — phase skipped"
else
  if ! command -v sbctl >/dev/null 2>&1; then
    try_warn dnf copr enable -y chenxiaolong/sbctl
    try_warn dnf install -y sbctl
  fi
  if command -v sbctl >/dev/null 2>&1; then
    if [ ! -f /var/lib/sbctl/keys/db/db.pem ]; then
      try_warn sbctl create-keys
      ok "Secure Boot keys created"
    else ok "Secure Boot keys already exist — skipping"; fi
    if [ -d /sys/firmware/efi/efivars ]; then
      if sbctl_keys_enrolled; then
        ok "PK/KEK/db keys confirmed in firmware"
      else
        if _out=$(sbctl enroll-keys 2>&1); then ok "keys enrolled in EFI variables"
        else
          if printf '%s' "$_out" | grep -q "not in Setup Mode"; then warn "Setup Mode off with keys owned by someone else"
          elif printf '%s' "$_out" | grep -qi "immutable"; then warn "EFI variables are immutable"
          else warn "sbctl enroll-keys failed: ${_out}"; fi
        fi
        sbctl_keys_enrolled && ok "keys confirmed after enrollment" || true
      fi
    else
      warn "no efivars — machine is not on UEFI"
    fi
    for f in /boot/vmlinuz-*; do [ -f "$f" ] || continue; try_warn sbctl sign -s "$f"; done
    for f in /boot/efi/EFI/*/*.efi /boot/efi/EFI/*/*.EFI /boot/efi/EFI/BOOT/*.efi; do [ -f "$f" ] || continue; try_warn sbctl sign -s "$f"; done
    unsigned=$(sbctl verify 2>/dev/null | grep -c 'not signed' || true)
    if [ "${unsigned:-0}" -eq 0 ]; then ok "entire boot chain signed"
    else warn "$unsigned ESP file(s) unsigned"; fi
    sb_line=$(sbctl status 2>/dev/null | grep -E '^Secure Boot' | head -1 || true)
    ok "Secure Boot: $(printf '%s' "${sb_line:-unknown state}" | tr -s '\t' ' ' | sed 's/^Secure Boot: *//')"
    if ! printf '%s' "$sb_line" | grep -q '✓'; then
      warn "Secure Boot is still OFF (keys ready, the BIOS switch was not flipped)"
      if sbctl_has_option_rom; then warn "there is an Option ROM on PCI hardware"
      else ok "no PCI device with an Option ROM"; fi
    fi
  else
    warn "sbctl not installed"
  fi
fi

# fwupd
if command -v fwupdmgr >/dev/null 2>&1; then
  if _fw_json=$(fwupdmgr security --json 2>/dev/null) && [ -n "$_fw_json" ]; then
    _fw_txt=$(printf '%s' "$_fw_json" | python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
failing = []
for a in d.get("SecurityAttributes", []):
    r, ok = str(a.get("HsiResult","")), str(a.get("HsiResultSuccess",""))
    if r and ok and r != ok:
        failing.append(f"  - {a.get(chr(78)+chr(97)+chr(109)+chr(101))}: {r} (needs: {ok})")
print("\n".join(failing))
' 2>/dev/null)
    if [ -n "$_fw_txt" ]; then
      ok "fwupd HSI: items still failing (firmware/hardware):"
      printf '%s\n' "$_fw_txt"
    else
      ok "fwupd HSI: no failing tests"
    fi
  else
    warn "fwupdmgr security --json returned nothing"
  fi
else
  ok "fwupd not installed"
fi
phase_end "$_f0" "kernel tuning applied"
