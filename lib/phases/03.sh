# Phase 3: mise (ready to use) + Bun (global) + Python/uv.

_f0=$FAIL_COUNT
# mise: install the binary only, ready to be used (no toolchains via mise).
as_user bash -c 'curl -fsSL https://mise.run | sh' || warn "mise.run failed"
if [ -x "$SUH/.local/bin/mise" ]; then
  ok "mise installed ($SUH/.local/bin/mise) — toolchains are managed by the user"
  ln -sfn "$SUH/.local/bin/mise" /usr/local/bin/mise 2>/dev/null || true
fi

# Bun: global install (official installer) — mandatory runtime for node/npm/etc.
if [ ! -x "$SUH/.bun/bin/bun" ]; then
  try_warn run_spin "installing bun" as_user bash -c 'curl -fsSL https://bun.sh/install | bash'
fi
if [ -x "$SUH/.bun/bin/bun" ]; then
  ln -sfn "$SUH/.bun/bin/bun" /usr/local/bin/bun 2>/dev/null || true
  ln -sfn "$SUH/.bun/bin/bunx" /usr/local/bin/bunx 2>/dev/null || true
  ok "bun installed ($SUH/.bun/bin/bun)"
else
  warn "bun not installed"
fi

# Python: system package (dnf) + uv (dnf) for global tooling.
command -v python3 >/dev/null 2>&1 && ok "python3 available ($(python3 --version))" || warn "python3 not found"
command -v uv >/dev/null 2>&1 && ok "uv available ($(uv --version))" || warn "uv not found (install via dnf)"


# shims for /usr/local/bin (mise itself, if present)
if [ -d "$SUH/.local/share/mise/shims" ]; then
  for shim in mise; do
    [ -e "$SUH/.local/share/mise/shims/$shim" ] || continue
    ln -sfn "$SUH/.local/share/mise/shims/$shim" "/usr/local/bin/$shim"
  done
  ok "mise shims exposed in /usr/local/bin"
fi

# Bun globals from npm.txt (opencode CLI, prettier, etc.) — bun is the mandatory runtime.
if [ -x "$SUH/.bun/bin/bun" ] && [ -s "$LISTS/npm.txt" ]; then
  mapfile -t BUNGS < <(read_list "$LISTS/npm.txt")
  BUNGS_MISSING=()
  for p in "${BUNGS[@]:-}"; do [ -z "$p" ] && continue; "$SUH/.bun/bin/bun" pm -g ls --depth=0 2>/dev/null | grep -q "$p@" || BUNGS_MISSING+=("$p"); done
  if [ "${#BUNGS_MISSING[@]}" -gt 0 ]; then
    try_warn run_spin "installing bun globals" as_user "$SUH/.bun/bin/bun" add -g --silent --allow-scripts=@opencode/cli "${BUNGS_MISSING[@]}"
  else
    ok "bun globals already installed — skipping"
  fi
  # OpenCode CLI ships a native binary via an optional dependency; bun does not
  # run its postinstall by default. Install the native binary package first, then
  # run the postinstall manually to link the binary into bin/opencode.
  try_warn run_spin "installing opencode native binary" as_user "$SUH/.bun/bin/bun" add -g --silent @opencode/cli-linux-x64 2>/dev/null || true
  POSTINSTALL="$SUH/.bun/install/global/node_modules/@opencode/cli/postinstall.mjs"
  if [ -f "$POSTINSTALL" ]; then
    if command -v node >/dev/null 2>&1; then
      try_warn run_spin "running opencode postinstall" as_user node "$POSTINSTALL"
    else
      try_warn run_spin "running opencode postinstall" as_user "$SUH/.bun/bin/bun" "$POSTINSTALL"
    fi
  fi
fi
phase_end "$_f0" "toolchains ready"