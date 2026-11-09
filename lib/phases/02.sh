# Phase 2: removal of pre-installed bloatware.

if [ -s "$LISTS/removals.txt" ]; then
  mapfile -t REMS < <(read_list "$LISTS/removals.txt")
  REMS_EXPANDED=()
  for p in "${REMS[@]:-}"; do
    [ -z "$p" ] && continue
    if [[ $p == *'*'* ]]; then
      while IFS= read -r found; do [ -n "$found" ] && REMS_EXPANDED+=("$found"); done < <(rpm -qa --qf '%{NAME}\n' | grep -E "^${p//\*/.*}$" || true)
    else
      REMS_EXPANDED+=("$p")
    fi
  done
  REMS_TO_REMOVE=()
  for p in "${REMS_EXPANDED[@]:-}"; do [ -z "$p" ] && continue; rpm_installed "$p" && REMS_TO_REMOVE+=("$p"); done
  if [ "${#REMS_TO_REMOVE[@]}" -eq 0 ]; then
    ok "bloatware already removed — skipping"
  else
    try_warn dnf remove -y --setopt=clean_requirements_on_remove=True "${REMS_TO_REMOVE[@]}"
    ok "bloatware removed"
  fi
fi
