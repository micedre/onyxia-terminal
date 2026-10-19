# Archi (modélisation ArchiMate) servi dans le navigateur via Xpra
ARG BASE_IMAGE=ghcr.io/votre-org/onyxia-xpra:0.1.0
FROM ${BASE_IMAGE}

USER root

# L'archive Linux officielle est publiée sur GitHub (dépôt archimatetool/archi.io).
# Attention : le tag est réutilisé à chaque version, vérifier l'URL avant de construire.
ARG ARCHI_VERSION=5.10.0
ARG ARCHI_TAG=5.10

# webkit2gtk : navigateur interne d'Archi (vue "Hints", aperçus)
RUN /opt/apt-install.sh libwebkit2gtk-4.1-0 && \
    curl -fsSL "https://github.com/archimatetool/archi.io/releases/download/${ARCHI_TAG}/Archi-Linux64-${ARCHI_VERSION}.tgz" \
        | tar -xz -C /opt 2>/dev/null; \
    test -x /opt/Archi/Archi && \
    # Toutes les données d'Archi (préférences, plugins, modèles) vont dans ~/work,
    # le seul dossier persistant du service
    sed -i \
        -e 's#user\.home/\.archi#user.home/work/.archi#g' \
        -e 's#user\.home%/\.archi#user.home%/work/.archi#g' \
        -e 's#user\.home/Documents/Archi#user.home/work/Archi#g' \
        /opt/Archi/Archi.ini && \
    /opt/clean.sh

COPY --chmod=0755 archi-launcher.sh /usr/local/bin/archi

USER 1000

ENV APP_COMMAND=/usr/local/bin/archi
