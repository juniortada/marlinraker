#!/bin/sh
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(cat "$ROOT/installer/VERSION")
IMAGE="marlinraker-desktop:$VERSION"
DIST="$ROOT/installer/dist"
BUILDER=marlinraker-installer-builder

rm -rf "$DIST"
mkdir -p "$DIST"

echo "- Imagem Docker $IMAGE"
docker build --platform linux/amd64 --target runtime -t "$IMAGE" "$ROOT"
docker save "$IMAGE" | gzip -9 > "$DIST/marlinraker-image.tar.gz"

echo "- Ambiente de build dos instaladores"
docker build -q -t "$BUILDER" -f "$ROOT/installer/builder.Dockerfile" "$ROOT/installer" >/dev/null

run_builder() {
    docker run --rm -u "$(id -u):$(id -g)" -v "$ROOT:/src" -w /src "$BUILDER" "$@"
}

echo "- Pacote .deb (Ubuntu)"
run_builder sh installer/linux/build-deb.sh "$VERSION"

echo "- Instalador .exe (Windows)"
run_builder sh installer/windows/build-exe.sh "$VERSION"

rm "$DIST/marlinraker-image.tar.gz"
ls -lh "$DIST"
