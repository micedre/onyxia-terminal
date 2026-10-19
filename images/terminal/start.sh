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

# --- Page du terminal ----------------------------------------------------------
# La page d'index de ttyd est enrichie de :
#  - JetBrains Mono (téléchargée, intégrée en data URI) et la police d'icônes
#    Nerd Font (servie par nginx) : les polices de fontFamily sont celles du
#    navigateur de l'utilisateur, souvent absentes ;
#  - terminal-page.js : presse-papiers (OSC 52, Ctrl+V), clic droit, polices.
# En cas d'échec, ttyd garde sa page par défaut.
FONT_BASE_URL="${TERMINAL_FONT_BASE_URL:-https://cdn.jsdelivr.net/npm/@fontsource/jetbrains-mono@5.0.20/files}"
FONT_DIR="$HOME/.cache/onyxia-terminal"
FONT_INDEX="$FONT_DIR/index-v3.html"   # à incrémenter quand la page change

build_index() {
    local index="$FONT_INDEX" weight font_css="" tmp_port tmp_pid
    mkdir -p "$FONT_DIR"
    [[ -s "$index" ]] && return 0

    for weight in 400 700; do
        local file="$FONT_DIR/jetbrains-mono-latin-${weight}-normal.woff2"
        if [[ -s "$file" ]] || curl -fsSL --max-time 15 -o "$file" "$FONT_BASE_URL/${file##*/}"; then
            font_css+="@font-face{font-family:'JetBrains Mono Web';font-weight:${weight};font-style:normal;font-display:block;src:url(data:font/woff2;base64,$(base64 -w0 "$file")) format('woff2');}"
        else
            rm -f "$file"
            echo "Police web indisponible (graisse ${weight}), repli sur les polices du navigateur." >&2
        fi
    done
    # Icônes Nerd Font (prompt, LazyVim) : fichier servi par nginx, en repli
    # glyphe par glyphe après JetBrains Mono
    font_css+="@font-face{font-family:'Symbols Nerd Font Mono';font-display:block;src:url(/fonts/SymbolsNerdFontMono-Regular.ttf) format('truetype');}"

    # La page d'index de ttyd est embarquée dans le binaire : on la récupère
    # auprès d'une instance temporaire, locale.
    tmp_port=$((20000 + RANDOM % 20000))
    ttyd --port "$tmp_port" --interface lo --credential "${LOGIN}:${PASSWORD}" --debug 3 true >/dev/null 2>&1 &
    tmp_pid=$!
    local ok=1 try
    for try in 1 2 3 4 5 6 7 8 9 10; do
        if curl -fsS --compressed --max-time 5 -u "${LOGIN}:${PASSWORD}" -o "$index.tmp" "http://127.0.0.1:${tmp_port}/"; then ok=0; break; fi
        sleep 0.5
    done
    kill "$tmp_pid" 2>/dev/null || true
    [[ $ok -eq 0 ]] || return 1

    PAGE_HEAD="<style>${font_css}</style><script>$(cat /opt/onyxia-terminal/terminal-page.js)</script></head>" \
        python3 -c 'import os,sys; print(sys.stdin.read().replace("</head>", os.environ["PAGE_HEAD"], 1), end="")' \
        < "$index.tmp" > "$index" || return 1
    rm -f "$index.tmp"
    grep -q "onOsc52" "$index"
}

INDEX_OPT=()
if build_index; then
    INDEX_OPT=(--index "$FONT_INDEX")
else
    rm -f "$FONT_INDEX" "$FONT_INDEX.tmp"
    echo "Page enrichie indisponible, utilisation de la page par défaut de ttyd." >&2
fi

# --debug 3 : erreurs + warnings seulement (le niveau "notice" affiche le
# mot de passe encodé en base64 dans les logs du pod)
echo "Démarrage du terminal sur le port $PORT (shell: $SHELL_BIN, multiplexeur: ${TERMINAL_MULTIPLEXER:-tmux})"

# --- Connexion : page « mot de passe seul » servie par nginx -----------------
# nginx écoute sur $PORT et ne sert ttyd (local, sous /terminal/) qu'avec le
# cookie SHA-256(sel:mot de passe) ; le sel change à chaque démarrage.
LOGIN_SALT="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
LOGIN_TOKEN="$(printf '%s' "${LOGIN_SALT}:${PASSWORD}" | sha256sum | cut -d' ' -f1)"
LOGIN_THEME=light; [[ "${DARK_MODE:-false}" == "true" ]] && LOGIN_THEME=dark
mkdir -p -m 700 /tmp/onyxia-terminal
sed -e "s/__SALT__/${LOGIN_SALT}/" -e "s/__THEME__/${LOGIN_THEME}/" /opt/login.html > /tmp/onyxia-terminal/login.html
(umask 077 && sed -e "s/__PORT__/${PORT}/" -e "s/__TOKEN__/${LOGIN_TOKEN}/" /opt/nginx-terminal.conf > /tmp/nginx-terminal.conf)
nginx -e /dev/stderr -c /tmp/nginx-terminal.conf -t -q || die "configuration nginx invalide."
nginx -e /dev/stderr -c /tmp/nginx-terminal.conf -g 'daemon off;' &

# fontFamily est passé en chaîne JSON (guillemets doubles) : ttyd lit les
# valeurs avec json-c, qui sinon ne garderait que le premier nom entre apostrophes
exec ttyd \
    --port 7682 \
    --interface lo \
    --base-path /terminal \
    --writable \
    --check-origin \
    --cwd "$WORKDIR" \
    --ping-interval 30 \
    --debug 3 \
    "${INDEX_OPT[@]}" \
    --client-option fontSize="${TERMINAL_FONT_SIZE:-14}" \
    --client-option fontFamily="\"'JetBrains Mono Web', 'Symbols Nerd Font Mono', 'JetBrains Mono', 'Fira Code', 'Cascadia Code', Menlo, Consolas, ui-monospace, 'DejaVu Sans Mono', 'Liberation Mono', 'Courier New', monospace\"" \
    --client-option "theme=${THEME}" \
    --client-option enableTrzsz=true \
    --client-option enableSixel=true \
    --client-option titleFixed="Terminal · SSP Cloud" \
    "${CMD[@]}"
