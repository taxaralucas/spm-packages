#!/bin/bash
NAME="$1"
VERSION="$2"
INSTALL_PATH="$3"
SRC="$4"
DESC="${5:-No description}"
DEPS="${6:-}"

if [ -z "$NAME" ] || [ -z "$VERSION" ] || [ -z "$INSTALL_PATH" ] || [ -z "$SRC" ]; then
echo "Usage: ./mkpkg.sh <name> <version> <target_install_path> <url_or_local_file> [description] [dependencies]"
exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="/tmp/mkpkg-$$"
mkdir -p "$TMP_DIR"

if [[ "$SRC" =~ ^https?:// ]]; then
echo "1. Téléchargement depuis $SRC..."
wget -q -O "$TMP_DIR/file" "$SRC" || { echo "Échec du téléchargement !"; rm -rf "$TMP_DIR"; exit 1; }
else
LOCAL_PATH="${SRC#file://}"
echo "1. Copie du fichier local $LOCAL_PATH..."
if [ -f "$LOCAL_PATH" ]; then
    cp "$LOCAL_PATH" "$TMP_DIR/file"
else
    echo "Fichier introuvable : $LOCAL_PATH"
    rm -rf "$TMP_DIR"
    exit 1
fi
fi

PKG_STAGING="$REPO_DIR/packages/${NAME}-${VERSION}"
DEST_DIR="$PKG_STAGING/data/$(dirname "$INSTALL_PATH")"
DEST_FILE="$DEST_DIR/$(basename "$INSTALL_PATH")"

mkdir -p "$DEST_DIR"
mv "$TMP_DIR/file" "$DEST_FILE"
chmod +x "$DEST_FILE"

cat > "$PKG_STAGING/pkginfo" << PKGINFO
name=$NAME
version=$VERSION
description=$DESC
PKGINFO

echo "2. Compression du paquet..."
TAR_NAME="${NAME}-${VERSION}.tar.gz"
cd "$PKG_STAGING"
tar -czf "$REPO_DIR/packages/$TAR_NAME" data pkginfo
cd "$REPO_DIR"

echo "3. Nettoyage..."
rm -rf "$PKG_STAGING" "$TMP_DIR"

echo "4. Mise à jour d'index.txt..."
sed -i "/^${NAME}|/d" index.txt 2>/dev/null
echo "${NAME}|${VERSION}|${DEPS}|${TAR_NAME}|${DESC}" >> index.txt

echo "5. Push vers GitHub..."
git add "packages/$TAR_NAME" index.txt
git commit -m "Add package: $NAME $VERSION"
git push

echo "Paquet '$NAME' prêt !"
