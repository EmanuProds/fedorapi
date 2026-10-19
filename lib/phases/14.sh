# Fase 14: tuning (kernel cola + split-lock + lockdown + BBR3 + min_free + shader + ananicy + wifi + snapper + grub-btrfs + secure boot + fwupd).

_f0=$FAIL_COUNT

# cola do kernel cachy (movida de packages)
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
if [ -n "$kdef" ]; then try_warn grubby --set-default="/boot/$kdef"; ok "kernel default: $kdef"; else warn "nenhum kernel cachy em /boot"; fi

# split-lock
if grubby --info=ALL 2>/dev/null | grep -q 'split_lock_detect=off'; then
  ok "split_lock_detect=off já aplicado — pulando"
else
  try_warn grubby --update-kernel=ALL --args="split_lock_detect=off"
  ok "split_lock_detect=off aplicado"
fi

# lockdown
if [ -e /sys/kernel/security/lockdown ]; then
  if grep -qw 'integrity' /sys/kernel/security/lockdown 2>/dev/null; then ok "lockdown=integrity já ativo — pulando"
  elif grubby --info=ALL 2>/dev/null | grep -qw 'lockdown=integrity'; then ok "lockdown=integrity no cmdline — pulando"
  else try_warn grubby --update-kernel=ALL --args="lockdown=integrity"; ok "lockdown=integrity aplicado"; fi
  warn "lockdown bloqueia módulos unsigned, kexec, perf e bpf"
else
  warn "sem /sys/kernel/security/lockdown"
fi

# suspend-to-idle
if grep -qw 'suspend_latency_idle=1' /proc/cmdline 2>/dev/null; then
  ok "suspend-to-idle já aplicado — pulando"
else
  try_warn grubby --update-kernel=ALL --args="suspend_latency_idle=1"
  ok "suspend-to-idle ativado"
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
if [ "$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)" = "bbr3" ]; then ok "BBR3 ativo + MTU probing ligado"
else warn "BBR3 não ficou como congestion control"; fi

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
Description=Define vm.min_free_kbytes como 1% da RAM total
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
if [ "${_min_free_kb:-0}" -gt 0 ] 2>/dev/null; then ok "min_free_kbytes = 1% da RAM (${_min_free_kb} kB)"
else warn "não foi possível ler a RAM"; fi

# shader cache
if grep -q 'MESA_SHADER_CACHE_MAX_SIZE' /etc/environment 2>/dev/null; then
  ok "cache de shader já configurado — pulando"
else
  grep -q '^AMD_VULKAN_ICD=' /etc/environment 2>/dev/null || printf 'AMD_VULKAN_ICD=RADV\n' >> /etc/environment
  grep -q '^MESA_SHADER_CACHE_MAX_SIZE=' /etc/environment 2>/dev/null || printf 'MESA_SHADER_CACHE_MAX_SIZE=12G\n' >> /etc/environment
  ok "cache de shader AMD ampliado para 12G"
fi

# ananicy
if rpm_installed ananicy-cpp; then
  if [ -d /etc/ananicy.d/00-default ]; then ok "ananicy-cpp com regras do CachyOS ativas"
  else warn "ananicy-cpp instalado mas sem regras"; fi
else warn "ananicy-cpp não instalado"; fi

# wifi
if lspci 2>/dev/null | grep -qiE '10ec:c8(22|2f)'; then
  lsmod | grep -q '^rtw88_8822ce' || try_warn modprobe rtw88_8822ce
  if lsmod | grep -q '^rtw88_8822ce'; then ok "WiFi Realtek 8822CE: driver nativo carregado"
  else warn "WiFi 8822CE detectado mas o driver não carregou"; fi
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
  ok "snapper: teto de 5, timeline desligado"
else
  warn "sem /etc/snapper/configs/root"
fi

# hook dnf5
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
  logger -t snapper-dnf-hook "aviso: cleanup number falhou"
  return 1
}
case "${1:-}" in
  pre)
    if out=$(snap_call org.opensuse.Snapper.CreatePreSnapshot "$CFG" "dnf: antes da transação" number "{}"); then
      num=$(snapshot_number "$out"); [ -n "$num" ] && printf '%s' "$num" > "$PRE_FILE"
      logger -t snapper-dnf-hook "pre-snapshot #$num criado"
    else logger -t snapper-dnf-hook "falha ao criar pre-snapshot"; fi ;;
  post)
    num=$(cat "$PRE_FILE" 2>/dev/null); [ -n "$num" ] || exit 0
    if out=$(snap_call org.opensuse.Snapper.CreatePostSnapshot "$CFG" "$num" "dnf: depois da transação" number "{}"); then
      post=$(snapshot_number "$out"); logger -t snapper-dnf-hook "post-snapshot #$post criado"
      rm -f "$PRE_FILE"; run_cleanup
    else logger -t snapper-dnf-hook "falha ao criar post-snapshot"; rm -f "$PRE_FILE"; fi ;;
esac
exit 0
HOOKEOF
chmod 755 /usr/local/bin/snapper-dnf-hook.sh
cat > /etc/dnf/libdnf5-plugins/actions.d/10-snapper.actions <<'ACTIONSEOF'
pre_transaction:*:::/usr/local/bin/snapper-dnf-hook.sh pre
post_transaction:*:::/usr/local/bin/snapper-dnf-hook.sh post
ACTIONSEOF
if [ -x /usr/local/bin/snapper-dnf-hook.sh ] && [ -f /etc/dnf/libdnf5-plugins/actions.d/10-snapper.actions ]; then
  ok "hook de snapshot do dnf5 instalado"
else
  warn "hook de snapshot do dnf5 incompleto"
fi

# grub-btrfs
if ! rpm_installed grub-btrfs; then
  try_warn dnf copr enable -y kylegospo/grub-btrfs
  try_warn dnf install -y grub-btrfs
fi
if rpm_installed grub-btrfs; then
  if ! snapper list-configs 2>/dev/null | grep -q '^root'; then
    try_warn snapper create-config /
    ok "config 'root' do snapper criada"
  else ok "config 'root' do snapper já existe — pulando"; fi
  if [ "$(snapper -c root list 2>/dev/null | grep -E 'single|pre|post' | grep -vc current)" -lt 1 ]; then
    try_warn snapper -c root create --description "baseline fedoraPI.sh" --cleanup-algorithm number
    ok "snapshot baseline criado"
  else ok "snapshots do snapper já existem — pulando"; fi
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
    ok "grub-btrfs.path corrigido"
  else ok "grub-btrfs.path já corrigido — pulando"; fi
  try_warn systemctl enable --now grub-btrfs.path
  if try_warn cp -a /boot/grub2/grub.cfg "/boot/grub2/grub.cfg.bak-$(date +%Y%m%d-%H%M%S)"; then
    try_warn grub2-mkconfig -o /boot/grub2/grub.cfg
  fi
  if grep -q "submenu 'Fedora Linux snapshots'" /boot/grub2/grub.cfg 2>/dev/null; then ok "submenu de snapshots no GRUB"
  else warn "grub.cfg sem submenu de snapshots"; fi
  if grub2-editenv list 2>/dev/null | grep -q '^menu_auto_hide='; then
    try_warn grub2-editenv - unset menu_auto_hide
    ok "menu_auto_hide removido"
  else ok "menu do GRUB já visível — pulando"; fi
else
  warn "grub-btrfs não instalado"
fi

# Secure Boot: pula se já está habilitado.
_sb_status=$(sbctl status 2>/dev/null | grep -E '^Secure Boot' || true)
if printf '%s' "$_sb_status" | grep -q '✓'; then
  ok "Secure Boot já habilitado — fase pulada"
else
  if ! command -v sbctl >/dev/null 2>&1; then
    try_warn dnf copr enable -y chenxiaolong/sbctl
    try_warn dnf install -y sbctl
  fi
  if command -v sbctl >/dev/null 2>&1; then
    if [ ! -f /var/lib/sbctl/keys/db/db.pem ]; then
      try_warn sbctl create-keys
      ok "chaves do Secure Boot criadas"
    else ok "chaves do Secure Boot já existem — pulando"; fi
    if [ -d /sys/firmware/efi/efivars ]; then
      if sbctl_keys_enrolled; then
        ok "chaves PK/KEK/db confirmadas no firmware"
      else
        if _out=$(sbctl enroll-keys 2>&1); then ok "chaves enrolled nas variáveis EFI"
        else
          if printf '%s' "$_out" | grep -q "not in Setup Mode"; then warn "Setup Mode desligado com chaves de outro dono"
          elif printf '%s' "$_out" | grep -qi "immutable"; then warn "variáveis EFI imutáveis"
          else warn "sbctl enroll-keys falhou: ${_out}"; fi
        fi
        sbctl_keys_enrolled && ok "chaves confirmadas após cadastro" || true
      fi
    else
      warn "sem efivars — máquina não está em UEFI"
    fi
    for f in /boot/vmlinuz-*; do [ -f "$f" ] || continue; try_warn sbctl sign -s "$f"; done
    for f in /boot/efi/EFI/*/*.efi /boot/efi/EFI/*/*.EFI /boot/efi/EFI/BOOT/*.efi; do [ -f "$f" ] || continue; try_warn sbctl sign -s "$f"; done
    unsigned=$(sbctl verify 2>/dev/null | grep -c 'not signed' || true)
    if [ "${unsigned:-0}" -eq 0 ]; then ok "cadeia de boot inteira assinada"
    else warn "$unsigned arquivo(s) da ESP sem assinatura"; fi
    sb_line=$(sbctl status 2>/dev/null | grep -E '^Secure Boot' | head -1 || true)
    ok "Secure Boot: $(printf '%s' "${sb_line:-estado desconhecido}" | tr -s '\t' ' ' | sed 's/^Secure Boot: *//')"
    if ! printf '%s' "$sb_line" | grep -q '✓'; then
      warn "Secure Boot continua DESLIGADO (chaves prontas, faltou o interruptor na BIOS)"
      if sbctl_has_option_rom; then warn "há Option ROM em hardware PCI"
      else ok "nenhum dispositivo PCI com Option ROM"; fi
    fi
  else
    warn "sbctl não instalado"
  fi
fi

# fwupd
if command -v fwupdmgr >/dev/null 2>&1; then
  if _fw_json=$(fwupdmgr security --json 2>/dev/null) && [ -n "$_fw_json" ]; then
    _fw_txt=$(printf '%s' "$_fw_json" | python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
sai = []
for a in d.get("SecurityAttributes", []):
    r, ok = str(a.get("HsiResult","")), str(a.get("HsiResultSuccess",""))
    if r and ok and r != ok:
        sai.append(f"  - {a.get(chr(78)+chr(97)+chr(109)+chr(101))}: {r} (precisa: {ok})")
print("\n".join(sai))
' 2>/dev/null)
    if [ -n "$_fw_txt" ]; then
      ok "fwupd HSI: itens que ainda falham (firmware/hardware):"
      printf '%s\n' "$_fw_txt"
    else
      ok "fwupd HSI: nenhum teste falhando"
    fi
  else
    warn "fwupdmgr security --json não retornou nada"
  fi
else
  ok "fwupd não instalado"
fi
phase_end "$_f0" "tuning de kernel aplicado"