# Base commune aux images "application" : terminal + Xpra 6 (serveur X virtuel
# et client HTML5). Chaque application part de cette image.
ARG BASE_IMAGE=ghcr.io/votre-org/onyxia-terminal:0.1.0
FROM ${BASE_IMAGE}

USER root

# Xpra 6 depuis le dépôt officiel xpra.org (Ubuntu 24.04 ne fournit que la 3.1).
# Si un module manque au démarrage, remplacer la liste par le méta-paquet "xpra".
RUN curl -fsSL -o /usr/share/keyrings/xpra.asc https://xpra.org/xpra.asc && \
    curl -fsSL -o /etc/apt/sources.list.d/xpra.sources \
        https://raw.githubusercontent.com/Xpra-org/xpra/master/packaging/repos/noble/xpra.sources && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        xpra-server xpra-x11 xpra-codecs xpra-html5 \
        xvfb xauth python3-gi-cairo \
        fonts-dejavu-core fonts-liberation adwaita-icon-theme && \
    /opt/clean.sh

# Client HTML5 : pas de lien vers xpra.org, qualité d'image minimale correcte
RUN printf '%s\n' \
        'blocked-hosts = xpra.org,www.xpra.org' \
        'min-quality = 30' \
        'min-speed = 50' \
        'floating_menu = true' \
        'sound = false' \
        > /etc/xpra/html5-client/default-settings.txt

USER 1000

# Par défaut, une image d'application démarre en mode application
ENV LAUNCH_MODE=application
