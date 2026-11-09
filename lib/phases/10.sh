# Phase 10: dconf (GNOME). App Folders come from dotfiles.

try_warn as_user dconf load / < "$CLONES/dotfiles/dconf/gnome-settings.ini"
ok "dconf restored (app-folders come from dotfiles)"
