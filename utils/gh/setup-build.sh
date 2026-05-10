#!/bin/sh
# =============================================================================
# setup-build.sh — Smart Entware package builder
#
# Detects whether a package requires a full cross-compilation toolchain
# (C/C++ source build) or can be assembled without one (prebuilt binaries,
# Go releases, Python scripts).
#
# Decision logic:
#   1. Parse the package Makefile for an empty Build/Compile stanza
#      → empty = prebuilt binary, no toolchain needed
#   2. Prebuilt path: download archive + repack as .ipk using tar only
#      (no ar needed — works on macOS, QNAP, any POSIX host)
#   3. Source path:   full Entware Docker build
#      a) Toolchain already present → make package/gh/{clean,compile}
#      b) Toolchain missing/stale   → full tools + toolchain + package build
#
# Usage:
#   ./setup-build.sh [x86_64|aarch64|arm]   auto-detect build type
#   ./setup-build.sh x86_64 --force-docker  always use Docker path
#   ./setup-build.sh x86_64 --wipe-toolchain  force full Docker rebuild
# =============================================================================

set -e

ARCH="${1:-x86_64}"
FORCE_DOCKER=0
WIPE_TOOLCHAIN=0
for arg in "$@"; do
    [ "$arg" = "--force-docker" ]    && FORCE_DOCKER=1
    [ "$arg" = "--wipe-toolchain" ]  && WIPE_TOOLCHAIN=1
done

PKG_VERSION="2.72.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKDIR="$(pwd)/entware-build"
ENTWARE_DIR="$WORKDIR/Entware"
PKGS_DIR="$WORKDIR/entware-packages"
DL_DIR="$WORKDIR/dl"
DOCKER_IMAGE="entware-builder"
CONTAINER_UID=1000
CONTAINER_GID=1000
MAKEFILE="$SCRIPT_DIR/Makefile"

log()  { printf '\033[1;32m[setup-build] %s\033[0m\n' "$*"; }
info() { printf '\033[1;34m[setup-build] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[setup-build] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[FEHLER] %s\033[0m\n' "$*" >&2; exit 1; }

# =============================================================================
# PHASE 1: Architektur-Mapping
# ENTWARE_ARCH muss exakt dem Wert in /opt/etc/opkg.conf entsprechen
# (arch <name> <prio>). Falsche Arch → "incompatible architectures".
# =============================================================================
case "$ARCH" in
    x86_64)  CONFIG="x64-3.2.config";       GH_SUFFIX="linux_amd64"
             TOOLCHAIN_GCC="staging_dir/host/bin/x86_64-openwrt-linux-gnu-gcc"
             ENTWARE_ARCH="x64-3.2" ;;
    aarch64) CONFIG="aarch64-3.10.config";  GH_SUFFIX="linux_arm64"
             TOOLCHAIN_GCC="staging_dir/host/bin/aarch64-openwrt-linux-gnu-gcc"
             ENTWARE_ARCH="aarch64-3.10" ;;
    arm)     CONFIG="armv7-3.2.config";     GH_SUFFIX="linux_armv6"
             TOOLCHAIN_GCC="staging_dir/host/bin/arm-openwrt-linux-gnueabi-gcc"
             ENTWARE_ARCH="arm-3.2" ;;
    *) die "Unknown architecture: $ARCH. Supported: x86_64, aarch64, arm" ;;
esac

log "Target arch: $ARCH  Config: $CONFIG  Binary suffix: $GH_SUFFIX  Entware arch: $ENTWARE_ARCH"

# =============================================================================
# PHASE 2: Paket-Typ erkennen (prebuilt vs. source)
# =============================================================================
detect_pkg_type() {
    [ -f "$MAKEFILE" ] || { warn "Makefile not found: $MAKEFILE"; echo "source"; return; }
    awk '
        /^define Build\/Compile/  { in_block=1; next }
        /^endef/ && in_block      { print (empty ? "prebuilt" : "source"); exit }
        in_block && /^[[:space:]]*$/ { next }
        in_block && /^[[:space:]]*#/ { next }
        in_block                  { empty=0; next }
        !in_block                 { empty=1 }
    ' "$MAKEFILE"
}

PKG_TYPE=$(detect_pkg_type)
[ "$FORCE_DOCKER" = "1" ] && PKG_TYPE="source"

info "Package type detected: $PKG_TYPE$([ "$FORCE_DOCKER" = "1" ] && echo " (forced via --force-docker)")"

# =============================================================================
# PHASE 3: Verzeichnisse + Download + SHA256
# =============================================================================
mkdir -p "$DL_DIR" "$WORKDIR"

GH_BASE_URL="https://github.com/cli/cli/releases/download/v${PKG_VERSION}"
GH_FILE="$DL_DIR/gh_${PKG_VERSION}_${GH_SUFFIX}.tar.gz"
CHECKSUMS_URL="${GH_BASE_URL}/gh_${PKG_VERSION}_checksums.txt"

if [ ! -f "$GH_FILE" ]; then
    log "Downloading gh v$PKG_VERSION ($GH_SUFFIX) ..."
    curl -L --progress-bar "${GH_BASE_URL}/gh_${PKG_VERSION}_${GH_SUFFIX}.tar.gz" -o "$GH_FILE"
else
    log "Archive already present: $GH_FILE"
fi

log "Verifying SHA256 via checksums.txt ..."
EXPECTED_HASH=$(curl -sL "$CHECKSUMS_URL" | grep "gh_${PKG_VERSION}_${GH_SUFFIX}.tar.gz" | awk '{print $1}')
ACTUAL_HASH=$(sha256sum "$GH_FILE" 2>/dev/null | awk '{print $1}')
# macOS fallback
[ -z "$ACTUAL_HASH" ] && ACTUAL_HASH=$(shasum -a 256 "$GH_FILE" | awk '{print $1}')
[ -z "$EXPECTED_HASH" ] && die "Could not read hash from checksums.txt"
if [ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]; then
    printf '[ERROR] SHA256 mismatch!\n  Expected: %s\n  Got:      %s\n' \
        "$EXPECTED_HASH" "$ACTUAL_HASH" >&2; exit 1
fi
log "SHA256 OK: $ACTUAL_HASH"

# =============================================================================
# PHASE 4a: PREBUILT-PFAD — .ipk via tar (kein ar, kein Docker)
#
# .ipk Format: tar.gz bestehend aus:
#   ./debian-binary   (enthält "2.0\n")
#   ./control.tar.gz  (control-Metadaten)
#   ./data.tar.gz     (Paket-Dateien)
#
# WICHTIG: ar wird NICHT verwendet — ar ist auf macOS (BSD ar) und QNAP
# nicht vorhanden oder inkompatibel mit dem GNU-ar-Format das opkg erwartet.
# tar czf erzeugt ein kompatibles Ergebnis.
# =============================================================================
if [ "$PKG_TYPE" = "prebuilt" ]; then
    info "Prebuilt binary detected — skipping Docker/toolchain entirely."
    info "Building .ipk via tar (no ar, no Docker) ..."

    STAGING=$(mktemp -d)
    trap 'rm -rf "$STAGING"' EXIT

    # Archiv entpacken
    tar -xzf "$GH_FILE" -C "$STAGING"
    GH_EXTRACTED=$(find "$STAGING" -maxdepth 1 -type d -name "gh_*" | head -1)
    [ -d "$GH_EXTRACTED" ] || die "Could not find extracted gh directory in $STAGING"

    # data.tar.gz
    DATA_DIR="$STAGING/data"
    mkdir -p "$DATA_DIR/opt/bin" "$DATA_DIR/opt/share/gh"
    cp "$GH_EXTRACTED/bin/gh"   "$DATA_DIR/opt/bin/gh"
    cp "$GH_EXTRACTED/LICENSE"  "$DATA_DIR/opt/share/gh/LICENSE"
    chmod 755 "$DATA_DIR/opt/bin/gh"
    tar -czf "$STAGING/data.tar.gz" -C "$DATA_DIR" .

    # control.tar.gz
    CTRL_DIR="$STAGING/control"
    mkdir -p "$CTRL_DIR"
    cat > "$CTRL_DIR/control" <<EOF
Package: gh
Version: ${PKG_VERSION}-1
Architecture: ${ENTWARE_ARCH}
Depends:
Source:
Section: utils
Status: unknown ok not-installed
Essential: no
Priority: optional
Maintainer: Konrad Lanz <konrad@greev.com>
Description: GitHub's official command line tool
 Brings pull requests, issues, releases and other
 GitHub concepts to the terminal.
EOF
    tar -czf "$STAGING/control.tar.gz" -C "$CTRL_DIR" .

    # debian-binary
    printf '2.0\n' > "$STAGING/debian-binary"

    # .ipk = tar.gz der drei Komponenten (kein ar!)
    IPK_NAME="gh_${PKG_VERSION}-1_${ENTWARE_ARCH}.ipk"
    IPK_STAGING="$STAGING/ipk"
    mkdir -p "$IPK_STAGING"
    cp "$STAGING/debian-binary"   "$IPK_STAGING/"
    cp "$STAGING/control.tar.gz" "$IPK_STAGING/"
    cp "$STAGING/data.tar.gz"    "$IPK_STAGING/"
    tar -czf "$WORKDIR/$IPK_NAME" -C "$IPK_STAGING" \
        ./debian-binary ./control.tar.gz ./data.tar.gz

    printf '\n'
    log "=========================================================="
    log "Build complete! (prebuilt path — no Docker, no ar)"
    log "Package:  $WORKDIR/$IPK_NAME"
    log "Arch:     $ENTWARE_ARCH"
    printf '\n'
    log "Install:  opkg install $WORKDIR/$IPK_NAME"
    log "Test:     gh --version"
    log "=========================================================="
    exit 0
fi

# =============================================================================
# PHASE 4b: SOURCE-PFAD — Docker + Entware-Buildsystem
# =============================================================================
log "Source package — using Docker build path."

command -v docker >/dev/null 2>&1 || die "Docker not found."
command -v git    >/dev/null 2>&1 || die "git not found."

mkdir -p "$ENTWARE_DIR" "$PKGS_DIR"

if docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
    log "Docker image '$DOCKER_IMAGE' already present — skipping build."
else
    log "Building Docker image '$DOCKER_IMAGE' (first time only) ..."
    TMP_DOCKER=$(mktemp -d)
    git clone --depth=1 https://github.com/Entware/docker.git "$TMP_DOCKER/docker"
    docker build "$TMP_DOCKER/docker" --pull --tag "$DOCKER_IMAGE"
    rm -rf "$TMP_DOCKER"
fi

if [ ! -d "$ENTWARE_DIR/.git" ]; then
    log "Cloning Entware build system ..."
    git clone --depth=1 https://github.com/Entware/Entware.git "$ENTWARE_DIR"
else
    log "Entware build system present, updating ..."
    git -C "$ENTWARE_DIR" pull --ff-only
fi
[ -f "$ENTWARE_DIR/configs/$CONFIG" ] || die "Config not found: $ENTWARE_DIR/configs/$CONFIG"

if [ ! -d "$PKGS_DIR/.git" ]; then
    log "Cloning entware-packages fork ..."
    git clone https://github.com/KonradLanz/entware-packages.git "$PKGS_DIR"
    git -C "$PKGS_DIR" checkout add-gh-cli
else
    log "entware-packages fork present."
    git -C "$PKGS_DIR" fetch origin
    git -C "$PKGS_DIR" checkout add-gh-cli
    git -C "$PKGS_DIR" pull --ff-only
fi

GH_PKG_SRC="$PKGS_DIR/utils/gh"
[ -d "$GH_PKG_SRC" ] || die "gh package directory not found: $GH_PKG_SRC"

TOOLCHAIN_OK=0
if [ "$WIPE_TOOLCHAIN" = "1" ]; then
    log "--wipe-toolchain: clearing toolchain ..."
    rm -rf "$ENTWARE_DIR/staging_dir" "$ENTWARE_DIR/build_dir" \
           "$ENTWARE_DIR/bin"         "$ENTWARE_DIR/.config"
elif [ -x "$ENTWARE_DIR/$TOOLCHAIN_GCC" ]; then
    info "Toolchain present — skipping tools/toolchain build."
    TOOLCHAIN_OK=1
else
    log "Toolchain incomplete — clearing build state ..."
    rm -rf "$ENTWARE_DIR/staging_dir" "$ENTWARE_DIR/build_dir" \
           "$ENTWARE_DIR/bin"         "$ENTWARE_DIR/.config"
fi

CALLER_UID=$(id -u); CALLER_GID=$(id -g)
chown -R "${CONTAINER_UID}:${CONTAINER_GID}" "$WORKDIR"
trap 'log "Restoring ownership ..."; chown -R "${CALLER_UID}:${CALLER_GID}" "$WORKDIR" 2>/dev/null || true' EXIT

if [ "$TOOLCHAIN_OK" = "1" ]; then
    info "Fast build: recompiling gh package only (~2-5 min) ..."
    BUILD_CMD="set -e
cd /home/me/Entware
echo CONFIG_PACKAGE_gh=m >> .config
make defconfig
make package/gh/clean
make package/gh/compile -j\$(nproc) V=s
find bin -name 'gh_*.ipk' 2>/dev/null"
else
    log "Full build: tools + toolchain + gh (~40-60 min first time) ..."
    BUILD_CMD="set -e
cd /home/me/Entware
cp configs/$CONFIG .config
echo CONFIG_PACKAGE_gh=m >> .config
make defconfig
make tools/install -j\$(nproc)
make toolchain/install -j\$(nproc)
make package/gh/compile -j\$(nproc) V=s
find bin -name 'gh_*.ipk' 2>/dev/null"
fi

docker run --rm \
    -v "$ENTWARE_DIR":/home/me/Entware \
    -v "$DL_DIR":/home/me/Entware/dl \
    -v "$GH_PKG_SRC":/home/me/Entware/package/utils/gh \
    -e CONFIG="$CONFIG" \
    "$DOCKER_IMAGE" \
    bash -c "$BUILD_CMD"

IPK=$(find "$ENTWARE_DIR/bin" -name "gh_*.ipk" 2>/dev/null | head -1)
[ -z "$IPK" ] && die ".ipk not found. Build failed?"
cp "$IPK" "$WORKDIR/"
IPK_NAME=$(basename "$IPK")

printf '\n'
log "=========================================================="
log "Build complete! (Docker path)"
log "Package: $WORKDIR/$IPK_NAME"
printf '\n'
log "Install:  opkg install $WORKDIR/$IPK_NAME"
log "Test:     gh --version"
log "=========================================================="
