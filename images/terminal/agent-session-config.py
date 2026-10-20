"""Prépare la configuration d'un agent isolé (appelé par agent-session).

- Lit la config opencode de l'utilisateur (~/.config/opencode/opencode.json[c],
  écrite par le chart ou à la main) et les variables OPENAI_BASE_URL / OPENAI_API_KEY.
- Chaque fournisseur (baseURL + apiKey) devient une route du proxy local
  (http://127.0.0.1:4000/p<n>/ ; /env/ pour les variables OPENAI_*), qui ajoute
  la vraie clé. La config copiée dans la session agent ne contient qu'une clé factice.

Usage : agent-session-config.py <config opencode de la session agent> <conf nginx du proxy>
"""
import json
import os
import re
import sys
from urllib.parse import urlsplit

PROXY = "http://127.0.0.1:4000"
DUMMY_KEY = "sandbox"


def strip_jsonc(text):
    """Retire les commentaires // et /* */ et les virgules finales (hors chaînes)."""
    out, i, n, in_str = [], 0, len(text), False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            out.append(c)
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
            continue
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = n if end < 0 else end + 2
            continue
        else:
            out.append(c)
        i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


def resolve(value):
    """Résout la syntaxe opencode {env:VAR}."""
    if not isinstance(value, str):
        return None
    m = re.fullmatch(r"\{env:([A-Za-z_][A-Za-z0-9_]*)\}", value.strip())
    return os.environ.get(m.group(1)) if m else value


def nginx_quote(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def location(prefix, base_url, key):
    url = urlsplit(base_url)
    if url.scheme not in ("http", "https") or not url.hostname:
        return None
    path = url.path.rstrip("/") + "/"
    target = f"{url.scheme}://{url.netloc}{path}"
    return f"""
        location /{prefix}/ {{
            proxy_pass {target};
            proxy_set_header Host {url.netloc};
            proxy_set_header Authorization {nginx_quote("Bearer " + key)};
            proxy_ssl_server_name on;
            proxy_ssl_verify on;
            proxy_ssl_verify_depth 4;
            proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;
        }}"""


def main(config_out, nginx_out):
    home = os.environ["HOME"]
    config = {}
    for name in ("opencode.jsonc", "opencode.json"):
        path = os.path.join(home, ".config", "opencode", name)
        if os.path.isfile(path):
            with open(path, encoding="utf-8") as f:
                config = json.loads(strip_jsonc(f.read()))
            break

    locations = []
    for n, (pid, provider) in enumerate(sorted((config.get("provider") or {}).items())):
        options = provider.get("options") if isinstance(provider, dict) else None
        if not isinstance(options, dict):
            continue
        base_url, key = resolve(options.get("baseURL")), resolve(options.get("apiKey"))
        if "apiKey" in options:
            options["apiKey"] = DUMMY_KEY
        if base_url and key:
            loc = location(f"p{n}", base_url, key)
            if loc:
                locations.append(loc)
                options["baseURL"] = f"{PROXY}/p{n}"
                continue
        print(f"agent-session : fournisseur « {pid} » sans baseURL/clé utilisables, non relayé.", file=sys.stderr)

    env_url, env_key = os.environ.get("OPENAI_BASE_URL"), os.environ.get("OPENAI_API_KEY")
    if env_url and env_key:
        loc = location("env", env_url, env_key)
        if loc:
            locations.append(loc)

    os.makedirs(os.path.dirname(config_out), exist_ok=True)
    with open(config_out, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
        f.write("\n")

    old_umask = os.umask(0o077)
    try:
        with open(nginx_out, "w", encoding="utf-8") as f:
            f.write("".join(locations) + "\n")
    finally:
        os.umask(old_umask)
    print(len(locations))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
