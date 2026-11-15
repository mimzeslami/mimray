<p align="center">
  <img src="linux/mimray.png" width="96" alt="mimray logo">
</p>

<h1 align="center">mimray</h1>

<p align="center">
  A simple, secure V2Ray-compatible VPN client for <b>macOS</b>, <b>Windows</b>, <b>Linux</b> and <b>Android</b>,<br>
  built on the <a href="https://github.com/SagerNet/sing-box">sing-box</a> core.
</p>

<p align="center">
  <a href="https://github.com/mimzeslami/mimray/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/mimzeslami/mimray?color=2F7BFF"></a>
  <a href="https://github.com/mimzeslami/mimray/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/mimzeslami/mimray/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/mimzeslami/mimray/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/mimzeslami/mimray/total?color=3DDC97"></a>
</p>

---

## Features

- **Every major protocol:** VLESS (incl. Reality / XTLS-Vision), VMess, Trojan, Shadowsocks, Hysteria2
- **Whole-device tunnel:** every app goes through the VPN; DNS-over-HTTPS inside the tunnel (no DNS leaks); IPv6 captured
- **Subscriptions:** several at once, with data usage and expiry; servers grouped by country, favorites and recent
- **Auto mode:** picks the fastest working server and fails over by itself, without reconnecting
- **Free servers (opt-in):** public free servers and servers shared by the community, tested from *your* device so only working ones are shown
- **Smart Gemini routing:** if your server's country is blocked by Gemini, Gemini traffic goes through a supported one
- **Import & export:** clipboard, QR on screen, QR image, config file (share links, base64 subscriptions, v2ray/xray or sing-box JSON); export as link, QR or file
- **Live stats:** speed, traffic, connections, exit IP and location
- **No password on every connect:** an optional background helper, installed once (macOS, Linux)
- **Updates itself:** new versions are offered in the app and verified against the release checksums before installing

## Install

| Platform | Recommended | Other ways |
|---|---|---|
| **macOS** 11+ (Apple Silicon & Intel) | [Homebrew](#macos) | [Install script](#macos), [.dmg](https://github.com/mimzeslami/mimray/releases/latest) |
| **Windows** 10/11 (x64) | [Scoop](#windows) or the [install script](#windows) | winget ([pending review](https://github.com/microsoft/winget-pkgs/pull/480738)), [.zip](https://github.com/mimzeslami/mimray/releases/latest) |
| **Linux** (x86_64) | `.deb` / `.rpm` from [Releases](https://github.com/mimzeslami/mimray/releases/latest) | [Install script](#linux), [.tar.gz](https://github.com/mimzeslami/mimray/releases/latest) |
| **Android** 7.0+ | `.apk` from [Releases](https://github.com/mimzeslami/mimray/releases/latest) | [Obtainium](#android) (auto-updates from GitHub) |

No Flutter, Go or developer tools are needed to install. Every download is checked against the release's `SHA256SUMS`.

### macOS

With [Homebrew](https://brew.sh):

```sh
brew tap mimzeslami/mimray
brew trust mimzeslami/mimray     # Homebrew 7+ asks you to trust third-party taps once
brew install --cask mimray
```

Or the install script, which also sets up the background helper (no password on every connect):

```sh
curl -fsSL https://raw.githubusercontent.com/mimzeslami/mimray/main/install.sh | sh
```

Or download the `.dmg` and drag mimray to Applications. The app isn't notarized yet, so the first time, right-click it → **Open**.

### Windows

With [Scoop](https://scoop.sh):

```powershell
scoop bucket add mimray https://github.com/mimzeslami/scoop-mimray
scoop install mimray
```

Or in PowerShell, the install script (installs to `%LOCALAPPDATA%\Programs\mimray`, adds Start Menu and Desktop shortcuts, no admin needed):

```powershell
irm https://raw.githubusercontent.com/mimzeslami/mimray/main/install.ps1 | iex
```

With winget, once [the submission](https://github.com/microsoft/winget-pkgs/pull/480738) is approved by Microsoft:

```powershell
winget install mimray
```

Windows asks for permission (UAC) when you connect, which the tunnel needs.

### Linux

**Debian, Ubuntu, Mint, Pop!_OS:** download `mimray-<version>-linux-x86_64.deb`, then

```sh
sudo apt install ./mimray-*-linux-x86_64.deb
```

**Fedora, openSUSE, RHEL:** download `mimray-<version>-linux-x86_64.rpm`, then

```sh
sudo dnf install ./mimray-*-linux-x86_64.rpm
```

**Any distro (including Arch)**, with the install script. It installs the needed packages with apt / dnf / pacman / zypper and sets up the background helper:

```sh
curl -fsSL https://raw.githubusercontent.com/mimzeslami/mimray/main/install.sh | sh
```

Run it from your app menu or with `mimray`. The tray icon needs AppIndicator support (on GNOME, the *AppIndicator* extension).

### Android

Download the APK for your phone from [Releases](https://github.com/mimzeslami/mimray/releases/latest): `arm64-v8a` for almost all phones, `armeabi-v7a` for very old ones, `x86_64` for emulators and Chromebooks. Open it and allow *Install unknown apps* when asked. On first connect, Android asks once to allow the VPN; tap **OK**.

To get updates automatically, add `https://github.com/mimzeslami/mimray` in [Obtainium](https://github.com/ImranR98/Obtainium). mimray also offers new versions inside the app.

## Getting started

1. Tap **+** and paste your `https://` subscription link, or import from the clipboard, a QR code or a config file.
2. Pick **Auto** or a location and tap the power button.
3. ☆ pins a location to **Favorites**; **Recent** shows the ones you used last. Right-click, long-press or ⋯ on a location for QR, copy, export and delete.
4. The bar at the bottom opens your subscription: usage, switching, updating and export.
5. ⚙ **Preferences**: connect on launch, smart Gemini routing, block QUIC, bypass LAN, DNS provider, the background helper and the core log.

### Free servers

The **Free** tab is off until you turn it on. It lists public free servers from [barry-far/V2ray-Config](https://github.com/barry-far/V2ray-Config) and servers shared by mimray users, **tested from your own device** so only working ones are shown (desktop runs a real connection test through each server; Android checks that they're reachable).

> ⚠️ Free servers are run by people you don't know. They can see and log traffic that isn't encrypted, and some exist precisely to watch the people who use them. Don't use them for logins, banking or anything sensitive. Your own server or a subscription you trust is always safer.

**Share your server:** in the Free tab, *Share your server* opens a GitHub form. Shared servers appear in everyone's app after the maintainer reviews and approves them.

## Uninstall

| Installed with | Remove with |
|---|---|
| Homebrew | `brew uninstall --cask mimray` |
| winget / Scoop | `winget uninstall mimray` / `scoop uninstall mimray` |
| .deb / .rpm | `sudo apt remove mimray` / `sudo dnf remove mimray` |
| macOS install script or .dmg | delete `/Applications/mimray.app` and `~/Library/Application Support/mimray` |
| Windows install script | delete `%LOCALAPPDATA%\Programs\mimray`, `%APPDATA%\mimray` and the two shortcuts |
| Linux install script | `rm -rf ~/.local/share/mimray ~/.local/bin/mimray ~/.local/share/applications/mimray.desktop ~/.config/mimray; sudo rm -f /usr/local/bin/mimray` |

If you installed the background helper, remove it first: ⚙ Preferences → **Remove**.

## Security

- **Pinned core:** the sing-box core is pinned to one version and its sha256 is verified at build time. Releases and in-app updates are verified against `SHA256SUMS`.
- **Subscriptions over https only**, since plain http would expose your credentials.
- **Private files:** your servers and settings are readable only by your user account.
- **Local-only stats:** the stats API listens on `127.0.0.1` behind a random per-session secret.
- **Short-lived root:** the core runs as root only while connected, and stops within a second if the app quits or crashes. Servers whose link disables certificate checks are marked ⚠.
- **The background helper** (installed once) listens on a socket only your user can open. It runs only its own root-owned copy of sing-box, and refuses any config that could read or write files or listen publicly. Details are in [docs/BUILDING.md](docs/BUILDING.md#the-background-helper).

Found a security problem? Please open a private [security advisory](https://github.com/mimzeslami/mimray/security/advisories/new) instead of a public issue.

## Contributing

Bug reports, fixes and features are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). To build from source, sign releases or run the end-to-end tests, see [docs/BUILDING.md](docs/BUILDING.md).

## Roadmap

- Camera QR scanning and file import/export on Android
- Background helper on Windows (no UAC prompt per connect)
- Notarized macOS builds

## License

mimray is free software under the [GNU General Public License v3.0 or later](LICENSE) (`GPL-3.0-or-later`), the same license as the bundled [sing-box](https://github.com/SagerNet/sing-box) core. You can use, study, share and change it; versions you distribute must stay under the same license. Fonts: Geist (SIL OFL 1.1, see `assets/fonts/OFL.txt`).
