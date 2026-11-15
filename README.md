# mimray

A simple, secure V2Ray-compatible VPN client for **macOS**, **Linux** and **Windows**, built with Flutter on top of the [sing-box](https://github.com/SagerNet/sing-box) core.

- **Protocols:** VMess, VLESS (incl. Reality / XTLS-Vision), Trojan, Shadowsocks, Hysteria2
- **Full-device TUN mode** – every app goes through the tunnel; DNS over HTTPS through the tunnel (no DNS leaks); IPv6 captured
- **Subscriptions** – several at once, switch between them, data usage + expiry shown
- **Auto mode** – picks the fastest working server and fails over by itself, without reconnecting
- **Smart Gemini routing** – if your server's country is blocked by Gemini, Gemini goes via a supported one automatically
- **Import:** clipboard, QR on screen, QR image, config file (share links, base64 subscription, v2ray/xray or sing-box JSON)
- **Export:** copy link, QR code, file – per server or per subscription
- Live speed, traffic totals, connection count, exit IP + location
- **No password on every connect** – an optional background helper (installed once) starts the tunnel for you

## Install

### macOS (Apple Silicon & Intel)

```sh
curl -fsSL https://raw.githubusercontent.com/mimzeslami/mimray/main/install.sh | sh
```

Installs `mimray.app` to `/Applications` and opens it. Or download the `.dmg` from [Releases](https://github.com/mimzeslami/mimray/releases) and drag it to Applications (first launch: right-click → Open, because the app isn't notarized).

### Linux (x86_64 — Ubuntu, Debian, Mint, Fedora, Arch, openSUSE…)

```sh
curl -fsSL https://raw.githubusercontent.com/mimzeslami/mimray/main/install.sh | sh
```

That's all — **no Flutter needed**. The installer:

- installs the system packages it needs (GTK 3, polkit, zenity, gnome-screenshot) with apt / dnf / pacman / zypper — it asks for your sudo password once
- downloads the latest release and **verifies its sha256** against the release's `SHA256SUMS`
- installs to `~/.local/share/mimray`, adds the `mimray` command and an app-menu entry

**Run it:** type `mimray` in a terminal, or open **mimray** from your app menu.
Then **+ Add → Add subscription**, pick a server (or Auto) and flip the switch — you'll be asked for your password to start the tunnel.

**Update:** run the same command again.

### Windows 10/11 (x64)

In **PowerShell**:

```powershell
irm https://raw.githubusercontent.com/mimzeslami/mimray/main/install.ps1 | iex
```

Installs to `%LOCALAPPDATA%\Programs\mimray` (no admin needed), verifies the sha256, adds Start Menu and Desktop shortcuts and opens the app.
**Run it:** open **mimray** from the Start Menu. Windows asks for permission (UAC) each time you connect — that's needed for the tunnel.
Or download the `.zip` from [Releases](https://github.com/mimzeslami/mimray/releases), unzip anywhere and run `mimray.exe`.

### Uninstall

- macOS: delete `/Applications/mimray.app` and `~/Library/Application Support/mimray`
- Windows: delete `%LOCALAPPDATA%\Programs\mimray`, `%APPDATA%\mimray` and the two `mimray` shortcuts
- Linux: `rm -rf ~/.local/share/mimray ~/.local/bin/mimray ~/.local/share/applications/mimray.desktop ~/.config/mimray; sudo rm -f /usr/local/bin/mimray`

## Usage

1. **+ Add** → *Add subscription* (paste your `https://` link), or *Import from clipboard* / *Scan QR on screen*.
2. Pick **Auto** or a server, flip the switch. The installer sets up the background helper, so there's no password prompt; without it you're asked once per connect (☰ → Settings → *Install* to add it later).
3. Right-click (or long-press, or ⋯) a server or a subscription chip for copy / QR / export / delete.
4. ☰ menu → **Settings**: connect on launch, smart Gemini routing, block QUIC, bypass LAN, DNS provider.

## Security notes

- The sing-box core is pinned to a version and **sha256-verified** at build time.
- Only `https` subscriptions are accepted (http would expose your credentials).
- Configs and saved servers are stored with `600` permissions.
- The stats API listens on `127.0.0.1` only, behind a random per-session secret.
- The core runs as root only while connected, and stops by itself within a second if the app quits or crashes.
- Servers whose link disables certificate checks are marked with ⚠.

## The background helper

The tunnel needs root. Instead of asking for your password on every connect, `install.sh` (or ☰ → Settings → *Install*)
sets up a small root service once: a LaunchDaemon on macOS, a systemd service on Linux. It is built to be safe:

- listens on a local socket only **your user** can open (file permission + peer uid check)
- runs only its own root-owned copy of sing-box
- accepts only the kind of config the app generates — anything that could make the core read/write files
  (log files, certificate paths, rule sets, cache, external UI) or listen publicly is refused
- the tunnel lives exactly as long as the app's connection; quit or crash ⇒ it stops

Remove it: ☰ → Settings → *Remove*, or `sudo sh <app>/install-helper.sh --uninstall`.

## Build from source

Requires Flutter (stable). The core is downloaded and verified automatically on first build.

```sh
git clone https://github.com/mimzeslami/mimray && cd mimray
flutter run -d macos     # or: flutter run -d linux
./tool/release.sh        # builds dist/mimray-<ver>-macos.dmg or dist/mimray-<ver>-linux-<arch>.tar.gz
```

Linux build deps: `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev`.
[Go](https://go.dev/dl/) 1.24+ builds the background helper (optional — without it the app asks for a password per connect).

### Signed + notarized macOS releases

CI signs and notarizes automatically once these repository secrets exist (Settings → Secrets → Actions):

| Secret | Value |
|---|---|
| `MACOS_CERT_P12` | your *Developer ID Application* certificate exported as .p12, base64: `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERT_PASSWORD` | the .p12 export password |
| `MACOS_SIGN_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID` | your Apple ID email |
| `APPLE_TEAM_ID` | 10-character team ID |
| `APPLE_APP_PASSWORD` | an [app-specific password](https://account.apple.com) |

Without them releases are ad-hoc signed (first launch: right-click → Open).

Tests:

```sh
flutter test                 # parsers, config, QR, UI layout
./tool/linux_tun_test.sh     # end-to-end Linux TUN test in Docker (traffic + DNS through a real proxy)
./tool/linux_helper_test.sh  # end-to-end root helper test in Docker
(cd helper && go test ./...) # helper: config validation + socket protocol
```

## Roadmap

Android build (in progress); background helper for Windows (no UAC prompt per connect).
