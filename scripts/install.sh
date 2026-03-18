#!/usr/bin/env sh
set -e

REPO="the-devops-hub/dot"
BIN_DIR="${DOT_BIN_DIR:-$HOME/.local/bin}"

# Detect OS and arch
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Linux)  os="linux" ;;
  Darwin) os="macos" ;;
  *)
    echo "Unsupported OS: $OS"
    exit 1
    ;;
esac

case "$ARCH" in
  x86_64)          arch="x86_64" ;;
  aarch64 | arm64) arch="aarch64" ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

ASSET="dot-${os}-${arch}.tar.gz"
URL="https://github.com/${REPO}/releases/latest/download/${ASSET}"

echo "Installing dot..."
echo "  Downloading $ASSET"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$URL" -o "$TMP/$ASSET"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$TMP/$ASSET" "$URL"
else
  echo "Error: curl or wget required"
  exit 1
fi

tar -xzf "$TMP/$ASSET" -C "$TMP"

mkdir -p "$BIN_DIR"
install -m755 "$TMP/dot" "$BIN_DIR/dot"

echo "  Installed to $BIN_DIR/dot"

# Warn if not in PATH
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "  Warning: $BIN_DIR is not in your PATH" ;;
esac

echo "Done. Run 'dot --help' to get started."
