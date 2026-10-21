# JDemetra+ (désaisonnalisation, X-13 / TRAMO-SEATS) servi dans le navigateur via Xpra
ARG BASE_IMAGE=ghcr.io/votre-org/onyxia-xpra:0.1.0
FROM ${BASE_IMAGE}

USER root

ARG JDEMETRA_VERSION=3.9.0

# Archive « standalone » officielle : elle embarque son propre JRE, rien d'autre
# à installer que les bibliothèques X/AWT utilisées par Swing, et GTK 3 : sans
# lui, l'API Desktop de Java manque et JDemetra+ n'ouvre pas son dépôt
# d'espaces de travail
RUN /opt/apt-install.sh libxext6 libxrender1 libxtst6 libxi6 libfreetype6 fontconfig \
        libgtk-3-0t64 unzip && \
    curl -fsSL -o /tmp/jdemetra.zip \
        "https://github.com/jdemetra/jdplus-main/releases/download/v${JDEMETRA_VERSION}/jdemetra-standalone-${JDEMETRA_VERSION}-linux-x86_64.zip" && \
    unzip -q /tmp/jdemetra.zip -d /opt && \
    rm /tmp/jdemetra.zip && \
    test -x /opt/nbdemetra/bin/nbdemetra && \
    /opt/clean.sh

COPY --chmod=0755 jdemetra-launcher.sh /usr/local/bin/jdemetra

USER 1000

ENV APP_COMMAND=/usr/local/bin/jdemetra
