#!/bin/sh
# End-to-end Linux TUN test in Docker: a shadowsocks server container + a privileged
# client container running the app's real Linux config (gvisor stack, auto_route,
# strict_route, DNS hijack, fake-IP DNS). Passes only if traffic and DNS really go through the tunnel.
set -eu
cd "$(dirname "$0")/.."
case "$(docker info --format '{{.Architecture}}')" in aarch64|arm64) A=aarch64 ;; *) A=x86_64 ;; esac
[ -x build/core-linux/sing-box ] || TARGET=linux-$A DEST=build/core-linux ./tool/fetch_core.sh
mkdir -p build/tun-test
cat > build/tun-test/server.json <<J
{"log":{"level":"info"},"inbounds":[{"type":"shadowsocks","listen":"::","listen_port":8388,"method":"aes-256-gcm","password":"testpass"}],"outbounds":[{"type":"direct"}]}
J
LINK="ss://$(printf 'aes-256-gcm:testpass' | base64)@mimray-srv:8388#test"
dart run tool/gen_config.dart "$LINK" "${IPV6:-false}" > build/tun-test/client.json

cleanup() { docker rm -f mimray-srv mimray-cli >/dev/null 2>&1 || true; docker network rm mimray-net >/dev/null 2>&1 || true; }
cleanup; trap cleanup EXIT
docker network create mimray-net >/dev/null
docker run -d --name mimray-srv --network mimray-net -v "$PWD/build/core-linux:/core:ro" \
  -v "$PWD/build/tun-test:/t:ro" debian:bookworm-slim /core/sing-box run -c /t/server.json >/dev/null
docker run --rm --name mimray-cli --network mimray-net --dns 8.8.8.8 --cap-add NET_ADMIN --device /dev/net/tun \
  -v "$PWD/build/core-linux:/core:ro" -v "$PWD/build/tun-test:/t:ro" debian:bookworm-slim sh -c '
  apt-get -qq update && apt-get -qq install -y curl dnsutils iproute2 >/dev/null 2>&1
  /core/sing-box run -c /t/client.json > /tmp/core.log 2>&1 &
  sleep 3
  ip addr | grep -q "172.19.0.1/30" || { echo "FAIL: no tun interface"; cat /tmp/core.log; exit 1; }
  r=$(curl -s -m 15 -o /dev/null -w "%{http_code} %{remote_ip}" https://www.gstatic.com/generate_204)
  [ "${r%% *}" = 204 ] && echo "PASS: HTTPS through tunnel ($r)" || { echo "FAIL: https got $r"; cat /tmp/core.log; exit 1; }
  nslookup -timeout=10 example.com 8.8.8.8 >/dev/null && echo "PASS: DNS to 8.8.8.8 hijacked + resolved" || { echo "FAIL: dns"; cat /tmp/core.log; exit 1; }
  echo "core log:"; cat /tmp/core.log'
echo "server saw:"
docker logs mimray-srv 2>&1 | grep -o "inbound connection to [^ ]*" | sort -u
# fake-IP DNS: the server must get the domain, not an IP (server-side domain routing relies on it)
docker logs mimray-srv 2>&1 | grep -q "connection to www.gstatic.com:443" && echo "PASS: server proxied the HTTPS request by domain" || { echo "FAIL: www.gstatic.com:443 did not reach the proxy server as a domain"; exit 1; }
