#!/usr/bin/env bash
# agent-session : session isolée pour un agent IA (opencode par défaut).
#  - utilisateur Linux « agent » : ni variables secrètes (S3, Vault, git,
#    Kubernetes), ni sudo, ni accès aux processus de l'utilisateur ;
#  - Landlock (landrun) : seuls sa copie de travail git (sans remote) et son
#    dossier personnel sont accessibles ; réseau limité au proxy HTTP(S) et au
#    proxy LLM ;
#  - proxy HTTP(S) (tinyproxy) avec liste de domaines autorisés et journal ;
#  - proxy LLM (nginx) qui ajoute la vraie clé d'API, que l'agent ne voit jamais.
set -euo pipefail

AGENT_USER=agent
AGENTS_DIR="$HOME/work/agents"
ALLOW_FILE="$AGENTS_DIR/allow.txt"
RT=/tmp/onyxia-agents
SHARE=/opt/onyxia-terminal
HTTP_PORT=8888
LLM_PORT=4000
DEFAULT_ALLOW=(pypi.org files.pythonhosted.org registry.npmjs.org github.com
               codeload.github.com objects.githubusercontent.com raw.githubusercontent.com)

usage() {
    cat <<'EOF'
Usage : agent-session [commande] [options]

  agent-session [-n NOM] [-r DÉPÔT] [--here] [-- commande...]
      Ouvre une session agent isolée dans un nouvel onglet tmux, sur une copie
      sans remote du dépôt courant (~/work/agents/NOM). Commande : opencode.
  agent-session log [-f]          requêtes HTTP(S) et appels LLM des agents
  agent-session allow DOMAINE...  autoriser des domaines (*.exemple.org accepté)
  agent-session deny DOMAINE...   retirer des domaines
  agent-session allow --list      domaines autorisés
  agent-session fetch NOM         dans votre dépôt : récupérer les commits de
                                  l'agent (branches agent-NOM/*)
  agent-session push NOM          envoyer votre branche courante à l'agent
                                  (branche upstream/<branche> chez lui)
  agent-session list              sessions existantes

Ne lancez pas le code de l'agent dans votre session (tests, make, uv run…) :
il y aurait accès à vos identifiants. Faites-le dans la session agent.
EOF
}

die() { echo "agent-session : $*" >&2; exit 1; }
info() { echo "agent-session : $*" >&2; }

check_name() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ && "$1" != .* ]] || die "nom invalide : $1"
}

running() { [[ -s "$1" ]] && kill -0 "$(cat "$1")" 2>/dev/null; }

init_rt() {
    mkdir -p "$RT" "$AGENTS_DIR"
    chmod 700 "$RT"
    # L'utilisateur agent doit traverser ~ (sans pouvoir le lister) pour atteindre
    # ~/work/agents ; Landlock lui interdit tout le reste
    chmod o+x "$HOME"
    if [[ ! -e "$ALLOW_FILE" ]]; then
        { echo "# Domaines joignables par les sessions agent (un par ligne, *.domaine accepté)"
          printf '%s\n' "${DEFAULT_ALLOW[@]}"; } > "$ALLOW_FILE"
    fi
}

# --- Proxys (lancés avec l'utilisateur onyxia, hors de la session agent) ------
start_http_proxy() {
    sed -e "s|__RT__|$RT|g" -e "s|__ALLOW__|$RT/allow.txt|g" "$SHARE/agent-tinyproxy.conf" > "$RT/tinyproxy.conf"
    # tinyproxy lit une copie sans commentaires ni lignes vides
    grep -v -e '^\s*#' -e '^\s*$' "$ALLOW_FILE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' > "$RT/allow.txt"
    if running "$RT/tinyproxy.pid"; then
        kill -USR1 "$(cat "$RT/tinyproxy.pid")"       # relit configuration et liste
    else
        tinyproxy -c "$RT/tinyproxy.conf" || die "le proxy HTTP n'a pas démarré (voir $RT/tinyproxy.log)."
    fi
}

start_llm_proxy() {
    local config_out="$1" routes
    routes="$(python3 -I "$SHARE/agent-session-config.py" "$config_out" "$RT/llm-routes.conf")"
    [[ "$routes" -gt 0 ]] || info "aucun fournisseur LLM configuré (IA désactivée dans Onyxia ?)."
    sed "s|__RT__|$RT|g" "$SHARE/agent-llm-nginx.conf" > "$RT/llm-nginx.conf"
    if running "$RT/llm-nginx.pid"; then
        nginx -c "$RT/llm-nginx.conf" -e "$RT/llm-nginx.log" -s reload
    else
        nginx -c "$RT/llm-nginx.conf" -e "$RT/llm-nginx.log" || die "le proxy LLM n'a pas démarré (voir $RT/llm-nginx.log)."
    fi
}

# --- Échanges git (bundles : seuls des objets et des références circulent) ----
bundle_tmp() {
    local f
    f="$(mktemp /tmp/agent-bundle.XXXXXX)"
    chmod 644 "$f"       # lisible par l'utilisateur agent
    echo "$f"
}

as_agent() { sudo -u "$AGENT_USER" -H -- "$@"; }

style_window() {
    tmux set-window-option -t "$1" window-status-style "fg=colour208,bold"
    tmux set-window-option -t "$1" window-status-current-style "fg=colour208,bold,reverse"
    tmux set-window-option -t "$1" automatic-rename off
}

cmd_start() {
    local name="" repo="" here=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--name) name="${2:?}"; shift 2 ;;
            -r|--repo) repo="${2:?}"; shift 2 ;;
            --here)    here=1; shift ;;
            -h|--help) usage; exit 0 ;;
            --)        shift; break ;;
            -*)        die "option inconnue : $1 (voir --help)" ;;
            *)         break ;;
        esac
    done
    local cmd=("$@")
    [[ ${#cmd[@]} -gt 0 ]] || cmd=(opencode)

    id "$AGENT_USER" >/dev/null 2>&1 || die "l'utilisateur $AGENT_USER n'existe pas dans cette image."
    local abi
    abi="$(python3 -I -c 'import ctypes; print(ctypes.CDLL(None).syscall(444, None, 0, 1))')"
    [[ "$abi" -ge 4 ]] || die "Landlock indisponible ou trop ancien sur ce nœud (ABI $abi, 4 requise)."

    [[ -n "$repo" ]] || repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "$name" ]] || name="$(basename "${repo:-agent}")"
    check_name "$name"
    init_rt

    local ws="$AGENTS_DIR/$name" ahome="$AGENTS_DIR/.home/$name"
    sudo install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 700 "$ahome" "$ahome/tmp"
    if ! sudo test -d "$ws"; then
        if [[ -n "$repo" ]]; then
            [[ "$(realpath "$repo")" != "$(realpath "$AGENTS_DIR")"/* ]] || die "ce dépôt est déjà une copie d'agent."
            local branch bundle
            branch="$(git -C "$repo" symbolic-ref --short -q HEAD || echo HEAD)"
            bundle="$(bundle_tmp)"
            sudo install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 700 "$ws"
            git -C "$repo" bundle create -q "$bundle" HEAD ${branch:+"$branch"} 2>/dev/null \
                || git -C "$repo" bundle create -q "$bundle" HEAD
            as_agent git clone -q "$bundle" "$ws"
            as_agent git -C "$ws" remote remove origin
            rm -f "$bundle"
            info "copie de $repo ($branch) dans $ws, sans remote."
        else
            sudo install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 700 "$ws"
            as_agent git init -q "$ws"
            info "pas de dépôt git ici : nouveau dépôt vide $ws."
        fi
    fi

    # Config opencode nettoyée : clé factice, baseURL vers le proxy LLM
    local cfg
    cfg="$(mktemp -d "$RT/cfg.XXXXXX")"
    if [[ -d "$HOME/.config/opencode" ]]; then
        find "$HOME/.config/opencode" -mindepth 1 -maxdepth 1 ! -name 'opencode.json*' ! -name 'backup*' \
            -exec cp -r {} "$cfg/" \;
    fi
    start_llm_proxy "$cfg/opencode.json"
    sudo install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 700 "$ahome/.config" "$ahome/.config/opencode"
    sudo cp -r "$cfg/." "$ahome/.config/opencode/"
    sudo chown -R "$AGENT_USER:$AGENT_USER" "$ahome/.config/opencode"
    rm -rf "$cfg"
    start_http_proxy

    local proxy="http://127.0.0.1:$HTTP_PORT"
    # --best-effort : landrun vise la dernière ABI Landlock ; l'ABI >= 4 vérifiée
    # plus haut couvre fichiers, ports TCP et isolation des processus
    local run=(sudo -u "$AGENT_USER" -H -- /usr/local/bin/landrun --best-effort
        --rox /usr --rox /opt --rox /bin --rox /sbin --rox /lib --rox /lib64 --ignore-missing
        --ro /etc --ro /proc --rw /dev
        --rwx "$ws" --rwx "$ahome"
        --connect-tcp "$HTTP_PORT" --connect-tcp "$LLM_PORT"
        --env "HOME=$ahome" --env "USER=$AGENT_USER" --env "LOGNAME=$AGENT_USER"
        --env "PATH=$ahome/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        --env "SHELL=/bin/bash" --env "TERM=${TERM:-xterm-256color}" --env "COLORTERM=${COLORTERM:-truecolor}"
        --env "LANG=${LANG:-C.UTF-8}" --env "LC_ALL=${LC_ALL:-C.UTF-8}" --env "EDITOR=nvim"
        --env "TMPDIR=$ahome/tmp" --env "XDG_CACHE_HOME=$ahome/.cache"
        --env "HTTP_PROXY=$proxy" --env "HTTPS_PROXY=$proxy" --env "http_proxy=$proxy" --env "https_proxy=$proxy"
        --env "NO_PROXY=127.0.0.1,localhost" --env "no_proxy=127.0.0.1,localhost"
        --env "GIT_AUTHOR_NAME=agent $name" --env "GIT_AUTHOR_EMAIL=agent-$name@sandbox.invalid"
        --env "GIT_COMMITTER_NAME=agent $name" --env "GIT_COMMITTER_EMAIL=agent-$name@sandbox.invalid"
        --env "AGENT_SESSION=$name"
        --env "PS1=[agent $name] \\w \\$ "
    )
    if grep -q "location /env/" "$RT/llm-routes.conf"; then
        run+=(--env "OPENAI_BASE_URL=http://127.0.0.1:$LLM_PORT/env" --env "OPENAI_API_KEY=sandbox")
        [[ -n "${OPENAI_DEFAULT_MODEL:-}" ]] && run+=(--env "OPENAI_DEFAULT_MODEL=$OPENAI_DEFAULT_MODEL")
    fi
    run+=(-- /bin/bash -c 'cd "$1" && shift && exec "$@"' agent-session "$ws" "${cmd[@]}")

    info "session « $name » : copie de travail $ws"
    info "récupérer son travail, depuis votre dépôt : agent-session fetch $name"
    # Onglet tmux « agent:NOM », en orange pour le distinguer
    if [[ $here -eq 0 && -n "${TMUX:-}" ]]; then
        local win
        win="$(tmux new-window -P -F '#{window_id}' -n "agent:$name" -c "$AGENTS_DIR" "$(printf '%q ' "${run[@]}")")"
        style_window "$win"
    else
        if [[ -n "${TMUX:-}" ]]; then
            tmux rename-window "agent:$name"
            style_window "$(tmux display -p '#{window_id}')"
        fi
        exec "${run[@]}"
    fi
}

cmd_log() {
    init_rt
    touch "$RT/tinyproxy.log" "$RT/llm-access.log"
    # tinyproxy : « CONNECT hôte:443 », requêtes HTTP en clair, domaines refusés
    # (l'heure vient de la ligne : « NIVEAU Mon jj hh:mm:ss.mmm [pid]: ... »)
    local fmt='
        /Request \(file descriptor/ { t=$2" "$3" "$4; sub(/\.[0-9]+$/, "", t); sub(/.*\): /, ""); sub(/ HTTP\/[0-9.]+$/, ""); print t, "REQ  ", $0; fflush(); next }
        /refused on filtered domain/ { t=$2" "$3" "$4; sub(/\.[0-9]+$/, "", t); match($0, /"[^"]+"/); print t, "REFUS", substr($0, RSTART+1, RLENGTH-2); fflush(); next }'
    if [[ "${1:-}" == "-f" ]]; then
        tail -n 0 -F "$RT/tinyproxy.log" 2>/dev/null | awk "$fmt" &
        trap 'kill $! 2>/dev/null' EXIT
        tail -n 0 -F "$RT/llm-access.log" 2>/dev/null
    else
        awk "$fmt" "$RT/tinyproxy.log"
        echo "--- appels LLM"
        cat "$RT/llm-access.log"
    fi
}

cmd_allow() {
    init_rt
    if [[ "${1:-}" == "--list" || $# -eq 0 ]]; then
        grep -v -e '^\s*#' -e '^\s*$' "$ALLOW_FILE"
        return
    fi
    local d
    for d in "$@"; do
        [[ "$d" =~ ^(\*\.)?[A-Za-z0-9.-]+$ ]] || die "domaine invalide : $d"
        grep -qxF "$d" "$ALLOW_FILE" || echo "$d" >> "$ALLOW_FILE"
    done
    running "$RT/tinyproxy.pid" && start_http_proxy
    info "autorisé : $*"
}

cmd_deny() {
    init_rt
    local d tmp
    tmp="$(mktemp)"
    cp "$ALLOW_FILE" "$tmp"
    for d in "$@"; do grep -vxF "$d" "$tmp" > "$tmp.n" || true; mv "$tmp.n" "$tmp"; done
    cat "$tmp" > "$ALLOW_FILE" && rm -f "$tmp"
    running "$RT/tinyproxy.pid" && start_http_proxy
    info "retiré : $*"
}

cmd_fetch() {
    local name="${1:?nom de la session}" bundle
    check_name "$name"
    git rev-parse --git-dir >/dev/null 2>&1 || die "à lancer dans votre dépôt git."
    sudo test -d "$AGENTS_DIR/$name/.git" || die "session inconnue : $name"
    bundle="$(mktemp)"
    as_agent git -C "$AGENTS_DIR/$name" bundle create -q - --branches > "$bundle"
    git fetch -q "$bundle" "+refs/heads/*:refs/remotes/agent-$name/*"
    rm -f "$bundle"
    git branch -r --list "agent-$name/*" --format='%(refname:short)  %(objectname:short) %(contents:subject)'
    info "à relire avant tout (git log -p HEAD..agent-$name/<branche>), puis poussez une branche et ouvrez une PR."
}

cmd_push() {
    local name="${1:?nom de la session}" branch bundle
    check_name "$name"
    branch="$(git symbolic-ref --short -q HEAD)" || die "à lancer sur une branche de votre dépôt."
    sudo test -d "$AGENTS_DIR/$name/.git" || die "session inconnue : $name"
    bundle="$(bundle_tmp)"
    git bundle create -q "$bundle" "$branch"
    as_agent git -C "$AGENTS_DIR/$name" fetch -q "$bundle" "+refs/heads/$branch:refs/remotes/upstream/$branch"
    rm -f "$bundle"
    info "l'agent « $name » a reçu upstream/$branch."
}

cmd_list() {
    init_rt
    local d
    for d in "$AGENTS_DIR"/*/; do
        [[ -d "$d" ]] || continue
        d="${d%/}"
        printf '%-24s %s\n' "$(basename "$d")" "$(sudo -u "$AGENT_USER" git -C "$d" log -1 --format='%cr  %s' 2>/dev/null || echo '(vide)')"
    done
}

case "${1:-}" in
    log)        shift; cmd_log "$@" ;;
    allow)      shift; cmd_allow "$@" ;;
    deny)       shift; cmd_deny "$@" ;;
    fetch)      shift; cmd_fetch "$@" ;;
    push)       shift; cmd_push "$@" ;;
    list)       shift; cmd_list "$@" ;;
    help|-h|--help) usage ;;
    start)      shift; cmd_start "$@" ;;
    *)          cmd_start "$@" ;;
esac
