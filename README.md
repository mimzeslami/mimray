# mimray

A simple, secure V2Ray-compatible VPN client for **macOS** and **Linux**, built with Flutter on top of the [sing-box](https://github.com/SagerNet/sing-box) core.

- **Protocols:** VMess, VLESS (incl. Reality / XTLS-Vision), Trojan, Shadowsocks, Hysteria2
- **Full-device TUN mode** – every app goes through the tunnel; DNS over HTTPS through the tunnel (no DNS leaks); IPv6 captured
- **Subscriptions** – several at once, switch between them, data usage + expiry shown
- **Auto mode** – picks the fastest working server and fails over by itself, without reconnecting
- **Smart Gemini routing** – if your server's country is blocked by Gemini, Gemini goes via a supported one automatically
- **Import:** clipboard, QR on screen, QR image, config file (share links, base64 subscription, v2ray/xray or sing-box JSON)
- **Export:** copy link, QR code, file – per server or per subscription
- Live speed, traffic totals, connection count, exit IP + location

## Install

### macOS (Apple Silicon & Intel)

```sh
curl -fsSL https://raw.githubusercontent.com/mimzeslami/mimray/main/install.sh | sh
```

Installs `mimray.app` to `/Applications` and opens it. Or download the `.dmg` from [Releases](https://github.com/mimzeslami/mimray/releases) and drag it to Applications (first launch: right-click → Open, because the app isn't notarized).

### Linux (x86_64, glibc distros: Ubuntu, Debian, Fedora, Arch, Mint…)

```sh
curl -fsSL https://raw.githubusercontent.com/mimzeslami/mimray/main/install.sh | sh
```

Installs to `~/.local/share/mimray`, adds a `mimray` command and an app-menu entry. Requirements:

```sh
# Debian/Ubuntu
sudo apt install libgtk-3-0 policykit-1 zenity gnome-screenshot
# Fedora
sudo dnf install gtk3 polkit zenity gnome-screenshot
# Arch
sudo pacman -S gtk3 polkit zenity gnome-screenshot
```

`polkit` (pkexec) is required to start the tunnel; `zenity` and a screenshot tool are only needed for file dialogs and QR scanning.

The installer verifies the download against the release's `SHA256SUMS` before installing.

### Uninstall

- macOS: delete `/Applications/mimray.app` and `~/Library/Application Support/mimray`
- Linux: `rm -rf ~/.local/share/mimray ~/.local/bin/mimray ~/.local/share/applications/mimray.desktop ~/.config/mimray`

## Usage

1. **+ Add** → *Add subscription* (paste your `https://` link), or *Import from clipboard* / *Scan QR on screen*.
2. Pick **Auto** or a server, flip the switch. Your password is asked once per connect (the TUN interface needs admin rights).
3. Right-click (or long-press, or ⋯) a server or a subscription chip for copy / QR / export / delete.
4. ☰ menu → **Settings**: connect on launch, smart Gemini routing, block QUIC, bypass LAN, DNS provider.

## Security notes

- The sing-box core is pinned to a version and **sha256-verified** at build time.
- Only `https` subscriptions are accepted (http would expose your credentials).
- Configs and saved servers are stored with `600` permissions.
- The stats API listens on `127.0.0.1` only, behind a random per-session secret.
- The core runs as root only while connected, and stops by itself within a second if the app quits or crashes.
- Servers whose link disables certificate checks are marked with ⚠.

## Build from source

Requires Flutter (stable). The core is downloaded and verified automatically on first build.

```sh
git clone https://github.com/mimzeslami/mimray && cd mimray
flutter run -d macos     # or: flutter run -d linux
./tool/release.sh        # builds dist/mimray-<ver>-macos.dmg or dist/mimray-<ver>-linux-<arch>.tar.gz
```

Linux build deps: `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev`.

Tests:

```sh
flutter test                 # parsers, config, QR, UI layout
./tool/linux_tun_test.sh     # end-to-end Linux TUN test in Docker (traffic + DNS through a real proxy)
```

## Roadmap

Windows and Android builds, macOS helper to avoid the per-connect password prompt, notarized macOS builds.
