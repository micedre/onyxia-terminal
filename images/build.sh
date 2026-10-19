#!/usr/bin/env bash
# Construit et pousse les trois images, dans l'ordre des dépendances.
#   REGISTRY=ghcr.io/mon-org VERSION=0.1.0 ./build.sh
set -euo pipefail
REGISTRY="${REGISTRY:-ghcr.io/votre-org}"
VERSION="${VERSION:-0.1.0}"
cd "$(dirname "$0")"

docker build -t "$REGISTRY/onyxia-terminal:$VERSION" terminal
docker build -t "$REGISTRY/onyxia-xpra:$VERSION" \
    --build-arg BASE_IMAGE="$REGISTRY/onyxia-terminal:$VERSION" xpra
docker build -t "$REGISTRY/onyxia-app-archi:$VERSION" \
    --build-arg BASE_IMAGE="$REGISTRY/onyxia-xpra:$VERSION" archi

if [[ "${PUSH:-true}" == "true" ]]; then
    for img in onyxia-terminal onyxia-xpra onyxia-app-archi; do
        docker push "$REGISTRY/$img:$VERSION"
    done
fi
