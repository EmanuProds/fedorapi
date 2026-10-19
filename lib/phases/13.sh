# Fase 13: LSPs (npm) + gopls.

_f0=$FAIL_COUNT
mapfile -t NPMG < <(read_list "$LISTS/npm.txt")
NPMG_FALTANDO=()
for p in "${NPMG[@]:-}"; do [ -z "$p" ] && continue; npm_global_installed "$p" || NPMG_FALTANDO+=("$p"); done
if [ "${#NPMG[@]}" -gt 0 ] && [ "${#NPMG_FALTANDO[@]}" -eq 0 ]; then
  ok "LSPs npm já instalados — pulando"
elif [ "${#NPMG_FALTANDO[@]}" -gt 0 ]; then
  try_warn run_spin "instalando LSPs npm" as_user "$SUH/.local/bin/mise" exec -- npm i -g --silent "${NPMG_FALTANDO[@]}"
fi
if as_user "$SUH/.local/bin/mise" exec -- go version >/dev/null 2>&1; then
  if gopls_installed; then ok "gopls já instalado — pulando"
  else try_warn run_spin "instalando gopls" as_user "$SUH/.local/bin/mise" exec -- go install golang.org/x/tools/gopls@latest; fi
  # sqls (LSP de SQL em Go)
  if [ ! -x "$SUH/.local/share/mise/installs/go/"*/bin/sqls ] && ! command -v sqls >/dev/null 2>&1; then
    try_warn run_spin "instalando sqls" as_user "$SUH/.local/bin/mise" exec -- go install github.com/sqls-server/sqls@latest
  else
    ok "sqls já instalado — pulando"
  fi
fi
# ty (LSP de Python em Rust, Astral)
if command -v pipx >/dev/null 2>&1 || [ -x "$SUH/.local/bin/pipx" ]; then
  if ! command -v ty >/dev/null 2>&1 && [ ! -x "$SUH/.local/bin/ty" ]; then
    try_warn run_spin "instalando ty" as_user "$SUH/.local/bin/mise" exec -- pipx install ty
  else
    ok "ty já instalado — pulando"
  fi
else
  warn "pipx não disponível — ty não instalado"
fi
try_warn as_user bash -c 'mkdir -p "$HOME/.local/share/bash-completion/completions" && mise completion bash --include-bash-completion-lib > "$HOME/.local/share/bash-completion/completions/mise"'
phase_end "$_f0" "LSPs prontos"