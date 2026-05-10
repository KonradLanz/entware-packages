#!/bin/sh
# =============================================================================
# setup-build.sh
# Vollständiges Setup-Skript: Entware-Build-Umgebung + gh-Paket bauen
#
# Voraussetzungen:
#   - Linux-Host (oder WSL2/NAS mit Docker)
#   - Git, curl
#
# Nutzung:
#   chmod +x setup-build.sh
#   ./setup-build.sh [x86_64|aarch64|arm]          (Vollbuild oder nur gh)
#   ./setup-build.sh x86_64 --wipe-toolchain       (Toolchain erzwungen neu)
# =============================================================================

set -e

ARCH="${1:-x86_64}"
WIPE_TOOLCHAIN=0
[ "${2:-}" = "--wipe-toolchain" ] && WIPE_TOOLCHAIN=1

PKG_VERSION="2.72.0"
WORKDIR="$(pwd)/entware-build"
ENTWARE_DIR="$WORKDIR/Entware"
PKGS_DIR="$WORKDIR/entware-packages"
DL_DIR="$WORKDIR/dl"
DOCKER_IMAGE="entware-builder"
CONTAINER_UID=1000
CONTAINER_GID=1000

log()  { printf '\033[1;32m[setup-build] %s\033[0m\n' "$*"; }
info() { printf '\033[1;34m[setup-build] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[FEHLER] %s\033[0m\n' "$*" >&2; exit 1; }

case "$ARCH" in
    x86_64)  CONFIG="x64-3.2.config";       GH_SUFFIX="linux_amd64"
             TOOLCHAIN_GCC="staging_dir/host/bin/x86_64-openwrt-linux-gnu-gcc" ;;
    aarch64) CONFIG="aarch64-3.10.config";  GH_SUFFIX="linux_arm64"
             TOOLCHAIN_GCC="staging_dir/host/bin/aarch64-openwrt-linux-gnu-gcc" ;;
    arm)     CONFIG="armv7-3.2.config";     GH_SUFFIX="linux_armv6"
             TOOLCHAIN_GCC="staging_dir/host/bin/arm-openwrt-linux-gnueabi-gcc" ;;
    *) die "Unbekannte Architektur: $ARCH. Erlaubt: x86_64, aarch64, arm" ;;
esac

log "Ziel-Architektur: $ARCH  Config: $CONFIG  Binary: $GH_SUFFIX"

# =============================================================================
# PHASE 1: Abhängigkeiten prüfen
# =============================================================================
log "Prüfe Abhängigkeiten ..."
command -v docker >/dev/null 2>&1 || die "Docker nicht gefunden."
command -v git    >/dev/null 2>&1 || die "git nicht gefunden."
command -v curl   >/dev/null 2>&1 || die "curl nicht gefunden."

# =============================================================================
# PHASE 2: Verzeichnisse anlegen
# =============================================================================
log "Lege Arbeitsverzeichnisse an: $WORKDIR"
mkdir -p "$ENTWARE_DIR" "$PKGS_DIR" "$DL_DIR"

# =============================================================================
# PHASE 3: Docker-Image bauen (falls noch nicht vorhanden)
# =============================================================================
if ! docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
    log "Baue Docker-Image '$DOCKER_IMAGE' ..."
    TMP_DOCKER=$(mktemp -d)
    git clone --depth=1 https://github.com/Entware/docker.git "$TMP_DOCKER/docker"
    docker build "$TMP_DOCKER/docker" --pull --tag "$DOCKER_IMAGE"
    rm -rf "$TMP_DOCKER"
else
    log "Docker-Image '$DOCKER_IMAGE' bereits vorhanden."
fi

# =============================================================================
# PHASE 4: Entware-Buildsystem klonen
# =============================================================================
if [ ! -d "$ENTWARE_DIR/.git" ]; then
    log "Klone Entware-Buildsystem ..."
    git clone --depth=1 https://github.com/Entware/Entware.git "$ENTWARE_DIR"
else
    log "Entware-Buildsystem bereits vorhanden, aktualisiere ..."
    git -C "$ENTWARE_DIR" pull --ff-only
fi

[ -f "$ENTWARE_DIR/configs/$CONFIG" ] || \
    die "Config nicht gefunden: $ENTWARE_DIR/configs/$CONFIG"

# =============================================================================
# PHASE 5: entware-packages fork klonen
# =============================================================================
if [ ! -d "$PKGS_DIR/.git" ]; then
    log "Klone entware-packages Fork ..."
    git clone https://github.com/KonradLanz/entware-packages.git "$PKGS_DIR"
    git -C "$PKGS_DIR" checkout add-gh-cli
else
    log "entware-packages Fork bereits vorhanden."
    git -C "$PKGS_DIR" fetch origin
    git -C "$PKGS_DIR" checkout add-gh-cli
    git -C "$PKGS_DIR" pull --ff-only
fi

GH_PKG_SRC="$PKGS_DIR/utils/gh"
[ -d "$GH_PKG_SRC" ] || die "gh-Paketverzeichnis nicht gefunden: $GH_PKG_SRC"

# =============================================================================
# PHASE 6: gh-Binary herunterladen & Hash verifizieren
# =============================================================================
GH_BASE_URL="https://github.com/cli/cli/releases/download/v${PKG_VERSION}"
GH_FILE="$DL_DIR/gh_${PKG_VERSION}_${GH_SUFFIX}.tar.gz"
CHECKSUMS_URL="${GH_BASE_URL}/gh_${PKG_VERSION}_checksums.txt"

if [ ! -f "$GH_FILE" ]; then
    log "Lade gh v$PKG_VERSION ($GH_SUFFIX) herunter ..."
    curl -L --progress-bar "${GH_BASE_URL}/gh_${PKG_VERSION}_${GH_SUFFIX}.tar.gz" -o "$GH_FILE"
else
    log "gh-Archiv bereits vorhanden: $GH_FILE"
fi

log "Verifiziere SHA256 via checksums.txt ..."
EXPECTED_HASH=$(curl -sL "$CHECKSUMS_URL" | grep "gh_${PKG_VERSION}_${GH_SUFFIX}.tar.gz" | awk '{print $1}')
ACTUAL_HASH=$(sha256sum "$GH_FILE" | awk '{print $1}')

[ -z "$EXPECTED_HASH" ] && die "Konnte Hash nicht aus checksums.txt lesen: $CHECKSUMS_URL"

if [ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]; then
    printf '[FEHLER] SHA256-Mismatch!\n' >&2
    printf '  Erwartet: %s\n' "$EXPECTED_HASH" >&2
    printf '  Erhalten: %s\n' "$ACTUAL_HASH" >&2
    exit 1
fi
log "SHA256 OK: $ACTUAL_HASH"

# =============================================================================
# PHASE 7: Toolchain-Zustand pruefen
# =============================================================================
TOOLCHAIN_OK=0
if [ "$WIPE_TOOLCHAIN" = "1" ]; then
    log "--wipe-toolchain: räume Toolchain auf ..."
    rm -rf "$ENTWARE_DIR/staging_dir" "$ENTWARE_DIR/build_dir" \
           "$ENTWARE_DIR/bin"         "$ENTWARE_DIR/.config"
elif [ -x "$ENTWARE_DIR/$TOOLCHAIN_GCC" ]; then
    info "Toolchain vorhanden ($TOOLCHAIN_GCC) — überspringe tools/toolchain."
    TOOLCHAIN_OK=1
else
    log "Toolchain unvollständig oder fehlend — räume Build-State auf ..."
    rm -rf "$ENTWARE_DIR/staging_dir" "$ENTWARE_DIR/build_dir" \
           "$ENTWARE_DIR/bin"         "$ENTWARE_DIR/.config"
fi

# =============================================================================
# PHASE 8: Ownership setzen
# =============================================================================
log "Setze Verzeichnis-Ownership für Container-User (UID $CONTAINER_UID) ..."
chown -R "${CONTAINER_UID}:${CONTAINER_GID}" "$WORKDIR"

CALLER_UID=$(id -u)
CALLER_GID=$(id -g)
trap 'log "Setze Ownership zurück auf ${CALLER_UID}:${CALLER_GID} ..."; chown -R "${CALLER_UID}:${CALLER_GID}" "$WORKDIR" 2>/dev/null || true' EXIT

# =============================================================================
# PHASE 9: Build im Container
# =============================================================================
if [ "$TOOLCHAIN_OK" = "1" ]; then
    info "Schnell-Build: nur gh-Paket wird neu kompiliert (~2-5 min) ..."
    BUILD_CMD='set -e
cd /home/me/Entware
echo CONFIG_PACKAGE_gh=m >> .config
make defconfig
make package/gh/clean
make package/gh/compile -j$(nproc) V=s
echo "=== Build erfolgreich ==="
find bin -name "gh_*.ipk" 2>/dev/null'
else
    log "Vollbuild: tools + toolchain + gh (~40-60 min beim ersten Mal) ..."
    BUILD_CMD='set -e
cd /home/me/Entware
cp "configs/$CONFIG" .config
echo CONFIG_PACKAGE_gh=m >> .config
make defconfig
make tools/install -j$(nproc)
make toolchain/install -j$(nproc)
make package/gh/compile -j$(nproc) V=s
echo "=== Build erfolgreich ==="
find bin -name "gh_*.ipk" 2>/dev/null'
fi

docker run --rm \
    -v "$ENTWARE_DIR":/home/me/Entware \
    -v "$DL_DIR":/home/me/Entware/dl \
    -v "$GH_PKG_SRC":/home/me/Entware/package/utils/gh \
    -e CONFIG="$CONFIG" \
    "$DOCKER_IMAGE" \
    bash -c "$BUILD_CMD"

# =============================================================================
# PHASE 10: .ipk sichern
# =============================================================================
log "Suche fertige .ipk-Datei ..."
IPK=$(find "$ENTWARE_DIR/bin" -name "gh_*.ipk" 2>/dev/null | head -1)

[ -z "$IPK" ] && die ".ipk nicht gefunden. Build fehlgeschlagen?"

cp "$IPK" "$WORKDIR/"
IPK_NAME=$(basename "$IPK")

printf '\n'
log "=========================================================="
log "Build abgeschlossen!"
log "Paket: $WORKDIR/$IPK_NAME"
printf '\n'
log "Installieren:  opkg install $WORKDIR/$IPK_NAME"
log "Testen:        gh --version"
log "=========================================================="
