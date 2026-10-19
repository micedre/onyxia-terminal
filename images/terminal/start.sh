#!/usr/bin/env bash
# Point d'entrée du service, appelé par : /opt/onyxia-init.sh /opt/start.sh
#   LAUNCH_MODE=terminal     -> terminal web (ttyd + tmux)           [défaut]
#   LAUNCH_MODE=application  -> une application graphique via Xpra (APP_COMMAND)
set -euo pipefail

PORT="${TTYD_PORT:-7681}"
LOGIN="${USERNAME:-onyxia}"
WORKDIR="${ROOT_PROJECT_DIRECTORY:-${WORKSPACE_DIR:-$HOME/work}}"

die() { echo "ERREUR : $*" >&2; exit 1; }

[[ -n "${PASSWORD:-}" ]] || die "la variable PASSWORD est vide, refus de démarrer sans authentification."
mkdir -p "$WORKDIR"

# =============================================================================
#  Mode application : Xpra (serveur X virtuel + client HTML5 sur le même port)
# =============================================================================
start_application() {
    command -v xpra >/dev/null || die "Xpra n'est pas installé dans cette image (le mode application nécessite une image d'application)."
    [[ -n "${APP_COMMAND:-}" ]] || die "APP_COMMAND est vide."

    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
    mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
    export NO_AT_BRIDGE=1          # évite les avertissements d'accessibilité GTK sans D-Bus

    # Préparation propre à l'application (ex. rediriger ses données vers ~/work)
    if [[ -x /opt/app/prepare.sh ]]; then
        /opt/app/prepare.sh
    fi

    echo "Démarrage d'Xpra sur le port $PORT : $APP_COMMAND"
    cd "$WORKDIR"
    # - auth=env,name=PASSWORD : même mot de passe que le service Onyxia
    # - exit-with-children     : fermer l'appli arrête le conteneur, Kubernetes le relance
    # - start-new-commands=no  : l'utilisateur ne peut lancer que l'appli prévue
    exec xpra seamless :100 \
        --daemon=no \
        --systemd-run=no \
        --dbus=no \
        --dbus-launch= \
        --mdns=no \
        --bind-tcp="0.0.0.0:${PORT},auth=env,name=PASSWORD,verify-username=no" \
        --html=on \
        --start-child="$APP_COMMAND" \
        --exit-with-children=yes \
        --start-new-commands=no \
        --file-transfer=yes \
        --open-files=no \
        --open-url=no \
        --audio=no \
        --webcam=no \
        --printing=no \
        --notifications=no \
        --opengl=no \
        --splash=no
}

if [[ "${LAUNCH_MODE:-terminal}" == "application" ]]; then
    start_application
fi

# =============================================================================
#  Mode terminal : ttyd
# =============================================================================

# --- Shell ------------------------------------------------------------------
SHELL_BIN="$(command -v "${TERMINAL_SHELL:-zsh}" || true)"
[[ -x "$SHELL_BIN" ]] || SHELL_BIN="$(command -v bash)"
export SHELL="$SHELL_BIN"   # tmux utilise $SHELL comme default-shell

# --- Commande lancée dans chaque connexion -----------------------------------
case "${TERMINAL_MULTIPLEXER:-tmux}" in
    tmux)
        # -A : se rattache à la session "main" si elle existe déjà
        CMD=(tmux -u new-session -A -s main -c "$WORKDIR")
        ;;
    *)
        CMD=("$SHELL_BIN" -l)
        ;;
esac

# --- Thème (suit le mode sombre d'Onyxia) -------------------------------------
if [[ "${DARK_MODE:-false}" == "true" ]]; then
    THEME='{"background":"#1e1e2e","foreground":"#cdd6f4","cursor":"#f5e0dc","selectionBackground":"#585b70",
"black":"#45475a","red":"#f38ba8","green":"#a6e3a1","yellow":"#f9e2af","blue":"#89b4fa","magenta":"#f5c2e7","cyan":"#94e2d5","white":"#bac2de",
"brightBlack":"#585b70","brightRed":"#f38ba8","brightGreen":"#a6e3a1","brightYellow":"#f9e2af","brightBlue":"#89b4fa","brightMagenta":"#f5c2e7","brightCyan":"#94e2d5","brightWhite":"#a6adc8"}'
else
    THEME='{"background":"#fafafa","foreground":"#383a42","cursor":"#526eff","selectionBackground":"#d7d7d7",
"black":"#383a42","red":"#e45649","green":"#50a14f","yellow":"#c18401","blue":"#4078f2","magenta":"#a626a4","cyan":"#0184bc","white":"#a0a1a7",
"brightBlack":"#696c77","brightRed":"#e45649","brightGreen":"#50a14f","brightYellow":"#c18401","brightBlue":"#4078f2","brightMagenta":"#a626a4","brightCyan":"#0184bc","brightWhite":"#ffffff"}'
fi
THEME="$(tr -d '\n' <<< "$THEME")"

# --debug 3 : erreurs + warnings seulement (le niveau "notice" affiche le
# mot de passe encodé en base64 dans les logs du pod)
echo "Démarrage de ttyd sur le port $PORT (shell: $SHELL_BIN, multiplexeur: ${TERMINAL_MULTIPLEXER:-tmux})"

exec ttyd \
    --port "$PORT" \
    --writable \
    --check-origin \
    --credential "${LOGIN}:${PASSWORD}" \
    --cwd "$WORKDIR" \
    --ping-interval 30 \
    --debug 3 \
    --client-option fontSize="${TERMINAL_FONT_SIZE:-14}" \
    --client-option fontFamily="'JetBrains Mono', 'Fira Code', 'Cascadia Code', Menlo, Consolas, monospace" \
    --client-option "theme=${THEME}" \
    --client-option enableTrzsz=true \
    --client-option enableSixel=true \
    --client-option titleFixed="Terminal · SSP Cloud" \
    "${CMD[@]}"
