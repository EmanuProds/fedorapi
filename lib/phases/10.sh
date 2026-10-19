# Fase 10: dconf (GNOME). App Folders vêm do dotfiles.

try_warn as_user dconf load / < "$CLONES/dotfiles/dconf/gnome-settings.ini"
ok "dconf restaurado (app-folders vêm do dotfiles)"