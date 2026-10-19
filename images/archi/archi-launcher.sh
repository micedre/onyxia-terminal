#!/bin/sh
# Lanceur Archi : reprend les réglages d'Archi.sh, adaptés à Xpra
export GDK_BACKEND=x11
export GTK_OVERLAY_SCROLLING=0
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export UBUNTU_MENUPROXY=0
unset GTK_IM_MODULE   # Xpra impose "xim", qu'Archi déconseille
exec /opt/Archi/Archi "$@"
