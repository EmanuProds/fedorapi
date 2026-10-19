# Fase 6: virtualização (virt-manager + libvirt + qemu-kvm).

if ! rpm_installed virt-manager; then
  try_warn dnf install -y virt-manager libvirt-daemon-driver-qemu libvirt-client-qemu qemu-kvm virt-install
  ok "virt-manager + libvirt + qemu-kvm instalados"
else
  ok "virt-manager já instalado — pulando"
fi