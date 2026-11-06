#!/bin/sh
set -eu

VERSION=$1
DIST=installer/dist
STAGE=$(mktemp -d)
chmod 755 "$STAGE"
SHARE="$STAGE/usr/share/marlinraker-desktop"

install -d "$STAGE/DEBIAN" "$STAGE/usr/bin" "$SHARE" "$STAGE/usr/share/applications" \
    "$STAGE/usr/share/icons/hicolor/scalable/apps" "$STAGE/usr/share/doc/marlinraker-desktop"

install -m 755 installer/linux/marlinraker "$STAGE/usr/bin/marlinraker"
sed "s/@VERSION@/$VERSION/" installer/linux/docker-compose.yml > "$SHARE/docker-compose.yml"
echo "marlinraker-desktop:$VERSION" > "$SHARE/IMAGE"
install -m 644 "$DIST/marlinraker-image.tar.gz" "$SHARE/marlinraker-image.tar.gz"
install -m 644 installer/linux/marlinraker-orca.desktop installer/linux/marlinraker-mainsail.desktop "$STAGE/usr/share/applications/"
install -m 644 installer/assets/marlinraker-desktop.svg "$STAGE/usr/share/icons/hicolor/scalable/apps/marlinraker-desktop.svg"
install -m 644 installer/assets/copyright "$STAGE/usr/share/doc/marlinraker-desktop/copyright"
gzip -9n < installer/linux/debian/changelog > "$STAGE/usr/share/doc/marlinraker-desktop/changelog.gz"
chmod 644 "$STAGE/usr/share/doc/marlinraker-desktop/changelog.gz"
chmod 644 "$SHARE/docker-compose.yml" "$SHARE/IMAGE"

for script in postinst prerm postrm; do
    install -m 755 "installer/linux/debian/$script" "$STAGE/DEBIAN/$script"
done
INSTALLED_SIZE=$(du -sk --exclude=DEBIAN "$STAGE" | cut -f1)
sed -e "s/@VERSION@/$VERSION/" -e "s/@INSTALLED_SIZE@/$INSTALLED_SIZE/" installer/linux/debian/control > "$STAGE/DEBIAN/control"

dpkg-deb --root-owner-group -Zxz --build "$STAGE" "$DIST/marlinraker-desktop_${VERSION}_amd64.deb"
rm -rf "$STAGE"
