# Orange Data Mining (apprentissage automatique visuel, par blocs) servi dans le navigateur via Xpra
ARG BASE_IMAGE=ghcr.io/votre-org/onyxia-xpra:0.1.0
FROM ${BASE_IMAGE}

USER root

ARG ORANGE_VERSION=3.40.0

# Bibliothèques X/xcb de Qt 6, puis Orange dans son propre environnement
# (uv, Python du système) pour ne pas interférer avec les projets de l'utilisateur
RUN /opt/apt-install.sh \
        libxkbcommon-x11-0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 \
        libxcb-render-util0 libxcb-xinerama0 libxcb-shape0 libxcb-cursor0 libxcb-xkb1 \
        libgl1 libegl1 libdbus-1-3 libfontconfig1 && \
    uv venv --python /usr/bin/python3 /opt/orange && \
    uv pip install --no-cache --python /opt/orange/bin/python \
        "orange3==${ORANGE_VERSION}" PyQt6 PyQt6-WebEngine && \
    /opt/orange/bin/python -c "import Orange.canvas" && \
    /opt/clean.sh

COPY --chmod=0755 orange-launcher.sh /usr/local/bin/orange

USER 1000

ENV APP_COMMAND=/usr/local/bin/orange
