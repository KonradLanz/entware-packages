#!/usr/bin/env bash
# setup-macos-build.sh
# Sets up the Entware build environment on macOS (Apple Silicon + Intel)
# Does NOT permanently modify ~/.zshrc or PATH.
#
# Usage (once):
#   bash scripts/setup-macos-build.sh
#
# Before every build session:
#   source scripts/entware-build-env.sh
#   cd /Volumes/EntwareBuild/Entware

set -euo pipefail

IMAGE_PATH="$HOME/entware-build/entware.sparseimage"
VOLUME="/Volumes/EntwareBuild"
SIZE="20g"
ENV_SCRIPT="$(dirname "$0")/entware-build-env.sh"

echo "==> Installing required Homebrew packages..."
brew install \
    make coreutils findutils gnu-sed gawk \
    gnu-tar patch diffutils gnu-getopt \
    gettext openssl@3 python3 wget xz

# Create case-sensitive disk image if not already present
if [ ! -f "$IMAGE_PATH" ]; then
    echo "==> Creating ${SIZE} case-sensitive sparse disk image at $IMAGE_PATH..."
    mkdir -p "$(dirname "$IMAGE_PATH")"
    hdiutil create -size "$SIZE" -type SPARSE -fs "Case-sensitive HFS+" \
        -volname EntwareBuild "$IMAGE_PATH"
else
    echo "==> Disk image already exists, skipping creation."
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

# Generate the local env script (not sourced permanently anywhere)
cat > "$ENV_SCRIPT" << 'EOF'
#!/usr/bin/env bash
# entware-build-env.sh
# Activates GNU tools for the current shell session ONLY.
# Source this before building: source scripts/entware-build-env.sh
# Your PATH reverts to normal when you close the terminal.

export PATH="/opt/homebrew/opt/make/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/findutils/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/gnu-sed/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/gawk/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/gnu-tar/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/gnu-getopt/bin:$PATH"

echo "Entware build env active (this session only)."
echo "cd /Volumes/EntwareBuild/Entware to start building."
EOF
chmod +x "$ENV_SCRIPT"

echo ""
echo "==> Setup complete! For every build session:"
echo ""
echo "    source scripts/entware-build-env.sh"
echo "    cd /Volumes/EntwareBuild/Entware"
echo "    make package/rmlint/compile V=s -j\$(nproc)"
echo ""
