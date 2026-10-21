#!/usr/bin/env bash
# Tests navigateur (Playwright, Chromium headless) contre une release Helm du
# chart terminal déjà déployée (voir local/install.sh).
#   tests/e2e/run.sh                 tous les tests
#   tests/e2e/run.sh clip theme      certains tests (login clip xfer theme proxy nvim-explorer)
#   tests/e2e/run.sh app [titre]     mode application (Xpra) : fenêtre affichée
# Variables : RELEASE (défaut terminal-test), BASE (défaut : hôte de l'ingress),
# CONTAINER (défaut terminal), OUT (captures d'écran, défaut : dossier temporaire).
set -euo pipefail
cd "$(dirname "$0")"
RELEASE="${RELEASE:-terminal-test}"
POD="$RELEASE-0"
CONTAINER="${CONTAINER:-terminal}"
export RELEASE

[[ -d node_modules/playwright ]] || { npm install --silent >/dev/null && npx playwright install chromium >/dev/null; }

BASE="${BASE:-https://$(helm get values "$RELEASE" -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)["ingress"]["hostname"])')}"
PASSWORD="$(kubectl exec "$POD" -c "$CONTAINER" -- printenv PASSWORD)"
OUT="${OUT:-$(mktemp -d)}"
until curl -sf -o /dev/null "$BASE/"; do sleep 3; done

if [[ "${1:-}" == app ]]; then
    node app.mjs "$BASE" "$PASSWORD" "$OUT/app" "${2:-}"
    echo "Captures : $OUT"
    exit
fi

tests=("$@")
[[ ${#tests[@]} -eq 0 ]] && tests=(login clip xfer theme proxy nvim-explorer)

for t in "${tests[@]}"; do
    if [[ "$t" == proxy ]]; then
        # Serveurs de test dans le pod : fichiers sur 8000, écho WebSocket sur 8765
        kubectl cp wsecho.py "$POD:/tmp/wsecho.py" -c terminal
        timeout 60 kubectl exec "$POD" -c terminal -- bash -c '
            up() { (exec 3<>/dev/tcp/127.0.0.1/$1) 2>/dev/null; }
            mkdir -p /tmp/www/sub && echo hello > /tmp/www/sub/f.txt
            up 8000 || (cd /tmp/www && setsid nohup python3 -m http.server 8000 >/dev/null 2>&1 </dev/null &)
            up 8765 || (setsid nohup uv run -q /tmp/wsecho.py >/dev/null 2>&1 </dev/null &)
            for i in $(seq 40); do up 8000 && up 8765 && break; sleep 1; done' || true
    fi
    # Session tmux neuve pour chaque test (ttyd la recrée à la connexion)
    kubectl exec "$POD" -c terminal -- tmux kill-session -t main 2>/dev/null || true
    echo "== $t"
    node "$t.mjs" "$BASE" "$PASSWORD" "$OUT/$t"
done
echo "Captures : $OUT"
