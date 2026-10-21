#!/bin/sh
# Lanceur Orange : réglages, extensions installées et fichiers récents dans
# ~/work, le seul dossier persistant du service
export QT_QPA_PLATFORM=xcb
# Pas de GPU, et le bac à sable de Chromium (aide en ligne) exige des droits absents du pod
export QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu --no-sandbox"
export XDG_DATA_HOME="$HOME/work/.orange/data"
export XDG_CONFIG_HOME="$HOME/work/.orange/config"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"
exec /opt/orange/bin/python -m Orange.canvas "$@"
