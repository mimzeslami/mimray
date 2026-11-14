#!/bin/sh
# mimray installer (macOS + Linux). Verifies the download against the release's SHA256SUMS.
#   curl -fsSL https://raw.githubusercontent.com/mimzeslami/mimray/main/install.sh | sh
set -eu
REPO=mimzeslami/mimray
OS=$(uname -s)
ARCH=$(uname -m)
case "$OS" in
  Darwin) PAT='macos\.dmg' ;;
  Linux) PAT="linux-$ARCH\.tar\.gz" ;;
  *) echo "Unsupported OS: $OS"; exit 1 ;;
esac

echo "==> Finding latest mimray release"
URLS=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4)
URL=$(echo "$URLS" | grep -E "$PAT\$" | head -1)
SUMS=$(echo "$URLS" | grep -E '/SHA256SUMS$' | head -1)
[ -n "$URL" ] || { echo "No release for $OS/$ARCH yet. Build from source: see README."; exit 1; }
NAME=${URL##*/}

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
echo "==> Downloading $NAME"
curl -fL --progress-bar -o "$T/$NAME" "$URL"
curl -fsSL -o "$T/SHA256SUMS" "$SUMS"
echo "==> Verifying sha256"
( cd "$T" && grep " $NAME\$" SHA256SUMS | { shasum -a 256 -c - 2>/dev/null || sha256sum -c -; } ) \
  || { echo "Checksum mismatch, aborting."; exit 1; }

if [ "$OS" = Darwin ]; then
  DEST=/Applications
  [ -w "$DEST" ] || DEST="$HOME/Applications"
  mkdir -p "$DEST"
  hdiutil attach -nobrowse -quiet -mountpoint "$T/mnt" "$T/$NAME"
  rm -rf "$DEST/mimray.app"
  cp -R "$T/mnt/mimray.app" "$DEST/"
  hdiutil detach -quiet "$T/mnt"
  xattr -dr com.apple.quarantine "$DEST/mimray.app" 2>/dev/null || true
  echo "==> Installed to $DEST/mimray.app"
  open "$DEST/mimray.app"
else
  DIR="$HOME/.local/share/mimray"
  rm -rf "$DIR" && mkdir -p "$DIR" "$HOME/.local/bin" "$HOME/.local/share/applications"
  tar xzf "$T/$NAME" -C "$DIR"
  ln -sf "$DIR/mimray" "$HOME/.local/bin/mimray"
  cat > "$HOME/.local/share/applications/mimray.desktop" <<D
[Desktop Entry]
Name=mimray
Comment=V2Ray / sing-box VPN client
Exec=$DIR/mimray
Icon=network-vpn
Terminal=false
Type=Application
Categories=Network;
D
  echo "==> Installed to $DIR (command: mimray, also in your app menu)"
  command -v pkexec >/dev/null || echo "!! pkexec not found: install polkit (needed to start the tunnel)"
  command -v zenity >/dev/null || command -v kdialog >/dev/null || echo "   tip: install zenity for file import/export dialogs"
  command -v gnome-screenshot >/dev/null || command -v spectacle >/dev/null || command -v flameshot >/dev/null || command -v grim >/dev/null \
    || echo "   tip: install gnome-screenshot (or spectacle/flameshot/grim+slurp) for 'Scan QR on screen'"
fi
