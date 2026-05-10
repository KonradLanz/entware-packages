#!/bin/sh
# =============================================================================
# setup-build.sh
# Vollständiges Setup-Skript: Entware-Build-Umgebung + gh-Paket bauen
#
# Voraussetzungen:
#   - Linux-Host (oder WSL2) mit Docker
#   - Git
#   - Internetzugang
#
# Nutzung:
#   chmod +x setup-build.sh
#   ./setup-build.sh [x86_64|aarch64|arm]   (default: x86_64)
# =============================================================================

set -e

ARCH="${1:-x86_64}"
PKG_VERSION="2.72.0"
WORKDIR="$(pwd)/entware-build"
ENTWARE_DIR="$WORKDIR/Entware"
PKGS_DIR="$WORKDIR/entware-packages"
DOCKER_IMAGE="entware-builder"
DOCKER_VOLUME="entware-home"

log() { echo "\033[1;32m[setup-build] $*\033[0m"; }
die() { echo "\033[1;31m[FEHLER] $*\033[0m" >&2; exit 1; }

# --- Architektur-spezifische Einstellungen ---
case "$ARCH" in
    x86_64)  CONFIG="x86-64.config"; GH_SUFFIX="linux_amd64"  ;;
    aarch64) CONFIG="aarch64.config"; GH_SUFFIX="linux_arm64"  ;;
    arm)     CONFIG="armv7.config";   GH_SUFFIX="linux_armv6"  ;;
    *) die "Unbekannte Architektur: $ARCH. Erlaubt: x86_64, aarch64, arm" ;;
esac

log "Ziel-Architektur: $ARCH ($GH_SUFFIX)"

# =============================================================================
# PHASE 1: Abhängigkeiten prüfen
# =============================================================================
log "Prüfe Abhängigkeiten ..."
command -v docker >/dev/null 2>&1 || die "Docker nicht gefunden. Bitte installieren: https://docs.docker.com/get-docker/"
command -v git    >/dev/null 2>&1 || die "git nicht gefunden."
command -v curl   >/dev/null 2>&1 || die "curl nicht gefunden."

# =============================================================================
# PHASE 2: Verzeichnisse anlegen
# =============================================================================
log "Lege Arbeitsverzeichnis an: $WORKDIR"
mkdir -p "$WORKDIR"

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

docker volume inspect "$DOCKER_VOLUME" >/dev/null 2>&1 || \
    docker volume create "$DOCKER_VOLUME"

# =============================================================================
# PHASE 4: Entware-Buildsystem klonen (falls nicht vorhanden)
# =============================================================================
if [ ! -d "$ENTWARE_DIR/.git" ]; then
    log "Klone Entware-Buildsystem ..."
    git clone --depth=1 https://github.com/Entware/Entware.git "$ENTWARE_DIR"
else
    log "Entware-Buildsystem bereits vorhanden, aktualisiere ..."
    git -C "$ENTWARE_DIR" pull --ff-only
fi

# =============================================================================
# PHASE 5: entware-packages fork klonen (falls nicht vorhanden)
# =============================================================================
if [ ! -d "$PKGS_DIR/.git" ]; then
    log "Klone entware-packages Fork ..."
    git clone https://github.com/KonradLanz/entware-packages.git "$PKGS_DIR"
    git -C "$PKGS_DIR" checkout add-gh-cli
else
    log "entware-packages Fork bereits vorhanden."
    git -C "$PKGS_DIR" checkout add-gh-cli
    git -C "$PKGS_DIR" pull --ff-only
fi

# =============================================================================
# PHASE 6: SHA256-Hash für das gh-Binary ermitteln & ins Makefile eintragen
# =============================================================================
log "Ermittle SHA256-Hash für gh v$PKG_VERSION ($GH_SUFFIX) ..."
GH_URL="https://github.com/cli/cli/releases/download/v${PKG_VERSION}/gh_${PKG_VERSION}_${GH_SUFFIX}.tar.gz"
GH_HASH=$(curl -sL "$GH_URL" | sha256sum | cut -d' ' -f1)

if [ -z "$GH_HASH" ]; then
    die "SHA256-Hash konnte nicht ermittelt werden. URL: $GH_URL"
fi

log "SHA256: $GH_HASH"

# Hash im Makefile ersetzen
MAKEFILE="$PKGS_DIR/utils/gh/Makefile"
sed -i "s|PKG_HASH:=skip|PKG_HASH:=$GH_HASH|g" "$MAKEFILE"
log "Makefile aktualisiert: $MAKEFILE"

# Aktuellen PKG_VERSION im Makefile prüfen / aktualisieren
sed -i "s|PKG_VERSION:=.*|PKG_VERSION:=$PKG_VERSION|" "$MAKEFILE"

# =============================================================================
# PHASE 7: Pakete im Entware-Buildsystem verlinken
# =============================================================================
log "Verlinke gh-Paket ins Buildsystem ..."
mkdir -p "$ENTWARE_DIR/package/utils"
ln -snf "$PKGS_DIR/utils/gh" "$ENTWARE_DIR/package/utils/gh"

# =============================================================================
# PHASE 8: Paket bauen (im Docker-Container)
# =============================================================================
log "Starte Build im Docker-Container ..."

docker run --rm \
    --mount source="$DOCKER_VOLUME",target=/home/me \
    -v "$ENTWARE_DIR":/home/me/Entware \
    -e ARCH="$ARCH" \
    -e CONFIG="$CONFIG" \
    "$DOCKER_IMAGE" \
    /bin/sh -c "
        set -e
        cd /home/me/Entware

        # Toolchain nur beim ersten Mal bauen
        if [ ! -d staging_dir ]; then
            cp configs/\$CONFIG .config
            echo 'CONFIG_PACKAGE_gh=m' >> .config
            make defconfig
            make tools/install -j\$(nproc)
            make toolchain/install -j\$(nproc)
        else
            echo 'CONFIG_PACKAGE_gh=m' >> .config
            make defconfig
        fi

        make package/gh/compile -j\$(nproc) V=s
        echo '=== Build erfolgreich ==='
        find bin -name 'gh_*.ipk' 2>/dev/null
    "

# =============================================================================
# PHASE 9: .ipk-Datei sichern
# =============================================================================
log "Suche fertige .ipk-Datei ..."
IPK=$(find "$ENTWARE_DIR/bin" -name "gh_*.ipk" 2>/dev/null | head -1)

if [ -z "$IPK" ]; then
    die ".ipk nicht gefunden. Build fehlgeschlagen?"
fi

cp "$IPK" "$WORKDIR/"
log ""
log "=================================================="
log "Build abgeschlossen!"
log "Paket: $WORKDIR/$(basename $IPK)"
log ""
log "Auf QNAP installieren:"
log "  scp $WORKDIR/$(basename $IPK) admin@NAS-IP:/tmp/"
log "  ssh admin@NAS-IP 'opkg install /tmp/$(basename $IPK)'"
log ""
log "Oder direkt testen:"
log "  opkg install $WORKDIR/$(basename $IPK)"
log "  gh --version"
log "  gh auth login --with-token <<< 'ghp_DEIN_TOKEN'"
log "=========================================================="
