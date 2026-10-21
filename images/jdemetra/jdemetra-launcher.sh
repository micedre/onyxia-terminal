#!/bin/sh
# Lanceur JDemetra+ : préférences et espaces de travail dans ~/work, le seul
# dossier persistant du service ; le cache peut rester dans /tmp
export _JAVA_AWT_WM_NONREPARENTING=1   # Swing sous Xpra (pas de gestionnaire de fenêtres classique)
mkdir -p "$HOME/work/.jdemetra"
# JDemetra+ lit les dossiers XDG (Documents…) pour placer ses espaces de travail
dirs="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
if [ ! -f "$dirs" ]; then
    mkdir -p "${dirs%/*}"
    printf 'XDG_DESKTOP_DIR="$HOME/work"\nXDG_DOCUMENTS_DIR="$HOME/work"\nXDG_DOWNLOAD_DIR="$HOME/work"\n' > "$dirs"
fi
exec /opt/nbdemetra/bin/nbdemetra \
    --userdir "$HOME/work/.jdemetra/userdir" \
    --cachedir /tmp/jdemetra-cache \
    "$@"
