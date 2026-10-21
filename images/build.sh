#!/usr/bin/env bash
# Construit et pousse les images, dans l'ordre des dépendances.
#   REGISTRY=ghcr.io/mon-org VERSION=0.1.0 ./build.sh
set -euo pipefail
REGISTRY="${REGISTRY:-ghcr.io/votre-org}"
VERSION="${VERSION:-0.1.0}"
APPS=(archi jdemetra orange)
cd "$(dirname "$0")"

docker build -t "$REGISTRY/onyxia-terminal:$VERSION" terminal
docker build -t "$REGISTRY/onyxia-xpra:$VERSION" \
    --build-arg BASE_IMAGE="$REGISTRY/onyxia-terminal:$VERSION" xpra
for app in "${APPS[@]}"; do
    docker build -t "$REGISTRY/onyxia-app-$app:$VERSION" \
        --build-arg BASE_IMAGE="$REGISTRY/onyxia-xpra:$VERSION" "$app"
done

if [[ "${PUSH:-true}" == "true" ]]; then
    for img in onyxia-terminal onyxia-xpra "${APPS[@]/#/onyxia-app-}"; do
        docker push "$REGISTRY/$img:$VERSION"
    done
fi
