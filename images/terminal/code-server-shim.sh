#!/usr/bin/env bash
# Installé en /usr/bin/code-server : permet de lancer cette image avec le chart
# officiel vscode-python (service.image.custom), qui exécute
# « code-server --host 0.0.0.0 ~/work » sur le port 8080. On ignore ces
# arguments et on démarre le terminal derrière nginx (voir start.sh).
export VSCODE_CHART_COMPAT=1
export TTYD_PORT=8080
exec /opt/start.sh
