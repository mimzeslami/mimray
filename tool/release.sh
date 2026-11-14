#!/bin/sh
# One command: build a release and package an installer into dist/.
#   macOS -> dist/mimray-<ver>-macos.dmg  (drag to Applications)
#   Linux -> dist/mimray-<ver>-linux-<arch>.tar.gz
set -eu
cd "$(dirname "$0")/.."
V=$(grep '^version:' pubspec.yaml | cut -d' ' -f2 | cut -d+ -f1)
mkdir -p dist
case "$(uname -s)" in
Darwin)
  flutter build macos --release # core is fetched + verified by the Xcode build phase
  APP=build/macos/Build/Products/Release/mimray.app
  # ponytail: ad-hoc signature runs on this Mac; other Macs need a Developer ID + notarization.
  codesign --force --deep -s - "$APP"
  T=$(mktemp -d)
  cp -R "$APP" "$T/" && ln -s /Applications "$T/Applications"
  hdiutil create -volname mimray -srcfolder "$T" -ov -format UDZO "dist/mimray-$V-macos.dmg" >/dev/null
  rm -rf "$T"
  ;;
Linux)
  flutter build linux --release # core is fetched + verified by CMake
  B=$(echo build/linux/*/release/bundle)
  tar czf "dist/mimray-$V-linux-$(uname -m).tar.gz" -C "$B" .
  ;;
*) echo "unsupported OS"; exit 1 ;;
esac
ls -lh dist
