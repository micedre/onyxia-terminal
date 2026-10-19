FROM inseefrlab/onyxia-base:latest

USER root

ARG TTYD_VERSION=1.7.7
ARG TRZSZ_VERSION=1.2.0
ARG FZF_VERSION=0.74.4
ARG NVIM_VERSION=0.12.6

# Outils terminal (paquets Ubuntu 24.04), puis binaires officiels pour :
#  - ttyd    : le terminal web
#  - trzsz   : upload/download de fichiers via le navigateur (compatible tmux)
#  - fzf     : version récente (le paquet apt ne fournit pas `fzf --zsh`)
#  - starship: le prompt
#  - neovim  : version récente (celle d'Ubuntu 24.04, 0.9, est trop ancienne pour LazyVim)
RUN /opt/apt-install.sh \
        tmux zsh zsh-autosuggestions zsh-syntax-highlighting ncurses-term \
        ripgrep fd-find bat eza zoxide \
        btop htop ncdu tree nginx && \
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

# LazyVim (config de départ) ; les plugins sont installés dès la construction
# pour un premier lancement immédiat, même sans réseau
RUN git clone --depth 1 https://github.com/LazyVim/starter ${HOME}/.config/nvim && \
    rm -rf ${HOME}/.config/nvim/.git && \
    nvim --headless "+Lazy! sync" +qa

ENV TTYD_PORT=7681
EXPOSE 7681

# Même principe que les autres images Onyxia : le script d'init configure
# S3 / Vault / git / kubectl puis fait un `exec` de la commande passée en argument.
CMD ["/opt/onyxia-init.sh", "/opt/start.sh"]
