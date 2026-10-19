# Fase 3: mise (node/bun/go/usage/pipx/gh).

_f0=$FAIL_COUNT
as_user bash -c 'curl -fsSL https://mise.run | sh' || warn "mise.run falhou"
if [ -x "$SUH/.local/bin/mise" ]; then
  mapfile -t TOOLS < <(read_list "$LISTS/mise.txt")
  [ "${#TOOLS[@]}" -gt 0 ] && try_warn as_user "$SUH/.local/bin/mise" use -g "${TOOLS[@]}"
fi
# shims para /usr/local/bin
if [ -d "$SUH/.local/share/mise/shims" ]; then
  for shim in npm node bun bunx gh go pipx omniroute; do
    [ -e "$SUH/.local/share/mise/shims/$shim" ] || continue
    ln -sfn "$SUH/.local/share/mise/shims/$shim" "/usr/local/bin/$shim"
  done
  ok "shims do mise expostos em /usr/local/bin"
fi

# Go: GOPATH/GOMODCACHE em ~/.go (e não no padrão ~/go). Persiste via go env -w
# (lido pelo comando go em qualquer contexto) + environment.d (systemd/PAM/ssh).
if [ -x "$SUH/.local/bin/mise" ]; then
  as_user mkdir -p "$SUH/.go" "$SUH/.go/bin" "$SUH/.config/go" "$SUH/.config/environment.d"
  if [ -d "$SUH/go" ]; then
    as_user bash -c 'shopt -s dotglob nullglob; for f in "$HOME/go"/*; do [ -e "$f" ] && mv -f "$f" "$HOME/.go/"; done; rmdir "$HOME/go" 2>/dev/null || true'
    ok "Go: cache ~/go migrado para ~/.go"
  fi
  try_warn as_user "$SUH/.local/bin/mise" exec -- go env -w GOPATH="$SUH/.go" GOMODCACHE="$SUH/.go/pkg/mod"
  cat > "$SUH/.config/environment.d/go.conf" <<EOF
# Go workspace em ~/.go (em vez do padrão ~/go)
GOPATH=$SUH/.go
GOMODCACHE=$SUH/.go/pkg/mod
BASH_ENV=$SUH/.bashrc
PATH=$SUH/.go/bin:\${PATH}
EOF
  chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.config/environment.d/go.conf"
  printf 'GOMODCACHE=%s/.go/pkg/mod\nGOPATH=%s/.go\n' "$SUH" "$SUH" > "$SUH/.config/go/env"
  chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$SUH/.config/go/env"
  ok "Go: GOPATH configurado em ~/.go"
fi
phase_end "$_f0" "toolchains prontos"