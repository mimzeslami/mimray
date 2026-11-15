# Contributing to mimray

Thanks for helping! Bug reports, fixes and features are all welcome.

## How changes get in

`main` is protected: nobody pushes to it directly. Every change goes through a pull request that
**passes CI** and is **reviewed and merged by the maintainer**.

1. Fork the repo and create a branch: `git checkout -b fix/short-description`
2. Make your change (small, focused PRs get reviewed fastest)
3. Check it locally:
   ```sh
   flutter analyze
   flutter test
   ./tool/linux_tun_test.sh   # if you touched lib/core.dart or tunnel/config code (needs Docker)
   (cd helper && go test ./...)  # if you touched helper/
   ```
4. Open a pull request against `main` and fill in the template

For anything big (new protocol, new platform, UI redesign) please open an issue first so we can agree on the approach.

## Dev setup

Flutter **3.44.6** (what CI uses) and Go 1.24+ (for the root helper). The sing-box core is downloaded and sha256-verified on first build.

```sh
flutter run -d macos   # or -d linux
```

Linux build deps: `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libayatana-appindicator3-dev`.

## Code layout

| File | What it does |
|------|--------------|
| `lib/links.dart` | share links, subscriptions, JSON configs → sing-box outbounds |
| `lib/core.dart` | builds the sing-box config, runs the core as root, stats |
| `lib/native.dart` | QR encode/decode, native file dialogs, screen capture |
| `lib/main.dart` | the UI |
| `helper/` | root helper service (Go): config validation, socket protocol |
| `tool/` | core download, helper build, release packaging, Linux e2e tests |

## Rules of thumb

- **Security first:** never weaken TLS checks, never log credentials, keep the core pinned + checksum-verified.
- Keep dependencies minimal; prefer the standard library and built-in OS tools.
- New parsing or config logic gets a test in `test/`.
- Never paste real server links, UUIDs or subscription URLs in issues, PRs or tests.
