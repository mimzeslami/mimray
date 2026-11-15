#!/bin/sh
# Installs (or removes) the mimray helper as a root service, so connecting
# doesn't ask for a password every time. Must run as root.
#   install-helper.sh <dir containing mimray-helper and sing-box> <uid>
#   install-helper.sh --uninstall
# Files are copied to a root-owned location, so the user can't swap the binaries.
set -eu
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }

case "$(uname -s)" in
  Darwin)
    D=/Library/PrivilegedHelperTools/mimray
    P=/Library/LaunchDaemons/com.mimray.helper.plist
    SOCK=/var/run/mimray.sock
    launchctl bootout system/com.mimray.helper 2>/dev/null || true
    if [ "${1:-}" = --uninstall ]; then
      rm -rf "$D" "$P" "$SOCK"
      echo "mimray helper removed"
      exit 0
    fi
    SRC=$1 U=$2
    mkdir -p "$D"
    cp -f "$SRC/mimray-helper" "$SRC/sing-box" "$D/"
    chown -R root:wheel "$D"
    chmod 755 "$D" "$D/mimray-helper" "$D/sing-box"
    cat > "$P" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.mimray.helper</string>
  <key>ProgramArguments</key>
  <array>
    <string>$D/mimray-helper</string>
    <string>-sock</string><string>$SOCK</string>
    <string>-uid</string><string>$U</string>
    <string>-core</string><string>$D/sing-box</string>
    <string>-dir</string><string>$D/run</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>/var/log/mimray-helper.log</string>
</dict>
</plist>
EOF
    chown root:wheel "$P"
    chmod 644 "$P"
    launchctl bootstrap system "$P"
    ;;
  Linux)
    D=/usr/local/lib/mimray
    UNIT=/etc/systemd/system/mimray-helper.service
    SOCK=/run/mimray.sock
    systemctl disable --now mimray-helper 2>/dev/null || true
    if [ "${1:-}" = --uninstall ]; then
      rm -rf "$D" "$UNIT" "$SOCK" /var/lib/mimray
      systemctl daemon-reload
      echo "mimray helper removed"
      exit 0
    fi
    SRC=$1 U=$2
    install -d -m 755 "$D"
    install -m 755 "$SRC/mimray-helper" "$SRC/sing-box" "$D/"
    cat > "$UNIT" <<EOF
[Unit]
Description=mimray VPN helper
After=network.target

[Service]
ExecStart=$D/mimray-helper -sock $SOCK -uid $U -core $D/sing-box -dir /var/lib/mimray
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now mimray-helper
    ;;
  *) echo "unsupported OS" >&2; exit 1 ;;
esac

i=0
while [ ! -S "$SOCK" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
[ -S "$SOCK" ] && echo "mimray helper installed" || { echo "helper did not start" >&2; exit 1; }
