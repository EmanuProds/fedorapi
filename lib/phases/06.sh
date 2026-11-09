# Phase 6: virtualization (virt-manager + libvirt + qemu-kvm).

if ! rpm_installed virt-manager; then
  try_warn dnf install -y virt-manager libvirt-daemon-driver-qemu libvirt-client-qemu qemu-kvm virt-install
  ok "virt-manager + libvirt + qemu-kvm installed"
else
  ok "virt-manager already installed — skipping"
fi
