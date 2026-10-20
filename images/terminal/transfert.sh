#!/usr/bin/env bash
# Transferts de fichiers avec le navigateur (trzsz), dans un panneau tmux
# temporaire ouvert dans le dossier du panneau actif (menu du clic droit,
# boutons [↑] [↓] de la barre d'état, glisser-déposer) :
#   transfert.sh envoyer    trz : le navigateur demande les fichiers à envoyer
#   transfert.sh depot      fichiers déposés sur la page (voir terminal-page.js)
#   transfert.sh recuperer  choix des fichiers avec fzf, puis tsz
set -u

fin() {
    echo
    read -rsn1 -t 5 -p "$1 · Entrée pour fermer" || true
}

case "${1:-}" in
    envoyer)
        echo "Envoi vers $PWD"
        trz
        fin "Terminé"
        ;;
    depot)
        # Au dépôt, trzsz.js écrit « trz » (ou « trz -d ») dans ce panneau.
        # Pendant les 200 ms qui précèdent, il ignore ce qu'affiche le
        # terminal : on redessine l'écran avant de lancer le transfert.
        stty -echo -isig
        read -r -t 10 line || exit 0
        stty echo isig
        tmux refresh-client 2>/dev/null
        echo "Réception des fichiers déposés dans $PWD"
        case "$line" in
            "trz")    trz ;;
            "trz -d") trz -d ;;
            *)        exit 0 ;;
        esac
        fin "Terminé"
        ;;
    recuperer)
        mapfile -t choix < <(
            find . -mindepth 1 -maxdepth 4 \
                \( -name .git -o -name node_modules -o -name .venv -o -name __pycache__ \) -prune \
                -o -type d -printf '%P/\n' -o -printf '%P\n' 2>/dev/null | sort |
            fzf --multi --prompt "Télécharger > " --height 100% --reverse \
                --header "Tab : sélection multiple · Entrée : télécharger · Échap : annuler"
        )
        [[ ${#choix[@]} -eq 0 ]] && exit 0
        opts=()
        for f in "${choix[@]}"; do [[ -d "$f" ]] && opts=(-d) && break; done
        tsz "${opts[@]}" "${choix[@]}"
        fin "Terminé"
        ;;
    *)
        echo "usage : $0 envoyer|depot|recuperer" >&2
        exit 2
        ;;
esac
