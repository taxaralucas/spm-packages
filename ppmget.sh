#!/bin/bash
# ppmget — yay-style: name in, built+installed package out, nothing left behind
set -e

SPM_REPO="$HOME/spm-packages"

PKGNAME="$1"
shift || true

if [ -z "$PKGNAME" ]; then
    echo "Usage: ppmget <package-name> [ppmmake flags, default -si]"
    exit 1
fi

echo "==> Updating recipe index..."
wget -q -O "$SPM_REPO/recipe-index.txt" \
    "https://raw.githubusercontent.com/taxaralucas/spm-packages/main/recipe-index.txt"

REPO_URL=$(grep "^$PKGNAME|" "$SPM_REPO/recipe-index.txt" | cut -d'|' -f2)

if [ -z "$REPO_URL" ]; then
    echo "No recipe found for '$PKGNAME'."
    echo "Known packages:"
    cut -d'|' -f1 "$SPM_REPO/recipe-index.txt" | sed 's/^/  - /'
    exit 1
fi

TMP_CLONE="/tmp/ppmget-$PKGNAME-$$"
echo "==> Cloning $REPO_URL..."
git clone -q "$REPO_URL" "$TMP_CLONE"
cd "$TMP_CLONE"

FLAGS="${*:--si}"
echo "==> Building $PKGNAME ($FLAGS)..."
ppmmake $FLAGS

cd "$SPM_REPO"
rm -rf "$TMP_CLONE"
echo "==> Cleaned up temporary files. Nothing left on disk."
