#!/bin/sh
set -eu

VERSION=$1
DIST=installer/dist
STAGE=$(mktemp -d)

with_bom() {
    printf '\357\273\277' > "$2"
    cat "$1" >> "$2"
}

with_bom installer/windows/marlinraker.ps1 "$STAGE/marlinraker.ps1"
with_bom installer/windows/MarlinrakerDesktop.psm1 "$STAGE/MarlinrakerDesktop.psm1"
with_bom installer/windows/installer.nsi "$STAGE/installer.nsi"
sed "s/@VERSION@/$VERSION/" installer/windows/docker-compose.yml > "$STAGE/docker-compose.yml"
printf 'marlinraker-desktop:%s' "$VERSION" > "$STAGE/IMAGE"
cp "$DIST/marlinraker-image.tar.gz" "$STAGE/"

for size in 16 32 48 256; do
    rsvg-convert -w "$size" -h "$size" installer/assets/marlinraker-desktop.svg -o "$STAGE/icon-$size.png"
done
magick "$STAGE/icon-16.png" "$STAGE/icon-32.png" "$STAGE/icon-48.png" "$STAGE/icon-256.png" "$STAGE/marlinraker-desktop.ico"

makensis -V2 -DVERSION="$VERSION" -DOUTFILE="$(pwd)/$DIST/MarlinrakerDesktopSetup-$VERSION.exe" "$STAGE/installer.nsi"
rm -rf "$STAGE"
