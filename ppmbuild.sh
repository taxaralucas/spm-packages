#!/bin/bash
# ppmbuild — yay-style builder for Paper Linux packages
set -e

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PKGNAME="$1"

if [ -z "$PKGNAME" ]; then
    echo "Usage: ppmbuild <package-name> [-i]"
    exit 1
fi

RECIPE="$REPO_DIR/recipes/${PKGNAME}.recipe"
if [ ! -f "$RECIPE" ]; then
    echo "No recipe found for '$PKGNAME' (expected: recipes/${PKGNAME}.recipe)"
    echo "Available recipes:"
    ls "$REPO_DIR/recipes" | sed 's/\.recipe$//' | sed 's/^/  - /'
    exit 1
fi

source "$RECIPE"

echo "==> Building $NAME $VERSION"
WORK_DIR="/tmp/ppmbuild-$NAME-$$"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "==> Downloading source..."
wget -q "$SOURCE_URL" -O source.tar.gz
mkdir src
tar -xf source.tar.gz -C src --strip-components=1
cd src

export OUT_BINARY="$WORK_DIR/output-binary"
echo "==> Running build()..."
build

if [ ! -f "$OUT_BINARY" ]; then
    echo "ERROR: build() did not produce \$OUT_BINARY"
    exit 1
fi

file "$OUT_BINARY" | grep -q "statically linked" || {
    echo "WARNING: output binary is NOT statically linked!"
    read -p "Continue anyway? (y/N) " ans
    [ "$ans" = "y" ] || exit 1
}

echo "==> Packaging with mkpkg.sh..."
cd "$REPO_DIR"
./mkpkg.sh "$NAME" "$VERSION" "$INSTALL_PATH" "$OUT_BINARY" "$DESC" "$DEPS"

if [ "$2" = "-i" ]; then
    echo "==> Installing into VM disk image (symlink-safe)..."
    sudo losetup -fP ~/paperlinux/paperlinux-root.img
    LOOPDEV=$(sudo losetup -j ~/paperlinux/paperlinux-root.img | cut -d: -f1)
    sudo mount "${LOOPDEV}p1" /mnt/paperlinux-root

    TARBALL="$REPO_DIR/packages/${NAME}-${VERSION}.tar.gz"
    TMP_EXTRACT="/tmp/ppmbuild-install-$$"
    mkdir -p "$TMP_EXTRACT"
    tar -xzf "$TARBALL" -C "$TMP_EXTRACT"

    # copy file-by-file, removing any existing file/symlink at the
    # destination first so we never write THROUGH a symlink
    ( cd "$TMP_EXTRACT/data" && find . -type f ) | while read -r f; do
        rel="${f#./}"
        dest="/mnt/paperlinux-root/$rel"
        sudo mkdir -p "$(dirname "$dest")"
        sudo rm -f "$dest"
        sudo cp "$TMP_EXTRACT/data/$rel" "$dest"
    done

    rm -rf "$TMP_EXTRACT"
    sudo umount /mnt/paperlinux-root
    sudo losetup -d "$LOOPDEV"
    echo "==> Installed directly into disk image."
fi

rm -rf "$WORK_DIR"
echo "==> Done: $NAME $VERSION built and pushed to spm-packages."
