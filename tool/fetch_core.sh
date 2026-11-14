#!/bin/sh
# Downloads the pinned sing-box core and verifies sha256 (fails closed).
#   macOS -> macos/core/sing-box  (universal: arm64 + x86_64 via lipo)
#   Linux -> linux/core/sing-box
# TARGET/DEST override, e.g. TARGET=linux-aarch64 DEST=build/core-linux
set -eu
V=1.14.4
cd "$(dirname "$0")/.."

sha() {
  case "$1" in
    darwin-arm64) echo 0d8c7f5ed5d587b0f1a5e9772a708ec3bfa4ac4c9329604b01d8d9c2ba406838 ;;
    darwin-amd64) echo eae86b9b033bba50b7c44ab719e4bfac0aca05efd28483390ed3aa510f32db25 ;;
    linux-amd64)  echo 699a1b510aa4396b2176d32d1181920399ebf1e267835da6f3b598d0f7c24968 ;;
    linux-arm64)  echo 436441f76ee2f7fe21b5b2d426d3cb261a480455a704865789ad533e4273ec26 ;;
    *) echo "unsupported platform $1" >&2; exit 1 ;;
  esac
}

# fetch <os-arch> <out-file>
fetch() {
  F=sing-box-$V-$1
  W=$(mktemp -d)
  curl -fsSL -o "$W/$F.tar.gz" "https://github.com/SagerNet/sing-box/releases/download/v$V/$F.tar.gz"
  echo "$(sha "$1")  $W/$F.tar.gz" | { shasum -a 256 -c - 2>/dev/null || sha256sum -c -; } >/dev/null \
    || { echo "sha256 mismatch for $F" >&2; rm -rf "$W"; exit 1; }
  tar xzf "$W/$F.tar.gz" -C "$W"
  mv "$W/$F/sing-box" "$2"
  rm -rf "$W"
  echo "verified $F"
}

T=${TARGET:-$(uname -s | tr A-Z a-z)-$(uname -m)}
T=$(echo "$T" | sed 's/x86_64/amd64/; s/aarch64/arm64/')
case "$T" in
  darwin-*)
    D=${DEST:-macos/core}; mkdir -p "$D"
    fetch darwin-arm64 "$D/sing-box-arm64"
    fetch darwin-amd64 "$D/sing-box-amd64"
    lipo -create -output "$D/sing-box" "$D/sing-box-arm64" "$D/sing-box-amd64"
    rm "$D/sing-box-arm64" "$D/sing-box-amd64"
    codesign --force --sign - "$D/sing-box" # lipo output is unsigned; bundle signing needs it signed
    ;;
  linux-*)
    D=${DEST:-linux/core}; mkdir -p "$D"
    fetch "$T" "$D/sing-box"
    ;;
  *) echo "unsupported platform $T" >&2; exit 1 ;;
esac
chmod +x "$D/sing-box"
