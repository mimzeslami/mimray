#!/bin/sh
# One command: build a release and package an installer into dist/.
#   macOS -> dist/mimray-<ver>-macos.dmg  (drag to Applications)
#   Linux -> dist/mimray-<ver>-linux-<arch>.tar.gz (+ .deb/.rpm with nfpm)
#   Windows (Git Bash) -> dist/mimray-<ver>-windows-x64.zip (+ -setup.exe with Inno Setup)
#   TARGET=android -> dist/mimray-<ver>-android-<abi>.apk
#
# macOS signing (optional, all via env):
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"   sign with Developer ID
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD               also notarize + staple
# Without SIGN_IDENTITY the app is ad-hoc signed (runs, but Gatekeeper warns).
set -eu
cd "$(dirname "$0")/.."
V=$(grep '^version:' pubspec.yaml | cut -d' ' -f2 | cut -d+ -f1)
mkdir -p dist
# Android (any host with the Android SDK): TARGET=android ./tool/release.sh
if [ "${TARGET:-}" = android ]; then
  [ -f android/app/libs/libbox.aar ] || ./tool/build_libbox.sh
  flutter build apk --release --split-per-abi
  for abi in arm64-v8a armeabi-v7a x86_64; do
    cp "build/app/outputs/flutter-apk/app-$abi-release.apk" "dist/mimray-$V-android-$abi.apk"
  done
  ls -lh dist
  exit 0
fi

case "$(uname -s)" in
Darwin)
  flutter build macos --release # core + helper are fetched/built by the Xcode build phase
  APP=build/macos/Build/Products/Release/mimray.app
  DMG="dist/mimray-$V-macos.dmg"
  ID=${SIGN_IDENTITY:--}
  if [ "$ID" = - ]; then
    codesign --force --deep -s - "$APP"
  else
    # inside-out: nested code first, hardened runtime + secure timestamp (notarization needs both)
    S="codesign --force --options runtime --timestamp -s"
    for f in "$APP"/Contents/MacOS/sing-box "$APP"/Contents/MacOS/mimray-helper; do
      [ -f "$f" ] && $S "$ID" "$f"
    done
    for f in "$APP"/Contents/Frameworks/*; do $S "$ID" "$f"; done
    $S "$ID" --entitlements macos/Runner/Release.entitlements "$APP"
  fi
  codesign --verify --deep --strict "$APP"
  T=$(mktemp -d)
  cp -R "$APP" "$T/" && ln -s /Applications "$T/Applications"
  hdiutil create -volname mimray -srcfolder "$T" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$T"
  if [ "$ID" != - ]; then
    codesign --force --timestamp -s "$ID" "$DMG"
    if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
      xcrun notarytool submit "$DMG" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" --wait
      xcrun stapler staple "$DMG"
      echo "notarized + stapled"
    fi
  fi
  ;;
Linux)
  flutter build linux --release # core + helper are fetched/built by CMake
  B=$(echo build/linux/*/release/bundle)
  tar czf "dist/mimray-$V-linux-$(uname -m).tar.gz" -C "$B" .
  # .deb + .rpm (needs nfpm: go install github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.48.0)
  if command -v nfpm >/dev/null; then
    sed "s|\${BUNDLE}|$PWD/$B|g; s|\${VERSION}|$V|g" packaging/nfpm.yaml > build/nfpm.yaml
    nfpm pkg -p deb -f build/nfpm.yaml -t "dist/mimray-$V-linux-x86_64.deb"
    nfpm pkg -p rpm -f build/nfpm.yaml -t "dist/mimray-$V-linux-x86_64.rpm"
  else
    echo "nfpm not found: skipping .deb/.rpm" >&2
  fi
  ;;
MINGW* | MSYS* | CYGWIN*)
  flutter build windows --release # core is fetched + verified by CMake
  B=build/windows/x64/runner/Release
  # app-local MSVC runtime, so it runs without the VC++ redistributable installed
  for d in msvcp140.dll vcruntime140.dll vcruntime140_1.dll; do cp "/c/Windows/System32/$d" "$B/"; done
  rm -f "dist/mimray-$V-windows-x64.zip"
  powershell -NoProfile -Command "Compress-Archive -Path '$(cygpath -w "$B")\\*' -DestinationPath '$(cygpath -w "$PWD/dist")\\mimray-$V-windows-x64.zip'"
  # installer (Inno Setup 6; CI installs it with choco)
  ISCC="/c/Program Files (x86)/Inno Setup 6/ISCC.exe"
  if [ -x "$ISCC" ]; then
    "$ISCC" //Q "//DVersion=$V" "//DSrc=$(cygpath -w "$PWD/$B")" "//DOut=$(cygpath -w "$PWD/dist")" "$(cygpath -w packaging/mimray.iss)"
  else
    echo "Inno Setup not found: skipping setup.exe" >&2
  fi
  ;;
*) echo "unsupported OS"; exit 1 ;;
esac
ls -lh dist
