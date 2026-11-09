# Phase 13: LSPs (bun) + gopls.

_f0=$FAIL_COUNT
mapfile -t NPMG < <(read_list "$LISTS/npm.txt")
NPMG_MISSING=()
for p in "${NPMG[@]:-}"; do [ -z "$p" ] && continue; npm_global_installed "$p" || NPMG_MISSING+=("$p"); done
if [ "${#NPMG[@]}" -gt 0 ] && [ "${#NPMG_MISSING[@]}" -eq 0 ]; then
  ok "bun LSPs already installed — skipping"
elif [ "${#NPMG_MISSING[@]}" -gt 0 ]; then
  try_warn run_spin "installing bun LSPs" as_user "$SUH/.local/bin/mise" exec -- bun add -g --silent "${NPMG_MISSING[@]}"
  as_user "$SUH/.local/bin/mise" reshim
fi
if as_user "$SUH/.local/bin/mise" exec -- go version >/dev/null 2>&1; then
  if gopls_installed; then ok "gopls already installed — skipping"
  else try_warn run_spin "installing gopls" as_user "$SUH/.local/bin/mise" exec -- go install golang.org/x/tools/gopls@latest; fi
  # sqls (SQL LSP in Go)
  if [ ! -x "$SUH/.local/share/mise/installs/go/"*/bin/sqls ] && ! command -v sqls >/dev/null 2>&1; then
    try_warn run_spin "installing sqls" as_user "$SUH/.local/bin/mise" exec -- go install github.com/sqls-server/sqls@latest
  else
    ok "sqls already installed — skipping"
  fi
fi
# ty (Python LSP in Rust, Astral)
if command -v pipx >/dev/null 2>&1 || [ -x "$SUH/.local/bin/pipx" ]; then
  if ! command -v ty >/dev/null 2>&1 && [ ! -x "$SUH/.local/bin/ty" ]; then
    try_warn run_spin "installing ty" as_user "$SUH/.local/bin/mise" exec -- pipx install ty
  else
    ok "ty already installed — skipping"
  fi
else
  warn "pipx not available — ty not installed"
fi
try_warn as_user bash -c 'mkdir -p "$HOME/.local/share/bash-completion/completions" && mise completion bash --include-bash-completion-lib > "$HOME/.local/share/bash-completion/completions/mise"'
phase_end "$_f0" "LSPs ready"
