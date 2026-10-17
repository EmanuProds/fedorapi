# fedorapi — Fedora Post-Installation

Post-installation script that turns a fresh **Fedora 44+ Workstation** into a
reproduction of personal desktop: apps, GNOME
extensions, CachyOS kernel, accent theming pipeline and OpenCode workspace.

Designed for **dnf5** (Fedora 41+) and the current stable release.

## Layout

```
fedorapi/
├── fedoraPI.sh            # main script: 12 linear phases, NO dialog interface, set -euo pipefail
├── lists/                 # install lists (edit freely; the script reads them at run time)
│   ├── packages.txt       # every dnf-installable package (official, Terra, RPM Fusion, COPR, vendor repos)
│   ├── removals.txt       # preinstalled Fedora bloatware (`libreoffice*`, vim, gnome extras…)
│   ├── phases.txt         # non-dnf installs: gh .rpm (Sunshine, firefoxpwa), Epic AppImage, fonts zip, curl|sh
│   ├── repos.txt          # reference doc for every repo used (Terra, RPM Fusion, COPRs, docker-ce, Google)
│   ├── flatpak.txt        # flathub apps + themes/runtimes
│   ├── extensions.txt     # GNOME extension UUIDs (installed via D-Bus, no pipx)
│   ├── services.txt       # systemd units to `enable --now`
│   ├── mise.txt           # toolchain managed by mise
│   ├── npm.txt            # global npm packages (LSPs)
│   └── candidates/packages-candidates.txt  # verified source snapshot kept for audit
├── scripts/verify.sh      # oracle: 58 gates, exit != 0 on any failure
```

Dotfiles and helper scripts are **not** stored here — they are cloned at run
time from their own repos (`git clone --depth 1`), so the Fedora always gets
the published latest and there is zero duplication:

| Repo (GitHub) | What fedorapi pulls |
|---|---|
| `EmanuProds/dotfiles` | `home/` (bash, ghostty, zed, gamemode, topgrade, watermark), `dconf/gnome-settings.ini`, `skills/` (185 skills → `~/.agents/skills`), `opencode/` skeleton (config, commands, plugins, tests) |
| `EmanuProds/accent-sync` | helper + `units/accent-sync.{path,service}` |
| `EmanuProds/opencode-desktop-titlebar` | patch helper (rpm-aware) + `units/opencode-titlebar-patch.{path,service}` |

## Phases

1. **Repos** — Terra, RPM Fusion (free/nonfree), 6 COPRs (incl. CachyOS
   `bieszczaders/*`), Docker CE repo, Google Cloud SDK repo file
2. **Bloatware** — `dnf remove` of `lists/removals.txt`
3. **Packages** — one `dnf install` of `lists/packages.txt`; afterwards the
   CachyOS glue: zram swap (`cachyos-settings`), `dracut -f`, SELinux bool
   `domain_kernel_load_modules`, dnf5 `.actions` keeping the newest `cachy`
   kernel as boot default (Fedora kernel stays as backup)
4. **Graphics/codecs** — ffmpeg + mesa VA/VDPAU `freeworld` swaps, `@multimedia`
   group, `libva(-utils)` for the Radeon
5. **Services** — `systemctl enable --now` from `lists/services.txt`
6. **Flatpaks** — Flathub remote + all `flatpak.txt` apps
7. **Dotfiles** — `git clone` of `EmanuProds/dotfiles` → `$HOME` + **Plymouth**
   spinner tweaks (watermark removal + `VerticalAlignment`)
8. **dconf** — GNOME settings restore from the clone
9. **Extensions** — 19 UUIDs via D-Bus `InstallRemoteExtension` (pipx-free)
10. **Toolchains** — mise (node/bun/go/usage/pipx/gh) + npm LSPs + completions
11. **OpenCode + helpers** — skeleton → `~/.config/opencode` + `npm install`;
    `accent-sync` and titlebar patch helpers → `~/.local/bin` with their user
    units enabled (memory.db is created fresh; migrate `~/.opencode/memory.db*`
    from Arch if history is wanted)
12. **Runtime phases** — `lists/phases.txt`: GitHub-release `.rpm` (Sunshine,
    PWAsForFirefox), Epic native AppImage, JetBrains Mono Nerd zip, LinuxToys

## Kernel / CachyOS parity

`kernel-cachyos-lto` (BORE 1000 Hz, ThinLTO, NTSync, sched-ext; x86-64-v3 —
the 5500U qualifies) + `cachyos-settings`, `scx-scheds/scx-tools/scx-manager`
and `ananicy-cpp` + rules from the `bieszczaders` COPRs. The stock Fedora
kernel is kept as a rescue entry.

## Usage

```bash
git clone <your-repo> fedorapi && cd fedorapi
chmod +x fedoraPI.sh
sudo ./fedoraPI.sh
```

Full log lands in `/tmp/fedorapi.log`.

## Validation

```bash
bash scripts/verify.sh   # 58 gates; exit != 0 on any drift
```

## Secrets

`opencode/env.example` holds placeholder keys. Copy it to
`~/.config/opencode/.env` on Fedora and fill real values. **Never commit
real keys** — the oracle fails the run if a real `.env` or `node_modules/`
leaks into the repo.

## License

MIT — Emanuel Pereira
