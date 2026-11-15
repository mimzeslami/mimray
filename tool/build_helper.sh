#!/bin/sh
# Builds the root helper (Go) next to the core:
#   macOS -> macos/core/mimray-helper (universal, ad-hoc signed)
#   Linux -> linux/core/mimray-helper
# Without Go it skips: the app still works, it just asks for a password per connect.
set -eu
cd "$(dirname "$0")/.."
if ! command -v go >/dev/null; then
  echo "warning: Go not found, skipping mimray-helper (install Go to build it)" >&2
  exit 0
fi
cd helper
case "$(uname -s)" in
  Darwin)
    OUT=../macos/core
    mkdir -p "$OUT"
    CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags=-s -o "$OUT/mimray-helper-arm64" .
    CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -trimpath -ldflags=-s -o "$OUT/mimray-helper-amd64" .
    lipo -create -output "$OUT/mimray-helper" "$OUT/mimray-helper-arm64" "$OUT/mimray-helper-amd64"
    rm "$OUT/mimray-helper-arm64" "$OUT/mimray-helper-amd64"
    codesign --force --sign - "$OUT/mimray-helper"
    ;;
  Linux)
    OUT=../linux/core
    mkdir -p "$OUT"
    CGO_ENABLED=0 go build -trimpath -ldflags=-s -o "$OUT/mimray-helper" .
    ;;
esac
cp install-helper.sh "$OUT/install-helper.sh"
chmod +x "$OUT/install-helper.sh"
echo "built $OUT/mimray-helper"
