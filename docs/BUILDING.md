# Building mimray

## Requirements

- Flutter **3.44.6** (what CI uses)
- [Go](https://go.dev/dl/) 1.24+ for the background helper. It's optional: without it, the app asks for a password on every connect.
- Linux: `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libayatana-appindicator3-dev`
- Android: Android SDK + NDK, JDK 17

The sing-box core is downloaded and sha256-verified automatically on the first build.

## Desktop

```sh
git clone https://github.com/mimzeslami/mimray && cd mimray
flutter run -d macos          # or: -d linux / -d windows
./tool/release.sh             # dist/: .dmg (macOS), .tar.gz + .deb + .rpm (Linux), .zip (Windows)
```

`.deb`/`.rpm` need [nfpm](https://nfpm.goreleaser.com): `go install github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.48.0`.

## Android

On Android the core runs in-process through sing-box's `libbox` library. The script builds it from the pinned source, with only the features mimray uses:

```sh
./tool/build_libbox.sh        # → android/app/libs/libbox.aar
flutter run -d <device>       # or: TARGET=android ./tool/release.sh → dist/*.apk
```

## Releases

Tagging `vX.Y.Z` on `main` makes CI build every platform and publish a GitHub release with `SHA256SUMS`.

### Signed + notarized macOS builds

CI signs and notarizes automatically once these repository secrets exist (Settings → Secrets → Actions):

| Secret | Value |
|---|---|
| `MACOS_CERT_P12` | your *Developer ID Application* certificate exported as .p12, base64: `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERT_PASSWORD` | the .p12 export password |
| `MACOS_SIGN_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID` | your Apple ID email |
| `APPLE_TEAM_ID` | 10-character team ID |
| `APPLE_APP_PASSWORD` | an [app-specific password](https://account.apple.com) |

Without them, releases are ad-hoc signed.

### Android release signing

Add the secrets `ANDROID_KEYSTORE_B64` (base64 of your .jks), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`. Keep that keystore safe: Android only installs updates signed with the same key. Without the secrets, CI builds are debug-signed.

### Package channels

- **Homebrew:** the cask lives in [mimzeslami/homebrew-mimray](https://github.com/mimzeslami/homebrew-mimray).
- **Scoop:** the manifest lives in [mimzeslami/scoop-mimray](https://github.com/mimzeslami/scoop-mimray); it updates itself from GitHub Releases.
- **winget:** manifests go to [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) as `mimzeslami.mimray`.

## The background helper

The tunnel needs root. Instead of asking for a password on every connect, `install.sh` (or ⚙ Preferences → *Install*) sets up a small root service once: a LaunchDaemon on macOS, a systemd service on Linux (`helper/`, Go). It:

- listens on a local socket that only **your user** can open (file permission + peer uid check);
- runs only its own root-owned copy of sing-box;
- accepts only the kind of config the app generates, refusing anything that could make the core read or write files (log files, certificate paths, rule sets, cache, external UI) or listen publicly;
- keeps the tunnel up exactly as long as the app's connection: if the app quits or crashes, the tunnel stops.

Remove it with ⚙ Preferences → *Remove*, or `sudo sh <app>/install-helper.sh --uninstall`.

## Community servers

"Share a server" issues are moderated:
- labelling an issue `approved` runs `.github/workflows/community.yml`, which validates the link with the app's own parser and adds it to `community/servers.json` on the `community` branch (the app reads it from there);
- labelling it `remove` takes it out again.

## Tests

```sh
flutter test                                    # parsers, config, free servers, updater, UI layout
flutter test --run-skipped --tags shots test/shots_test.dart   # screenshots → build/redesign_shots/
(cd helper && go test ./...)                    # helper: config validation + socket protocol
./tool/linux_tun_test.sh                        # Linux TUN end-to-end in Docker (traffic + DNS via a real proxy)
./tool/linux_helper_test.sh                     # root helper end-to-end in Docker
dart run tool/free_check.dart <path/to/sing-box>  # live free-server test from this machine
```
