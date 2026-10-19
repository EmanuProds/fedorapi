# Fase 2: remoção de bloatware pré-instalado.

if [ -s "$LISTS/removals.txt" ]; then
  mapfile -t REMS < <(read_list "$LISTS/removals.txt")
  REMS_EXPANDIDOS=()
  for p in "${REMS[@]:-}"; do
    [ -z "$p" ] && continue
    if [[ $p == *'*'* ]]; then
      while IFS= read -r encontrado; do [ -n "$encontrado" ] && REMS_EXPANDIDOS+=("$encontrado"); done < <(rpm -qa --qf '%{NAME}\n' | grep -E "^${p//\*/.*}$" || true)
    else
      REMS_EXPANDIDOS+=("$p")
    fi
  done
  REMS_A_REMOVER=()
  for p in "${REMS_EXPANDIDOS[@]:-}"; do [ -z "$p" ] && continue; rpm_installed "$p" && REMS_A_REMOVER+=("$p"); done
  if [ "${#REMS_A_REMOVER[@]}" -eq 0 ]; then
    ok "bloatware já removido — pulando"
  else
    try_warn dnf remove -y --setopt=clean_requirements_on_remove=True "${REMS_A_REMOVER[@]}"
    ok "bloatware removido"
  fi
fi