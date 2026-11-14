#!/bin/sh
# mimray installer for macOS and Linux.
#   curl -fsSL https://raw.githubusercontent.com/mimzeslami/mimray/main/install.sh | sh
# Linux: installs the runtime dependencies too (apt / dnf / pacman / zypper).
# Downloads are verified against the release's SHA256SUMS.
# Env: MIMRAY_TARBALL=/path/file.tar.gz  install a local build instead of downloading
#      MIMRAY_NO_DEPS=1                  skip installing system packages
set -eu
REPO=mimzeslami/mimray
OS=$(uname -s)
ARCH=$(uname -m)

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

SUDO=""
if [ "$(id -u)" != 0 ]; then
  if command -v sudo >/dev/null; then SUDO=sudo; fi
fi

linux_deps() {
  [ "${MIMRAY_NO_DEPS:-}" = 1 ] && return
  say "Installing dependencies (GTK 3, polkit, zenity, screenshot tool)"
  if command -v apt-get >/dev/null; then
    # policykit-1 was split into pkexec on newer Debian/Ubuntu
    PK=pkexec; apt-cache show pkexec >/dev/null 2>&1 || PK=policykit-1
    $SUDO apt-get update -qq
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      libgtk-3-0 "$PK" zenity gnome-screenshot curl ca-certificates >/dev/null
  elif command -v dnf >/dev/null; then
    $SUDO dnf install -y -q gtk3 polkit zenity gnome-screenshot curl
  elif command -v pacman >/dev/null; then
    $SUDO pacman -S --needed --noconfirm gtk3 polkit zenity gnome-screenshot curl
  elif command -v zypper >/dev/null; then
    $SUDO zypper -n -q install gtk3 polkit zenity gnome-screenshot curl
  else
    warn "Unknown package manager. Please install: GTK 3, polkit (pkexec), zenity, gnome-screenshot"
  fi
}

# --- pick the release asset -------------------------------------------------
case "$OS" in
  Darwin) PAT='macos\.dmg' ;;
  Linux)
    [ "$ARCH" = x86_64 ] || die "Linux $ARCH isn't supported yet (x86_64 only). Build from source: see README."
    PAT="linux-$ARCH\.tar\.gz"
    ;;
  *) die "Unsupported OS: $OS" ;;
esac

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

if [ -n "${MIMRAY_TARBALL:-}" ]; then
  NAME=$(basename "$MIMRAY_TARBALL")
  cp "$MIMRAY_TARBALL" "$T/$NAME"
  say "Using local build $NAME"
else
  command -v curl >/dev/null || die "curl is required"
  say "Finding the latest mimray release"
  URLS=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4) \
    || die "Couldn't reach GitHub. Check your internet connection."
  URL=$(echo "$URLS" | grep -E "$PAT\$" | head -1 || true)
  SUMS=$(echo "$URLS" | grep -E '/SHA256SUMS$' | head -1 || true)
  [ -n "$URL" ] && [ -n "$SUMS" ] || die "No release for $OS/$ARCH yet."
  NAME=${URL##*/}
  say "Downloading $NAME"
  curl -fL --progress-bar -o "$T/$NAME" "$URL"
  curl -fsSL -o "$T/SHA256SUMS" "$SUMS"
  say "Verifying checksum"
  (cd "$T" && grep " $NAME\$" SHA256SUMS | { shasum -a 256 -c - 2>/dev/null || sha256sum -c -; } >/dev/null) \
    || die "Checksum mismatch, aborting (download corrupted or tampered)."
fi

# --- macOS --------------------------------------------------------------------
if [ "$OS" = Darwin ]; then
  DEST=/Applications
  [ -w "$DEST" ] || DEST="$HOME/Applications"
  mkdir -p "$DEST"
  hdiutil attach -nobrowse -quiet -mountpoint "$T/mnt" "$T/$NAME"
  rm -rf "$DEST/mimray.app"
  cp -R "$T/mnt/mimray.app" "$DEST/"
  hdiutil detach -quiet "$T/mnt"
  xattr -dr com.apple.quarantine "$DEST/mimray.app" 2>/dev/null || true
  say "Installed to $DEST/mimray.app"
  cat <<EOF

  Run it:  open it from Launchpad / Applications, or:  open -a mimray
  Then:    + Add → Add subscription, pick a server, flip the switch.
           macOS asks for your password when connecting (needed for the tunnel).

EOF
  open "$DEST/mimray.app" || true
  exit 0
fi

# --- Linux ----------------------------------------------------------------------
linux_deps

DIR="$HOME/.local/share/mimray"
rm -rf "$DIR"
mkdir -p "$DIR" "$HOME/.local/bin" "$HOME/.local/share/applications"
tar xzf "$T/$NAME" -C "$DIR"
[ -x "$DIR/mimray" ] && [ -x "$DIR/sing-box" ] || die "Package is incomplete (mimray or sing-box missing)."

ln -sf "$DIR/mimray" "$HOME/.local/bin/mimray"
# also on the system PATH so `mimray` works right away, without re-login
if [ -n "$SUDO" ] || [ "$(id -u)" = 0 ]; then
  $SUDO ln -sf "$DIR/mimray" /usr/local/bin/mimray 2>/dev/null || true
fi

cat > "$HOME/.local/share/applications/mimray.desktop" <<EOF
[Desktop Entry]
Name=mimray
GenericName=VPN Client
Comment=V2Ray / sing-box VPN client
Exec=$DIR/mimray
Icon=network-vpn
Terminal=false
Type=Application
Categories=Network;
Keywords=vpn;v2ray;proxy;vless;vmess;
EOF
command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

# sanity: the bundled core must run on this system
"$DIR/sing-box" version >/dev/null 2>&1 || warn "The VPN core couldn't start here (glibc too old or non-glibc distro like Alpine)."
command -v pkexec >/dev/null || warn "pkexec missing: install polkit, it's needed to start the tunnel."

say "Installed to $DIR"
cat <<EOF

  Run it:  type  mimray  in a terminal, or open "mimray" from your app menu.
  Then:    + Add → Add subscription (or Import from clipboard / Scan QR),
           pick a server or Auto, and flip the switch.
           You'll be asked for your password when connecting (needed for the tunnel).

  Update:  run this installer again.
  Remove:  rm -rf ~/.local/share/mimray ~/.local/bin/mimray ~/.config/mimray \\
              ~/.local/share/applications/mimray.desktop; sudo rm -f /usr/local/bin/mimray

EOF
