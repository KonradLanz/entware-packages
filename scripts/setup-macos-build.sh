#!/usr/bin/env bash
# setup-macos-build.sh
# Sets up the Entware build environment on macOS (Apple Silicon + Intel)
# Usage: bash scripts/setup-macos-build.sh

set -euo pipefail

INAGE_PATH="$HOME/entware-build/entware.sparseimage"
VOLUME="/Volumes/EntwareBuild"
SIZE="20g"

echo "==> Installing required Homebrew packages..."
brew install \
    make coreutils findutils gnu-sed gawk \
    gnu-tar patch diffutils gnu-getopt \
    gettext openssl@3 python3 wget xz

echo "==> Setting up GNU tools PATH..."
export PATH="/opt/homebrew/opt/make/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/findutils/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/gnu-sed/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/gawk/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/gnu-tar/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/gnu-getopt/bin:$PATH"

# Persist to ~/.zshrc if not already there
if ! grep -q 'Entware build' ~/.zshrc 2>/dev/null; then
    echo "==> Adding GNU tools to ~/.zshrc..."
    cat >> ~/.zshrc << 'EOF'

# GNU tools for Entware build (added by setup-macos-build.sh)
export PATH="/opt/homebrew/opt/make/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/findutils/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/gnu-sed/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/gawk/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/gnu-tar/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/gnu-getopt/bin:$PATH"
EOF
fi

# Create case-sensitive disk image if not already present
if [ ! -f "$IMAGE_PATH" ]; then
    echo "==> Creating ${SIZE} case-sensitive sparse disk image at $IMAGE_PATH..."
    mkdir -p "$(dirname "$IMAGE_PATH")"
    hdiutil create -size "$SIZE" -type SPARSE -fs "Case-sensitive HFS+" \
        -volname EntwareBuild "$IMAGE_PATH"
else
    echo "==> Disk image already exists at $IMAGE_PATH, skipping creation."
fi

# Mount if not already mounted
if ! mount | grep -q "$VOLUME"; then
    echo "==> Mounting disk image..."
    hdiutil attach "$IMAGE_PATH"
else
    echo "==> Disk image already mounted at $VOLUME."
fi

# Clone Entware SDK if not present
if [ ! -d "$VOLUME/Entware" ]; then
    echo "==> Cloning Entware SDK into $VOLUME/Entware..."
    git clone https://github.com/Entware/Entware.git "$VOLUME/Entware"
else
    echo "==> Entware SDK already present, skipping clone."
fi

echo ""
echo "==> Setup complete! Now run:"
echo ""
echo "    cd $VOLUME/Entware"
echo "    cp configs/x64-3.2.config .config"
echo "    make defconfig"
echo "    echo 'src-git konrad https://github.com/KonradLanz/entware-packages.git;add-rmlint' >> feeds.conf"
echo "    make package/feeds/update"
echo "    make package/feeds/install"
echo "    make package/rmlint/compile V=s -j\$(nproc)"
echo ""
