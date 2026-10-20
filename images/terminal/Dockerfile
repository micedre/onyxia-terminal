FROM inseefrlab/onyxia-base:latest

USER root

ARG TTYD_VERSION=1.7.7
ARG TRZSZ_VERSION=1.2.0
ARG FZF_VERSION=0.74.4
ARG NVIM_VERSION=0.12.6
ARG NERDFONT_VERSION=3.5.1
ARG UV_VERSION=0.13.1
ARG LANDRUN_VERSION=0.1.17

# Outils terminal (paquets Ubuntu 24.04), puis binaires officiels pour :
#  - ttyd    : le terminal web
#  - trzsz   : upload/download de fichiers via le navigateur (compatible tmux)
#  - fzf     : version récente (le paquet apt ne fournit pas `fzf --zsh`)
#  - starship: le prompt
#  - neovim  : version récente (celle d'Ubuntu 24.04, 0.9, est trop ancienne pour LazyVim)
#  - Symbols Nerd Font : icônes du prompt et de LazyVim, servie au navigateur par nginx
#  - uv      : gestionnaire de projets et d'environnements Python (uv, uvx)
#  - landrun + tinyproxy : sessions agent isolées (Landlock, proxy filtrant)
# Les bibliothèques lib* sont celles de chrome-headless-shell (installé plus bas
# pour Quarto : diagrammes Mermaid/Graphviz en docx/pdf)
RUN /opt/apt-install.sh \
        tmux zsh zsh-autosuggestions zsh-syntax-highlighting ncurses-term \
        ripgrep fd-find bat eza zoxide \
        btop htop ncdu tree nginx xz-utils tinyproxy \
        libnss3 libnspr4 libatk1.0-0t64 libatk-bridge2.0-0t64 libatspi2.0-0t64 \
        libcups2t64 libdrm2 libgbm1 libxkbcommon0 libxcomposite1 libxdamage1 \
        libxfixes3 libxrandr2 libpango-1.0-0 libcairo2 libasound2t64 libdbus-1-3 \
        libexpat1 fonts-liberation && \
    ln -sf /usr/bin/batcat /usr/local/bin/bat && \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd && \
    curl -fsSL -o /usr/local/bin/ttyd \
        "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.x86_64" && \
    chmod +x /usr/local/bin/ttyd && \
    curl -fsSL "https://github.com/trzsz/trzsz-go/releases/download/v${TRZSZ_VERSION}/trzsz_${TRZSZ_VERSION}_linux_x86_64.tar.gz" \
        | tar -xz --strip-components=1 -C /usr/local/bin && \
    curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_amd64.tar.gz" \
        | tar -xz -C /usr/local/bin && \
    curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b /usr/local/bin && \
    mkdir -p /opt/nvim && \
    curl -fsSL "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux-x86_64.tar.gz" \
        | tar -xz --strip-components=1 -C /opt/nvim && \
    ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim && \
    mkdir -p /opt/fonts && \
    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERDFONT_VERSION}/NerdFontsSymbolsOnly.tar.xz" \
        | tar -xJ -C /opt/fonts SymbolsNerdFontMono-Regular.ttf LICENSE && \
    curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz" \
        | tar -xz --strip-components=1 -C /usr/local/bin && \
    curl -fsSL -o /usr/local/bin/landrun \
        "https://github.com/Zouuup/landrun/releases/download/v${LANDRUN_VERSION}/landrun-linux-amd64" && \
    chmod +x /usr/local/bin/landrun && \
    /opt/clean.sh

# opencode : assistant de code IA, configuré par le chart (même script que les
# images datascience officielles, fourni par onyxia-base)
# Le script interroge l'API GitHub : en CI, le jeton (secret de build optionnel
# « github_token ») évite la limite des requêtes anonymes (erreur 403).
RUN --mount=type=secret,id=github_token \
    if [ -s /run/secrets/github_token ]; then \
        export CURL_HOME="$(mktemp -d)" && \
        printf 'header = "Authorization: Bearer %s"\n' "$(cat /run/secrets/github_token)" > "$CURL_HOME/.curlrc"; \
    fi && \
    /opt/install-opencode.sh && \
    rm -rf "${CURL_HOME:-/nonexistent}" && \
    /opt/clean.sh

COPY --chmod=0755 start.sh /opt/start.sh
# Compatibilité avec le chart vscode-python (image personnalisée)
COPY --chmod=0755 code-server-shim.sh /usr/bin/code-server
COPY nginx-terminal.conf /opt/nginx-terminal.conf
COPY nginx-proxy-common.conf /opt/onyxia-terminal/
COPY login.html /opt/login.html
COPY terminal-page.js aide.txt themes.json dotfiles/nvim-onyxia.lua /opt/onyxia-terminal/
COPY --chmod=0755 aide.sh transfert.sh theme.sh /opt/onyxia-terminal/
COPY --chmod=0755 theme.sh /usr/local/bin/theme
COPY --chmod=0755 ports.sh /usr/local/bin/ports
# Sessions agent isolées : utilisateur sans sudo ni identifiants (voir agent-session.sh)
COPY agent-session-config.py agent-llm-nginx.conf agent-tinyproxy.conf /opt/onyxia-terminal/
COPY --chmod=0755 agent-session.sh /usr/local/bin/agent-session
RUN useradd --uid 2000 --user-group --create-home --shell /bin/bash agent
COPY dotfiles/zshrc     ${HOME}/.zshrc
COPY dotfiles/tmux.conf ${HOME}/.tmux.conf
COPY dotfiles/bashrc-extra /tmp/bashrc-extra
# Le marqueur sépare la config de l'image de ce que les scripts d'init ajoutent
# ensuite à ~/.bashrc, que ~/.zshrc reprend
RUN cat /tmp/bashrc-extra >> ${HOME}/.bashrc && \
    echo "# >>> fin de la configuration de l'image (ajouts ultérieurs : scripts d'init) <<<" >> ${HOME}/.bashrc && \
    mkdir -p ${HOME}/.cache && \
    /opt/fix-user-permissions.sh && \
    /opt/clean.sh

USER 1000

# Chrome headless pour Quarto (installé dans ~/.local/share/quarto) ; échoue si
# une bibliothèque système manque
RUN quarto install chrome-headless-shell --no-prompt --quiet && \
    chrome="$(find ${HOME}/.local/share/quarto/chrome-headless-shell -name chrome-headless-shell -type f | head -1)" && \
    test -x "$chrome" && \
    ! ldd "$chrome" | grep "not found"

# LazyVim (config de départ) ; les plugins et les parseurs treesitter
# (ensure_installed de LazyVim) sont installés dès la construction pour un
# premier lancement immédiat, même sans réseau ($HOME hors ~/work n'est pas conservé)
RUN git clone --depth 1 https://github.com/LazyVim/starter ${HOME}/.config/nvim && \
    rm -rf ${HOME}/.config/nvim/.git && \
    cat /opt/onyxia-terminal/nvim-onyxia.lua >> ${HOME}/.config/nvim/lua/config/options.lua && \
    nvim --headless "+Lazy! sync" +qa && \
    nvim --headless \
        '+lua local p = require("lazy.core.config").plugins["nvim-treesitter"]; require("lazy").load({ plugins = { p } }); require("nvim-treesitter").install(require("lazy.core.plugin").values(p, "opts", false).ensure_installed):wait(600000)' \
        +qa && \
    test -n "$(ls ${HOME}/.local/share/nvim/site/parser)"

ENV TTYD_PORT=7681
EXPOSE 7681

# Même principe que les autres images Onyxia : le script d'init configure
# S3 / Vault / git / kubectl puis fait un `exec` de la commande passée en argument.
CMD ["/opt/onyxia-init.sh", "/opt/start.sh"]
