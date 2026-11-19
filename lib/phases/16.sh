# Phase 16: global git identity (user.name/user.email) + SSH key + HTTPS credentials.

_f0=$FAIL_COUNT

# The script runs as root: the identity must go into the ~/.gitconfig of the
# user who called sudo (as_user swaps HOME), never into /root.
git_global_get() { as_user git config --global --get "$1" 2>/dev/null || true; }

# Prompt on the terminal (fd 3) while stdout goes to the log. An empty answer
# keeps the current value, so re-runs stay idempotent.
ask_git_value() {
  local label="$1" current="$2" value
  if [ -n "$current" ]; then
    printf '\n%s[Git]%s %s [%s]: ' "$C_BLU" "$C_OFF" "$label" "$current" >&3
  else
    printf '\n%s[Git]%s %s: ' "$C_BLU" "$C_OFF" "$label" >&3
  fi
  read -r value || value=""
  GIT_VALUE="${value:-$current}"
}

valid_email() { case "$1" in *@*.*) return 0 ;; esac; return 1; }

if ! command_exists git; then
  warn "git not installed — global identity not configured"
elif [ ! -t 0 ]; then
  warn "no interactive terminal — global git identity not configured"
else
  ask_git_value "user.name (name in commits)" "$(git_global_get user.name)"
  git_name="$GIT_VALUE"

  # Three attempts for the email; then give up and leave the value as it is.
  git_mail=""
  for _ in 1 2 3; do
    ask_git_value "user.email (email in commits)" "$(git_global_get user.email)"
    git_mail="$GIT_VALUE"
    [ -z "$git_mail" ] && break
    valid_email "$git_mail" && break
    warn "invalid email — use the format name@example.com"
  done
  valid_email "$git_mail" || git_mail=""

  if [ -n "$git_name" ] && [ -n "$git_mail" ]; then
    try_warn as_user git config --global user.name "$git_name"
    try_warn as_user git config --global user.email "$git_mail"
    ok "git: global identity configured (${git_name} <${git_mail}>)"
  else
    warn "git: global identity not configured (empty name or email)"
  fi
fi

# --- GitHub SSH key --------------------------------------------------------
# Root cannot export SSH_AUTH_SOCK into the user's session, so the key is added
# to the agent that already exists (gnome-keyring or the ssh-agent.socket from
# phase 9). With no persistent agent, an ephemeral one is started just to
# validate the key.
SSH_KEY="$SUH/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
  warn "SSH: $SSH_KEY does not exist — key not added"
elif [ ! -t 0 ]; then
  warn "no interactive terminal — SSH key not added"
else
  SSH_SOCK=""
  for _sock in "/run/user/$UID_R/keyring/ssh" "/run/user/$UID_R/ssh-agent.socket"; do
    if [ -S "$_sock" ]; then SSH_SOCK="$_sock"; break; fi
  done
  if [ -z "$SSH_SOCK" ]; then
    as_user systemctl --user start ssh-agent.socket >/dev/null 2>&1 || true
    if [ -S "/run/user/$UID_R/ssh-agent.socket" ]; then
      SSH_SOCK="/run/user/$UID_R/ssh-agent.socket"
    fi
  fi

  if [ -n "$SSH_SOCK" ]; then
    if as_user env SSH_AUTH_SOCK="$SSH_SOCK" ssh-add "$SSH_KEY"; then
      ok "SSH: id_ed25519 key added to the agent"
    else
      warn "SSH: ssh-add failed — check the key passphrase"
    fi
    _ssh_out=$(as_user env SSH_AUTH_SOCK="$SSH_SOCK" \
      ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new git@github.com 2>&1 || true)
  else
    warn "SSH: no persistent agent — validating the key with an ephemeral agent"
    _ssh_out=$(as_user bash -c 'eval "$(ssh-agent -s)" >/dev/null &&
      ssh-add "$HOME/.ssh/id_ed25519" &&
      ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new git@github.com' 2>&1 || true)
  fi

  # GitHub replies with "successfully authenticated" and exits with code 1
  # (it does not offer a shell), so success is read from the message, not the exit code.
  if _ssh_line=$(printf '%s' "$_ssh_out" | grep -m1 'successfully authenticated'); then
    ok "SSH GitHub: $_ssh_line"
  else
    warn "SSH GitHub: did not authenticate — $(printf '%s' "$_ssh_out" | tail -1)"
  fi
fi

# --- HTTPS credentials (~/.git-credentials) --------------------------------
# The file stores the token in plain text and belongs to the user: the script
# neither reads nor writes its content, only explains the format, checks the
# permission and enables the global helper when the answer is y. "n" leaves git
# exactly as it was.
GIT_CRED_FILE="$SUH/.git-credentials"
if [ ! -t 0 ]; then
  warn "no interactive terminal — HTTPS credentials not configured"
else
  printf '\n%s[Git]%s Create/add %s in the format https://USER:TOKEN@github.com (PAT, not the password).\n' \
    "$C_BLU" "$C_OFF" "$GIT_CRED_FILE" >&3
  while :; do
    printf '%s[Git]%s Use ~/.git-credentials for clone/push? [y/n]: ' "$C_BLU" "$C_OFF" >&3
    if ! read -r _ans; then
      printf '\n' >&3
      warn "input closed — HTTPS credentials left as they are"
      break
    fi
    case "${_ans,,}" in
      y|yes)
        if [ ! -f "$GIT_CRED_FILE" ]; then
          warn "answered y, but $GIT_CRED_FILE does not exist yet — create the file and answer again"
          continue
        fi
        [ "$(stat -c %a "$GIT_CRED_FILE" 2>/dev/null)" = "600" ] || try_warn chmod 600 "$GIT_CRED_FILE"
        try_warn as_user git config --global --replace-all credential.helper store
        ok "git: credential.helper=store active (HTTPS clone/push use ~/.git-credentials)"
        break
        ;;
      n|no)
        ok "git: HTTPS credentials left as they are (nothing changed)"
        break
        ;;
      *)
        warn "invalid answer — use y/yes or n/no"
        ;;
    esac
  done
fi

phase_end "$_f0" "git identity ready"
