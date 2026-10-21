#!/usr/bin/env bash
# Installé en /usr/bin/code-server : permet de lancer cette image avec le chart
# officiel vscode-python (service.image.custom), qui exécute
# « code-server --host 0.0.0.0 ~/work » sur le port 8080. On ignore ces
# arguments et on lance start.sh sur ce port : le terminal derrière nginx, ou,
# dans une image d'application (LAUNCH_MODE et APP_COMMAND fixés par l'image),
# l'application via Xpra.

# Les scripts d'init écrits pour VS Code appellent aussi code-server pour gérer
# les extensions : sans objet ici, on ne fait rien (et surtout on ne démarre pas
# le terminal).
for arg in "$@"; do
    case "$arg" in
        --install-extension*|--uninstall-extension*|--list-extensions*|--show-versions|--extensions-dir*|--help|-h)
            echo "code-server (terminal Onyxia) : « $arg » ignoré, VS Code n'est pas installé dans cette image." >&2
            exit 0
            ;;
        --version|-v)
            echo "0.0.0-onyxia-terminal"
            exit 0
            ;;
    esac
done

export TTYD_PORT=8080
exec /opt/start.sh
