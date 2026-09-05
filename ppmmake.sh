#!/bin/bash
# ppmmake — makepkg-style builder
# Modes:
#   ppmmake -si                  (existing: read ./PKGBUILD in cwd)
#   ppmmake <github-url> [-si]   (new: auto-fetch, auto-detect, auto-build)
set -e

SPM_REPO="$HOME/spm-packages"

url_mode() {
    local URL="$1"
    shift

    # normalize a github.com/.../releases/tag/vX.Y.Z or plain repo URL
    # into owner/repo + a tag if present
    local OWNER REPO TAG
    if [[ "$URL" =~ github\.com/([^/]+)/([^/]+)/releases/tag/([^/]+) ]]; then
        OWNER="${BASH_REMATCH[1]}"
        REPO="${BASH_REMATCH[2]}"
        TAG="${BASH_REMATCH[3]}"
    elif [[ "$URL" =~ github\.com/([^/]+)/([^/]+) ]]; then
        OWNER="${BASH_REMATCH[1]}"
        REPO="${BASH_REMATCH[2]%.git}"
        TAG=""
    else
        echo "Only github.com URLs are supported for auto mode right now."
        exit 1
    fi

    local NAME="$REPO"
    local WORK_DIR="/tmp/ppmmake-auto-$NAME-$$"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

    local TARBALL_URL
    if [ -n "$TAG" ]; then
        TARBALL_URL="https://github.com/$OWNER/$REPO/archive/refs/tags/$TAG.tar.gz"
        NAME_VERSION="${TAG#v}"
    else
        TARBALL_URL="https://github.com/$OWNER/$REPO/archive/refs/heads/master.tar.gz"
        NAME_VERSION="latest"
    fi

    echo "==> Fetching $TARBALL_URL"
    wget -q "$TARBALL_URL" -O source.tar.gz || {
        echo "Could not fetch tarball. Trying 'main' branch instead of 'master'..."
        TARBALL_URL="https://github.com/$OWNER/$REPO/archive/refs/heads/main.tar.gz"
        wget -q "$TARBALL_URL" -O source.tar.gz
    }

    mkdir src
    tar -xf source.tar.gz -C src --strip-components=1
    cd src

    echo "==> Detecting project type for '$NAME'..."

    # Case 1: single-script project (e.g. neofetch) — a script matching the
    # repo name at the repo root, with a shebang, no build system files
    if [ -f "$NAME" ] && head -1 "$NAME" | grep -q '^#!' \
       ; then

        local SHEBANG=$(head -1 "$NAME")
        echo "==> Detected: standalone script ($SHEBANG)"

        WORK_DIR_OUT="$WORK_DIR/output-binary"
        cp "$NAME" "$WORK_DIR_OUT"
        chmod +x "$WORK_DIR_OUT"

        DESC="Auto-packaged script from $OWNER/$REPO"
        INSTALL_PATH="/usr/bin/$NAME"
        DEPS=""
        if echo "$SHEBANG" | grep -q bash; then
            DEPS="bash"
        fi

        echo "==> Packaging..."
        cd "$SPM_REPO"
        ./mkpkg.sh "$NAME" "$NAME_VERSION" "$INSTALL_PATH" "$WORK_DIR_OUT" "$DESC" "$DEPS"

        do_install_step "$NAME" "$NAME_VERSION" "$INSTALL_PATH" "$WORK_DIR_OUT" "$@"

    # Case 2: cmake project
    elif [ -f "CMakeLists.txt" ]; then
        echo "==> Detected: CMake project — attempting auto-build"
        echo "    (this is a best guess; complex projects may need a hand-written PKGBUILD)"
        mkdir -p build && cd build
        cmake .. -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=gcc \
            -DBUILD_SHARED_LIBS=OFF -DCMAKE_EXE_LINKER_FLAGS="-static" 2>&1 | tail -30
        make -j2 2>&1 | tail -60
        BIN=$(find . -maxdepth 1 -type f -executable | head -1)
        if [ -z "$BIN" ]; then
            echo "ERROR: could not find a built binary. Auto-build failed."
            echo "Write a manual PKGBUILD for this project instead."
            exit 1
        fi
        WORK_DIR_OUT="$WORK_DIR/output-binary"
        cp "$BIN" "$WORK_DIR_OUT"
        cd "$SPM_REPO"
        ./mkpkg.sh "$NAME" "$NAME_VERSION" "/usr/bin/$NAME" "$WORK_DIR_OUT" "Auto-built from $OWNER/$REPO" ""
        do_install_step "$NAME" "$NAME_VERSION" "/usr/bin/$NAME" "$WORK_DIR_OUT" "$@"

    # Case 3: configure/make project
    elif [ -f "configure" ] || [ -f "configure.ac" ]; then
        echo "==> Detected: autotools project — attempting auto-build"
        [ -f configure ] || autoreconf -fi
        CC=gcc ./configure --disable-shared 2>&1 | tail -30
        make LDFLAGS="-static" -j2 2>&1 | tail -60
        BIN=$(find . -maxdepth 1 -type f -executable ! -name "configure" | head -1)
        if [ -z "$BIN" ]; then
            echo "ERROR: could not find a built binary. Auto-build failed."
            exit 1
        fi
        WORK_DIR_OUT="$WORK_DIR/output-binary"
        cp "$BIN" "$WORK_DIR_OUT"
        cd "$SPM_REPO"
        ./mkpkg.sh "$NAME" "$NAME_VERSION" "/usr/bin/$NAME" "$WORK_DIR_OUT" "Auto-built from $OWNER/$REPO" ""
        do_install_step "$NAME" "$NAME_VERSION" "/usr/bin/$NAME" "$WORK_DIR_OUT" "$@"

    else
        echo "Could not auto-detect a build method for this project."
        echo "Clone it and write a PKGBUILD by hand instead:"
        echo "  git clone https://github.com/$OWNER/$REPO.git"
        exit 1
    fi

    rm -rf "$WORK_DIR"
}

do_install_step() {
    local NAME="$1" VERSION="$2" INSTALL_PATH="$3" OUT_BINARY="$4"
    shift 4
    for arg in "$@"; do
        if [[ "$arg" == *i* ]]; then
            echo "==> Installing into VM disk image..."
            sudo losetup -fP ~/paperlinux/paperlinux-root.img
            LOOPDEV=$(sudo losetup -j ~/paperlinux/paperlinux-root.img | cut -d: -f1)
            sudo mount "${LOOPDEV}p1" /mnt/paperlinux-root
            DEST="/mnt/paperlinux-root${INSTALL_PATH}"
            sudo mkdir -p "$(dirname "$DEST")"
            sudo rm -f "$DEST"
            sudo cp "$OUT_BINARY" "$DEST"
            sudo chmod +x "$DEST"
            sudo umount /mnt/paperlinux-root
            sudo losetup -d "$LOOPDEV"
            echo "==> Installed."
            break
        fi
    done
}

# --- entrypoint ---
if [[ "$1" == http* ]]; then
    url_mode "$@"
    exit 0
fi

# classic PKGBUILD mode (unchanged)
if [ ! -f "./PKGBUILD" ]; then
    echo "No PKGBUILD found in current directory, and no URL given."
    echo "Usage: ppmmake <github-url> [-si]"
    echo "       ppmmake -si   (reads ./PKGBUILD)"
    exit 1
fi

source ./PKGBUILD
echo "==> Building $NAME $VERSION"
WORK_DIR="/tmp/ppmmake-$NAME-$$"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
wget -q "$SOURCE_URL" -O source.tar.gz
mkdir src
tar -xf source.tar.gz -C src --strip-components=1
cd src
export OUT_BINARY="$WORK_DIR/output-binary"
build
cd "$SPM_REPO"
./mkpkg.sh "$NAME" "$VERSION" "$INSTALL_PATH" "$OUT_BINARY" "$DESC" "$DEPS"
do_install_step "$NAME" "$VERSION" "$INSTALL_PATH" "$OUT_BINARY" "$@"
rm -rf "$WORK_DIR"
