# AGENTS.md — notes for coding agents resuming work on this repo

Read this first, then `README.md` (user-facing, in French) and
`docs/isolation-agents.md` (agent isolation design, choices and trade-offs).

## What this is

A web terminal service for Onyxia / SSP Cloud: a Docker image
(`ghcr.io/micedre/onyxia-terminal`) and a Helm chart (`chart/terminal`). It also works
as a custom image for the official `vscode-python` chart. In the browser it gives:

- tmux + zsh in the browser (ttyd behind nginx), with a password-only login page;
- Neovim + LazyVim preinstalled (plugins and treesitter parsers are baked in);
- opencode configured from the chart's `ai` block;
- file transfers (trzsz), a light/dark theme switch, a code-server-like
  `/proxy/PORT/` for local web servers;
- `agent-session`: isolated AI agent sessions (separate user + Landlock + an allowlist proxy).

Derived images run one desktop app through Xpra (application mode of the chart):
`images/xpra` (base), then `images/archi`, `images/jdemetra` (JDemetra+, seasonal
adjustment) and `images/orange` (Orange Data Mining). Each app image sets
`LAUNCH_MODE`/`APP_COMMAND` itself, so it also starts under the vscode-python chart
(custom image, via the `code-server` shim).

## Conventions

- **Language:** code comments, UI strings, help text and docs are in **French**. Match the
  density and tone of the surrounding code (short "why" comments, no noise). This
  file is in English for agents.
- **Commits:** go straight to `main` (the user's workflow). Messages are in English: an imperative
  subject plus a bullet body, ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (or the attribution
  line the harness gives you).
- **Push** with the token from the environment, never stored in git config:
  ```bash
  git -c http.extraheader="Authorization: Basic $(printf 'x-access-token:%s' "$GIT_PERSONAL_ACCESS_TOKEN" | base64 -w0)" push origin main
  ```
  `gh` is not installed. Use the GitHub REST API with the same token (e.g. to poll
  Actions runs).
- **Secrets:** `local/` is gitignored and holds secrets (the test release's password, an LLM API key)
  plus helper scripts. Never commit it or print its secrets.
- **Cluster:** namespace `user-h4njlg`, test release `terminal-test`. Don't touch the
  user's other releases without asking. Uninstall `terminal-test` when done.
- **Don't** weaken pod security (e.g. AppArmor `Unconfined`). It was proposed and
  refused; the agent-isolation design deliberately works within the default profile.

## Layout

| Path | Role |
|---|---|
| `images/terminal/Dockerfile` | the main image (on top of `inseefrlab/onyxia-base`); version ARGs at the top (ttyd, trzsz, fzf, nvim, Nerd Font, uv, landrun) |
| `images/terminal/start.sh` | entrypoint: init scripts, theme, builds the enriched ttyd index page, templates and starts nginx, then `exec ttyd` |
| `images/terminal/nginx-terminal.conf` | front on `$PORT` (7681; 8080 under vscode-python): `/login`, `/logout`, `/fonts/`, `/terminal/` → ttyd unix socket, `/proxy/PORT/` + `/absproxy/PORT/` |
| `images/terminal/nginx-proxy-common.conf` | directives shared by the proxy locations |
| `images/terminal/login.html` | password form; cookie = SHA-256(salt:password), salt generated at each start (`__SALT__`, `__THEME__` filled by start.sh) |
| `images/terminal/terminal-page.js` | injected into ttyd's page: font re-measure, OSC 52 clipboard, Ctrl+V, right-click, trzsz drop redirect + drop overlay, theme, localhost-link rewriting |
| `images/terminal/themes.json` | the two xterm palettes (single source) |
| `images/terminal/dotfiles/tmux.conf` | keybindings (Alt+…), status-bar buttons, French right-click menu, user keys, hooks |
| `images/terminal/dotfiles/nvim-onyxia.lua` | appended to LazyVim's `options.lua`: OSC 52 clipboard, background from tmux `@theme` |
| `images/terminal/dotfiles/nvim-plugins-onyxia.lua` | copied to `lua/plugins/onyxia.lua`: snacks explorer/files/grep show hidden files |
| `images/terminal/aide.txt`, `aide.sh` | help popup (Alt+h, `[?]`) |
| `images/terminal/transfert.sh` | trz/tsz in a temporary tmux pane (menu, `[↑]`/`[↓]`, drag-and-drop) |
| `images/terminal/theme.sh` | `theme` command and tmux-side theme plumbing |
| `images/terminal/ports.sh` | `ports` command (listening ports + `/proxy` links) |
| `images/terminal/agent-session.sh` (+ `agent-*.conf`, `agent-session-config.py`) | isolated agent sessions |
| `images/terminal/code-server-shim.sh` | fake `code-server` so the vscode-python chart starts the terminal (or the image's app) |
| `images/xpra/` | Xpra 6 + HTML5 client on top of onyxia-terminal; `ENV LAUNCH_MODE=application` |
| `images/{archi,jdemetra,orange}/` | one app each: Dockerfile + `*-launcher.sh` (redirects the app's data to `~/work`), `ENV APP_COMMAND` |
| `chart/terminal/` | Helm chart (library-chart dependency; `values.schema.json` drives the Onyxia form; `templates/NOTES.txt` gives tips in FR/EN) |
| `tests/e2e/` | Playwright browser tests run against a deployed release (`run.sh`) |
| `docs/isolation-agents.md` | agent isolation: threat model, options studied, architecture, limits |
| `.github/workflows/` | builds and pushes images on push to `main` (tags `latest`, `sha-xxxxxxx`) and on `v*` tags |

## Runtime architecture

```
browser ──HTTPS──▶ ingress ──▶ nginx :7681 ──cookie ok──▶ /terminal/ → ttyd (unix socket /tmp/onyxia-terminal/ttyd.sock, dir 700)
                                           ├─▶ /proxy/PORT/ → 127.0.0.1:PORT (fallback [::1])
                                           └─▶ /login, /fonts/ (public)
application mode: ingress ──▶ nginx :7681 (static Xpra HTML5 client from /usr/share/xpra/www) ──WebSocket──▶ Xpra 127.0.0.1:14500 (password auth)
ttyd → tmux session "main" → zsh
```

**Browser ↔ tmux side channels.** There is no API between the page and the pod. Reuse these channels rather than inventing new ones:

| Direction | Mechanism | Used for |
|---|---|---|
| pod → page | OSC 52 (tmux `set-clipboard on`) | copy to the browser clipboard |
| tmux → page | OSC `7777;theme=…`, written to `#{client_tty}` by `theme.sh` | theme toggle/hello |
| page → tmux | user keys: `\e[7999~` User0, `\e[7998~` User1, `\e[7997~` User2 | User0: open the drop pane; User1/User2: theme light/dark |
| page ↔ trzsz | `findTrzsz()` locates ttyd's private ZmodemAddon via xterm internals; `sendToServer` is wrapped | drag-and-drop without Ctrl+C in the active pane |
| page | `window.open` wrapper | clicked `http://localhost:PORT` links → `/proxy/PORT/` |

**Reserved local ports:**
- 8888: tinyproxy, for agents;
- 4000: the LLM key proxy, for agents;
- 7681 / `$PORT`: the front.

All three are refused by `/proxy`.

## Technical choices

Rationale behind non-obvious implementation choices (the README only gives an overview).

| Topic | Choice |
|---|---|
| **Front & auth** | |
| Single port | nginx listens on 7681 (8080 under vscode-python), in front of ttyd or Xpra: same ingress and probes in both modes |
| Terminal auth | login page served by nginx; cookie = SHA-256(salt:password), salt drawn at each start (the password is stored neither in the cookie nor in the config); the page requires HTTPS (WebCrypto) |
| ttyd socket | ttyd listens on a private unix socket (`/tmp/onyxia-terminal`, 700), not a local port: neither the pod nor an agent session can reach it without going through nginx |
| Probes | `tcpSocket` in our chart; `/` returns 200 (a page pointing to `terminal/`) for vscode-python's HTTP probes, which follow redirects |
| ttyd logs | `--debug 3`: the default level writes credentials to the logs |
| Port proxy | nginx `/proxy/PORT/` and `/absproxy/PORT/` → `127.0.0.1:PORT` (fallback `[::1]`), same cookie as the terminal, WebSocket, redirect rewriting; the front and agent proxy ports are refused; `http://localhost:PORT` links clicked in the terminal are rewritten by `terminal-page.js` (`window.open` wrapper) |
| **Terminal page** | |
| Enriched index | ttyd's index page is rebuilt at start: embedded font (data URI), Nerd Font icons, `terminal-page.js` (cell re-measure after fonts load, OSC 52, Ctrl+V, right-click) |
| Font list | passed to ttyd as a JSON string: ttyd parses options with json-c, which otherwise keeps only the first quoted name |
| **tmux features** | |
| Transfers (trzsz) | each transfer opens in a temporary tmux pane (`transfert.sh`); on drop, trzsz.js sends Ctrl+C then `trz` to the active pane, so `terminal-page.js` replaces that Ctrl+C with a tmux key (`User0`) that opens the receiving pane, where `trz` lands |
| Theme | palettes in `themes.json`; tmux asks the page via a private sequence (`OSC 7777`, written to the client tty), the page answers with a key (`User1`/`User2`) that sets `@theme` in tmux and sends `set background` to running Neovims (`nvim --server`) |
| Right-click menu | `display-menu -O`: without it, the button release (~100 ms after the click) closes the menu at once |
| **Tools** | |
| Neovim | official archive (Ubuntu 24.04's is too old for LazyVim); OSC 52 clipboard, paste from the register (reading the clipboard via OSC 52 would block under tmux) |
| opencode | onyxia-base install script; in CI, GitHub token passed as a build secret (avoids the anonymous API limit); config mounted by the chart (`library-chart.secretOpencode`) |
| **Init** | |
| Git repository from the form | `onyxia-init.sh` (onyxia-base) only clones `git.repository` when a git token is set; without one, `start.sh` clones the (public) repo itself |
| zsh and init scripts | `~/.bashrc` carries an end-of-config marker; `~/.zshrc` sources what init scripts append after it |
| **Agents** | |
| Isolated agents | `agent` user + Landlock (landrun) + tinyproxy + LLM key proxy; bubblewrap rejected because the pods' AppArmor profile denies mounts; see `docs/isolation-agents.md` |
| **Application mode** | |
| Application front | nginx serves Xpra's HTML5 client itself (precompressed `.gz`) and passes only the WebSocket to Xpra (`127.0.0.1:14500`, password auth): served by Xpra (brotli), part of the files came back as 502 in a user's browser (`XpraClient is not defined`) |
| Application auth | Xpra `auth=env,name=PASSWORD,verify-username=no` (HMAC challenge, the password never travels in clear) |
| App start | `--start-child-after-connect`: at the first connection, once the virtual screen matches the browser (otherwise JDemetra+ opened at 7376×3720) |
| App exit | `--exit-with-children`: closing the app stops the container, Kubernetes restarts it |
| Lock-down | `--start-new-commands=no`: the user can only run the intended app |
| Xpra | version 6 from the xpra.org repo (Ubuntu 24.04 only ships 3.1) |
| Archi data | `Archi.ini` rewritten: preferences, plugins and models in `~/work/.archi` and `~/work/Archi` |
| JDemetra+ | official standalone archive (bundled JRE 21); `--userdir ~/work/.jdemetra/userdir`, cache in `/tmp` |
| Orange | `orange3` + PyQt6 in a separate uv env (`/opt/orange`), to keep user projects untouched; settings and add-ons in `~/work/.orange` (`XDG_DATA_HOME`, `XDG_CONFIG_HOME`); online help (QtWebEngine) without GPU or sandbox |

## Dev / test loop

1. Edit, then commit and push to `main`. CI builds `ghcr.io/micedre/onyxia-terminal:latest` in about 6–9 min.
   Poll it with:
   ```bash
   curl -s -H "Authorization: Bearer $GIT_PERSONAL_ACCESS_TOKEN" \
     "https://api.github.com/repos/micedre/onyxia-terminal/actions/runs?per_page=1&head_sha=$(git rev-parse HEAD)"
   ```
2. Deploy with `bash local/install.sh` (`helm upgrade --install terminal-test chart/terminal -f local/values.yaml`, `pullPolicy: Always`).
   - If the pod spec didn't change, **delete the pod** to pull the new image: `kubectl delete pod terminal-test-0` (no `--wait=false`; otherwise `kubectl wait` matches the old pod).
   - Then wait for `curl -sf https://<host>/login`. The ingress lags a little after Ready.
3. Run the browser tests with `tests/e2e/run.sh [login clip xfer theme proxy nvim-explorer]`. Each test starts from a fresh tmux session `main` (killed before each test). It installs Playwright on first run, gets the password via `kubectl exec … printenv PASSWORD`, and gets the host from `helm get values`. Look at the screenshots it saves.
4. Run quick checks inside the pod with `kubectl exec terminal-test-0 -c terminal -- bash -c '…'`.
   - To validate an nginx change before a CI build: `kubectl cp` the conf, `sed` the `__PORT__`/`__TOKEN__` placeholders, then `nginx -t -c …`.
5. Run `helm uninstall terminal-test` at the end.

vscode-python compatibility: `local/install-vscode.sh` (release `vscode-term`, values in `local/vscode-values.yaml`).

## Gotchas learned the hard way

- **nginx:**
  - a regex containing `{n,m}` must be quoted;
  - `map_hash_bucket_size 128` must come before the first `map` (the 64-hex token);
  - `proxy_pass` with variables can't use `proxy_redirect default`;
  - `if` inside a location is limited: prefer separate locations.
- **ttyd:**
  - client options are parsed by json-c, so `fontFamily` is passed as a JSON string, otherwise only the first quoted name survives;
  - ttyd recreates the trzsz addon and re-applies its theme on every reconnect, so `terminal-page.js` re-checks every 500 ms.
- **trzsz.js:**
  - on drop it sends `\x03` (while `uploadInterrupting` is true) then `trz\r` to the active pane;
  - it drops server output for 200 ms, so `transfert.sh depot` runs `tmux refresh-client`;
  - pickers and downloads need the File System Access API (Chrome/Edge only).
- **tmux 3.4:**
  - `display-menu` needs `-O`, or the menu closes on button release;
  - right-click menu keys in use: h p m e r t a d b z x.
- **tmux copy:** `mode-keys` defaults to emacs here (tmux starts before zsh exports `EDITOR`), and an emacs selection excludes the cell under the mouse, so dragging dropped the last character. The default `word-separators` (all punctuation) cut double-clicked base64 tokens. Both are set in `tmux.conf`, and `clip.mjs` asserts them.
- **Xpra apps:**
  - nginx serves the HTML5 client itself (`images/xpra/nginx-xpra.conf`). Served directly by Xpra (brotli, its own HTTP server), part of the files came back as 502 in the user's Edge (`XpraClient is not defined`). It was not reproducible from the cluster or headless Chromium, and it was fixed by the front. `Error importing enc_remote` in the logs is harmless;
  - started with `--start-child-after-connect`, otherwise they size their window for the 8192x4096 initial virtual screen;
  - JDemetra+ (NetBeans) needs GTK 3 for Java's Desktop API (no workspace repository without it), and keeps a lock in its userdir: a second instance with the same `HOME` hands over to the first and exits.
- **Shortcuts:** Alt+c is fzf's cd widget, so don't bind it (theme is Alt+m). Browser-reserved keys (Ctrl+W/T) are why everything uses Alt.
- **Neovim / tokyonight:** setting `background=light` before the colorscheme loads is overridden. `nvim-onyxia.lua` applies it on `VimEnter`. Running instances are updated via `nvim --server <sock> --remote-expr`.
- **SSP Cloud pods:**
  - the AppArmor profile `cri-containerd.apparmor.d` denies `mount`, so bubblewrap and similar can't work;
  - Landlock ABI 6 works: landrun needs `--best-effort`, and `agent-session` checks ABI ≥ 4 itself. Agent sessions also can't `bind` TCP ports (verified).
- **onyxia-init.sh clone bug:** without `GIT_PERSONAL_ACCESS_TOKEN`, `CLONE_URL` is never set, so `git.repository` isn't cloned (`fatal: You must specify a repository to clone`). `start.sh` clones it as a fallback. Upstream fix belongs in onyxia-base.
- **`kubectl exec`** with background processes hangs until they exit. Use `setsid nohup … >/dev/null 2>&1 </dev/null &` and a `timeout`.
- **zsh** asks for confirmation on `rm *`, which breaks scripted terminal tests. Use fresh directories instead.
- **Page cache:** the enriched index page is cached as `~/.cache/onyxia-terminal/index-vN.html`. That path is not persistent, but bump `FONT_INDEX` in `start.sh` when the page structure changes.

## Feature → files map

| Feature | Files | Tests |
|---|---|---|
| Login, cookie | `login.html`, `nginx-terminal.conf`, `start.sh` | `login.mjs` |
| Neovim explorer (dotfiles) | `nvim-plugins-onyxia.lua`, Dockerfile | `nvim-explorer.mjs` |
| Clipboard, right-click, help | `terminal-page.js`, `tmux.conf`, `aide.*`, `nvim-onyxia.lua` | `clip.mjs` |
| File transfers | `transfert.sh`, `tmux.conf` (User0, menu, `[↑]`/`[↓]`), `terminal-page.js` | `xfer.mjs` |
| Theme | `themes.json`, `theme.sh`, `terminal-page.js`, `tmux.conf` (User1/2, hooks), `nvim-onyxia.lua`, `login.html` | `theme.mjs` |
| Port proxy | `nginx-terminal.conf`, `nginx-proxy-common.conf`, `ports.sh`, `terminal-page.js`, `login.html` (`?next=`), chart `TERMINAL_URL` | `proxy.mjs` |
| Desktop apps (Xpra) | `images/xpra`, `images/<app>/`, `start.sh` (`start_application`), chart `apps`/`launcher`, schema `launcher.app.listEnum`, CI steps, `images/build.sh` | `run.sh app [title]` (`app.mjs`: GET / = 200, Xpra password, window title, screenshot); for vscode-python, run `node app.mjs` directly (pod `vscode-term-vscode-python-0`, container `vscode-python`) |
| Agent isolation | `agent-session.sh`, `agent-*.conf`, `agent-session-config.py`, Dockerfile (`agent` user, landrun, tinyproxy) | manual checks, see `docs/isolation-agents.md#vérifications` |

When adding a feature, update `aide.txt`, `chart/terminal/templates/NOTES.txt` (FR and EN),
`README.md` (features table, "Ce qui a été vérifié", "Limites"; the "Choix techniques"
brick list only if a new building block is added), and the "Technical choices" table above
for any non-obvious choice.

## Open ideas / known gaps

- **Not tested:** the chart published in an Onyxia catalog (only tested via Helm); Firefox.
- **Firefox:** trz pickers and tsz downloads don't work; drag-and-drop does.
- **Theme:** with several tabs open, only the tab where the toggle happened remembers the choice.
- **Agent isolation evolutions:** listed at the end of `docs/isolation-agents.md`: mitmproxy for HTTPS paths, a separate agent pod (git flow designed there), LLM quotas.
- **os-factory/har** was evaluated. It provides workflow isolation (worktrees, verify evidence), not security isolation, and relies on Docker (absent in pods). It could only complement `agent-session`, used inside an agent workspace; not integrated.
- **Tau-Argus** was asked for: it is Windows-only (Java GUI over Windows DLLs, no maintained Linux build). Wine was offered and refused, so it is not packaged.
- No version tag has been cut yet; `v*` tags would publish versioned images.
