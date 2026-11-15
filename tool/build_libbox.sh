#!/bin/sh
# Builds sing-box's Android library (libbox.aar) from the pinned source commit,
# with only the features mimray uses, into android/app/libs/libbox.aar.
# Needs: Go, Android SDK + NDK (ANDROID_HOME or ~/Library/Android/sdk), JDK 17+.
set -eu
V=1.14.4
COMMIT=c005f35300ce76427dc285481ec5695f5b179cd2 # tag v1.14.4
GOMOBILE=v0.1.12                                 # matches sing-box go.mod
TAGS=with_gvisor,with_quic,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0
cd "$(dirname "$0")/.."
ROOT=$PWD
OUT=$ROOT/android/app/libs/libbox.aar

export ANDROID_HOME=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
[ -d "$ANDROID_HOME" ] || { echo "Android SDK not found (set ANDROID_HOME)" >&2; exit 1; }
# newest *complete* NDK (a half-installed one lacks meta/platforms.json)
NDK=${ANDROID_NDK_HOME:-$(for d in $(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V); do [ -f "$d/meta/platforms.json" ] && echo "$d"; done | tail -1)}
[ -d "$NDK" ] || { echo "Android NDK not found (install via SDK manager)" >&2; exit 1; }
export ANDROID_NDK_HOME=$NDK

SRC=$ROOT/build/src/sing-box
if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$ROOT/build/src"
  git clone -q --depth 1 --branch "v$V" https://github.com/SagerNet/sing-box.git "$SRC"
fi
[ "$(git -C "$SRC" rev-parse HEAD)" = "$COMMIT" ] || { echo "sing-box source is not the pinned commit" >&2; exit 1; }

export PATH="$(go env GOPATH)/bin:$PATH"
go install "github.com/sagernet/gomobile/cmd/gomobile@$GOMOBILE"
go install "github.com/sagernet/gomobile/cmd/gobind@$GOMOBILE"

mkdir -p "$(dirname "$OUT")"
cd "$SRC"
gomobile bind -v -o "$OUT" \
  -target android/arm64,android/arm,android/amd64 -androidapi 24 \
  -javapkg=io.nekohasekai -libname=box \
  -trimpath -buildvcs=false \
  -ldflags "-X github.com/sagernet/sing-box/constant.Version=$V -X runtime.godebugDefault=multipathtcp=0,tlssha1=1 -checklinkname=0 -s -w -buildid=" \
  -tags "$TAGS" ./experimental/libbox
ls -lh "$OUT"
