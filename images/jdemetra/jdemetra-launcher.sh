#!/bin/sh
# Lanceur JDemetra+ : préférences et espaces de travail dans ~/work, le seul
# dossier persistant du service ; le cache peut rester dans /tmp
export _JAVA_AWT_WM_NONREPARENTING=1   # Swing sous Xpra (pas de gestionnaire de fenêtres classique)
mkdir -p "$HOME/work/.jdemetra"
exec /opt/nbdemetra/bin/nbdemetra \
    --userdir "$HOME/work/.jdemetra/userdir" \
    --cachedir /tmp/jdemetra-cache \
    "$@"
