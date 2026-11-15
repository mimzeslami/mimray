#!/bin/sh
# End-to-end test of the root helper on Linux (Docker): a normal user starts the
# VPN through the helper (no password), traffic goes through a real proxy server,
# and closing the connection tears the tunnel down. Also checks that a malicious
# config (root file write) is refused.
set -eu
cd "$(dirname "$0")/.."
case "$(docker info --format '{{.Architecture}}')" in aarch64|arm64) A=aarch64; GA=arm64 ;; *) A=x86_64; GA=amd64 ;; esac
[ -x build/core-linux/sing-box ] || TARGET=linux-$A DEST=build/core-linux ./tool/fetch_core.sh
(cd helper && CGO_ENABLED=0 GOOS=linux GOARCH=$GA go build -o ../build/core-linux/mimray-helper .)
mkdir -p build/helper-test
cat > build/helper-test/server.json <<J
{"log":{"level":"info"},"inbounds":[{"type":"shadowsocks","listen":"::","listen_port":8388,"method":"aes-256-gcm","password":"testpass"}],"outbounds":[{"type":"direct"}]}
J
LINK="ss://$(printf 'aes-256-gcm:testpass' | base64)@mimray-srv:8388#test"
dart run tool/gen_config.dart "$LINK" false > build/helper-test/client.json
python3 -I -c 'import json,sys; c=json.load(open(sys.argv[1])); print(json.dumps({"cmd":"start","config":c}))' build/helper-test/client.json > build/helper-test/start.json
python3 -I -c 'import json,sys; c=json.load(open(sys.argv[1])); c["log"]["output"]="/etc/evil"; print(json.dumps({"cmd":"start","config":c}))' build/helper-test/client.json > build/helper-test/evil.json

cleanup() { docker rm -f mimray-srv >/dev/null 2>&1 || true; docker network rm mimray-net >/dev/null 2>&1 || true; }
cleanup; trap cleanup EXIT
docker network create mimray-net >/dev/null
docker run -d --name mimray-srv --network mimray-net -v "$PWD/build/core-linux:/core:ro" \
  -v "$PWD/build/helper-test:/t:ro" debian:bookworm-slim /core/sing-box run -c /t/server.json >/dev/null
docker run --rm --network mimray-net --cap-add NET_ADMIN --device /dev/net/tun \
  -v "$PWD/build/core-linux:/core:ro" -v "$PWD/build/helper-test:/t:ro" debian:bookworm-slim sh -c '
  set -e
  apt-get -qq update && apt-get -qq install -y curl iproute2 netcat-openbsd >/dev/null 2>&1
  useradd -m alice
  mkdir -p /var/lib/mimray
  /core/mimray-helper -sock /run/mimray.sock -uid $(id -u alice) -core /core/sing-box -dir /var/lib/mimray 2>/tmp/helper.log &
  sleep 1
  ls -l /run/mimray.sock

  # 1. malicious config is refused
  r=$(su alice -c "nc -U -q 2 /run/mimray.sock < /t/evil.json" || true)
  echo "$r" | grep -q "config rejected" && echo "PASS: malicious config refused" || { echo "FAIL: $r"; exit 1; }
  [ ! -e /etc/evil ] || { echo "FAIL: root file written"; exit 1; }

  # 2. root cannot be impersonated: another user is refused
  useradd -m mallory
  r=$(su mallory -c "echo {\\\"cmd\\\":\\\"version\\\"} | nc -U -q 1 /run/mimray.sock" 2>&1 || true)
  echo "$r" | grep -qiE "not allowed|denied" && echo "PASS: other user refused ($r)" || { echo "FAIL: other user got: $r"; exit 1; }

  # 3. alice connects with no password, session held open for 8s
  su alice -c "(cat /t/start.json; sleep 8) | nc -q 0 -U /run/mimray.sock > /tmp/session.log" &
  sleep 3
  ip addr | grep -q "172.19.0.1/30" && echo "PASS: tunnel up via helper" || { echo "FAIL: no tunnel"; cat /tmp/session.log /tmp/helper.log; exit 1; }
  code=$(curl -s -m 10 -o /dev/null -w "%{http_code}" https://www.gstatic.com/generate_204)
  [ "$code" = 204 ] && echo "PASS: HTTPS through tunnel" || { echo "FAIL: https $code"; exit 1; }

  # 4. alice disconnects (session ends) -> tunnel must be torn down
  sleep 7
  if ip addr | grep -q "172.19.0.1/30"; then echo "FAIL: tunnel still up after disconnect"; exit 1; else echo "PASS: tunnel removed after disconnect"; fi
  grep -q "\"exit\"" /tmp/session.log && echo "PASS: helper reported exit"
'
echo "server saw:"; docker logs mimray-srv 2>&1 | grep -o "inbound connection to [^ ]*" | sort -u
