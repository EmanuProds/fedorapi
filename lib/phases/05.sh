# Fase 5: codecs e aceleração de vídeo (Radeon).

_f0=$FAIL_COUNT
if ! rpm_installed ffmpeg; then try_warn dnf swap -y ffmpeg-free ffmpeg --allowerasing; else ok "ffmpeg já instalado — pulando"; fi
if ! rpm_installed mesa-va-drivers-freeworld; then try_warn dnf install -y mesa-va-drivers-freeworld; else ok "mesa-va-drivers-freeworld já instalado — pulando"; fi
if ! rpm_installed mesa-vulkan-drivers-freeworld; then try_warn dnf swap -y mesa-vulkan-drivers mesa-vulkan-drivers-freeworld --allowerasing; else ok "mesa-vulkan-drivers-freeworld já instalado — pulando"; fi
if ! dnf group list --installed 2>/dev/null | grep -q '^multimedia'; then
  try_warn dnf group install -y multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin,libheif-freeworld
else ok "grupo multimedia já instalado — pulando"; fi
if ! rpm_installed libva-utils; then try_warn dnf install -y libva libva-utils; else ok "libva/libva-utils já instalados — pulando"; fi
if ! rpm_installed svt-av1-libs; then try_warn dnf install -y svt-av1-libs; else ok "svt-av1-libs já instalado — pulando"; fi
phase_end "$_f0" "codecs/VA-API prontos"