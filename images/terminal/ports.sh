#!/usr/bin/env bash
# Serveurs web du terminal, ouverts dans le navigateur via le proxy du terminal.
#   ports          liste les ports TCP en écoute, avec leur lien
#   ports 8000     affiche le lien du port 8000
# Liens : $TERMINAL_URL/proxy/PORT/ (TERMINAL_URL posé par le chart Helm ; à
# défaut, chemin à ajouter à l'adresse du terminal).
set -u

BASE="${TERMINAL_URL:-}"
BASE="${BASE%/}"
# Ports internes : frontal du terminal, proxys des sessions agent
INTERNES=" ${TTYD_PORT:-7681} 8888 4000 "

lien() {
    local url="$BASE/proxy/$1/"
    # OSC 8 : lien cliquable dans le terminal ; le texte reste l'URL
    printf '\e]8;;%s\e\\%s\e]8;;\e\\' "$url" "$url"
}

if [[ $# -gt 0 ]]; then
    [[ "$1" =~ ^[0-9]{2,5}$ ]] || { echo "usage : ports [PORT]" >&2; exit 2; }
    lien "$1"; echo
    [[ -z "$BASE" ]] && echo "(chemin à ajouter à l'adresse du terminal)"
    exit 0
fi

# Ports en écoute (état 0A) d'après /proc/net/tcp{,6}, avec le processus
# quand il appartient à l'utilisateur
python3 -I - <<'EOF' | sort -n -u | while read -r port proc; do
import os, re
inodes = {}
for f in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        for line in open(f).readlines()[1:]:
            c = line.split()
            if c[3] == "0A":
                inodes[c[9]] = int(c[1].rsplit(":", 1)[1], 16)
    except OSError:
        pass
names = {}
for pid in filter(str.isdigit, os.listdir("/proc")):
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            m = re.match(r"socket:\[(\d+)\]", os.readlink(f"/proc/{pid}/fd/{fd}"))
            if m and m.group(1) in inodes:
                names[m.group(1)] = open(f"/proc/{pid}/comm").read().strip()
    except OSError:
        pass
for inode, port in inodes.items():
    print(port, names.get(inode, "?"))
EOF
    [[ "$INTERNES" == *" $port "* ]] && continue
    printf '%-6s %-16s ' "$port" "$proc"
    lien "$port"; echo
done | { out="$(cat)"; if [[ -n "$out" ]]; then echo "$out"; else echo "Aucun serveur en écoute (lancez par exemple : python3 -m http.server 8000)"; fi; }
[[ -z "$BASE" ]] && echo "(liens : chemins à ajouter à l'adresse du terminal)"
exit 0
