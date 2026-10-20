#!/usr/bin/env bash
# Thème clair / sombre du terminal web (voir terminal-page.js).
#   theme                      affiche le thème courant
#   theme clair|sombre|bascule choisit le thème (mémorisé par le navigateur)
#   theme defaut               revient au thème d'Onyxia
# Appelé par tmux :
#   theme.sh toggle|hello      demande à la page de basculer / d'annoncer son thème
#   theme.sh sync light|dark   la page a changé de thème : mise à jour des Neovim ouverts
set -u

# Séquence privée lue par la page, écrite directement sur le terminal de
# chaque client tmux (pas besoin de passthrough)
send() {
    local seq
    seq="$(printf '\e]7777;theme=%s\a' "$1")"
    if [[ -n "${TMUX:-}" ]] || tmux has-session 2>/dev/null; then
        tmux list-clients -F '#{client_tty}' 2>/dev/null | while read -r tty; do
            [[ -w "$tty" ]] && printf '%s' "$seq" > "$tty"
        done
    else
        printf '%s' "$seq"
    fi
}

case "${1:-}" in
    "")
        cur="$(tmux show -gqv @theme 2>/dev/null)"
        case "$cur" in dark) echo "sombre" ;; light) echo "clair" ;; *) echo "inconnu" ;; esac
        ;;
    clair|light)     send light ;;
    sombre|dark)     send dark ;;
    bascule|toggle)  send toggle ;;
    defaut|default)  send default ;;
    hello)           send hello ;;
    sync)
        bg="${2:-}"
        [[ "$bg" == light || "$bg" == dark ]] || exit 2
        # Sockets des Neovim de l'utilisateur ($XDG_RUNTIME_DIR ou /tmp/nvim.$USER)
        find "${XDG_RUNTIME_DIR:-/tmp}" -maxdepth 4 -type s -name 'nvim.*.0' -user "$(id -u)" 2>/dev/null |
        while read -r sock; do
            timeout 2 nvim --server "$sock" --remote-expr "execute('set background=$bg')" >/dev/null 2>&1
        done
        ;;
    *)
        echo "usage : theme [clair|sombre|bascule|defaut]" >&2
        exit 2
        ;;
esac
