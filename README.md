# fedorapi — Fedora Post-Installation

Post-installation script that turns a fresh **Fedora 44+ Workstation** into a
reproduction of a personal desktop: apps, GNOME extensions, CachyOS kernel,
accent theming pipeline and OpenCode workspace.

Designed for **dnf5** (Fedora 41+) and the current stable release.

## Layout

```
fedorapi/
├── fedoraPI.sh            # executor: sources lib/, prompts per phase
├── lib/
│   ├── common.sh          # helpers, logging, idempotency, ask_phase
│   └── phases/            # one file per phase (01-repos.sh … 13-runtime.sh)
├── lists/                 # install lists (edit freely; read at run time)
└── scripts/verify.sh      # oracle: gates, exit != 0 on any failure
```

Dotfiles and helper scripts are **not** stored here — cloned at run time from
their own repos, so Fedora always gets the published latest.

## Usage

```bash
git clone <your-repo> fedorapi && cd fedorapi
chmod +x install.sh
sudo ./install.sh
```

The script is interactive: before each of the 14 phases it asks whether to run
it (10s timeout, auto-yes). Full log lands in `/tmp/fedorapi.log`.

## Validation

```bash
bash scripts/verify.sh   # exit != 0 on any drift
```

## License

MIT — Emanuel Pereira