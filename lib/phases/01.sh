# Fase 1: repos de terceiros (Terra, RPM Fusion, COPRs, Docker CE).

if [ -d /var/lib/dnf/offline/packages ] && [ -n "$(ls -A /var/lib/dnf/offline/packages 2>/dev/null)" ]; then
  try_warn dnf5 offline clean
fi

if grep -q '^max_parallel_downloads=15' /etc/dnf/dnf.conf 2>/dev/null && grep -q '^fastestmirror=True' /etc/dnf/dnf.conf 2>/dev/null; then
  ok "dnf: tuning já aplicado — pulando"
else
  for kv in max_parallel_downloads=15 max_downloads_per_mirror=15 fastestmirror=True; do
    try_warn dnf config-manager setopt "$kv"
  done
  ok "dnf: tuning aplicado"
fi

if rpm -q terra-release >/dev/null 2>&1; then
  ok "terra-release já instalado — pulando"
else
  dnf install -y --nogpgcheck --repofrompath "terra,https://repos.fyralabs.com/terra$FDC" terra-release terra-gpg-keys
fi

rpm -q rpmfusion-free-release >/dev/null 2>&1 || dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$FDC.noarch.rpm"
rpm -q rpmfusion-nonfree-release >/dev/null 2>&1 || dnf install -y "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$FDC.noarch.rpm"

for copr in sneexy/zen-browser rivenirvana/morewaita-icon-theme chronoscrat/starship atim/resources atim/lazydocker bieszczaders/kernel-cachyos-lto bieszczaders/kernel-cachyos-addons; do
  repo_file="/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:${copr/\//\:}.repo"
  [ -f "$repo_file" ] && continue
  try_warn dnf --setopt=retries=20 copr enable -y "$copr" >/dev/null 2>&1
done

[ -f /etc/yum.repos.d/docker-ce.repo ] || try_warn dnf config-manager addrepo --overwrite --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo >/dev/null 2>&1
ok "repos prontos"