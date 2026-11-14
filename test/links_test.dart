import "dart:convert";
import "dart:io";
import 'package:flutter_test/flutter_test.dart';
import 'package:mimray/core.dart';
import 'package:image/image.dart' as img;
import 'package:mimray/links.dart';
import 'package:mimray/native.dart';

void main() {
  test('parses common share links', () {
    final vmess =
        'vmess://${base64.encode(utf8.encode(jsonEncode({'ps': 'vm', 'add': 'a.com', 'port': '443', 'id': 'u1', 'aid': '0', 'net': 'ws', 'host': 'h.com', 'path': '/ws?ed=2048', 'tls': 'tls'})))}';
    final links = [
      vmess,
      'vless://u2@b.com:443?security=reality&sni=x.com&fp=chrome&pbk=j_x32y8W5KyfJ3jNTjWUq0tUiG4kxEMzLp9T4M5zeDU&sid=ab&flow=xtls-rprx-vision&type=tcp#VL%20R',
      'trojan://p%40ss@[2001:db8::1]:443?type=grpc&serviceName=g#TJ',
      'ss://${base64.encode(utf8.encode('aes-256-gcm:pw'))}@c.com:8388#SS',
      'hy2://pw@d.com:443?sni=d.com&obfs=salamander&obfs-password=o&insecure=1#HY',
      'vless://u@e.com:443?type=xhttp#unsupported',
    ];
    final sub = parseSubscription(base64.encode(utf8.encode(links.join('\n'))));
    expect(sub.length, 5);
    final o = {for (final s in sub) s.outbound['type']: s};
    expect(o['vmess']!.outbound['transport'], {
      'type': 'ws',
      'headers': {'Host': 'h.com'},
      'max_early_data': 2048,
      'early_data_header_name': 'Sec-WebSocket-Protocol',
      'path': '/ws',
    });
    expect(o['vless']!.name, 'VL R');
    expect(o['vless']!.outbound['tls']['reality'], {
      'enabled': true,
      'public_key': 'j_x32y8W5KyfJ3jNTjWUq0tUiG4kxEMzLp9T4M5zeDU',
      'short_id': 'ab',
    });
    expect(o['trojan']!.outbound['password'], 'p@ss');
    expect(o['trojan']!.host, '2001:db8::1');
    expect(o['shadowsocks']!.outbound['method'], 'aes-256-gcm');
    expect(o['hysteria2']!.name, '⚠ HY');
    File('build/check_auto.json').writeAsStringSync(
      jsonEncode(
        buildConfig(
          [for (final s in sub) s.outbound],
          api: '127.0.0.1:9090',
          secret: 'x',
        ),
      ),
    );
    // dump configs for `sing-box check`
    for (final s in sub) {
      File('build/check_${s.outbound['type']}.json').writeAsStringSync(
        jsonEncode(
          buildConfig(
            [s.outbound],
            ai: sub.first.outbound,
            api: '127.0.0.1:9090',
            secret: 'x',
          ),
        ),
      );
      File('build/linux_${s.outbound['type']}.json').writeAsStringSync(
        jsonEncode(buildConfig([s.outbound], stack: 'gvisor')),
      );
    }
  });
  test('imports xray and sing-box JSON configs', () {
    final xray = jsonEncode({
      'outbounds': [
        {
          'tag': 'x1',
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': 'r.com',
                'port': 443,
                'users': [
                  {'id': 'U', 'flow': 'xtls-rprx-vision'},
                ],
              },
            ],
          },
          'streamSettings': {
            'network': 'ws',
            'security': 'tls',
            'tlsSettings': {'serverName': 's.com', 'fingerprint': 'chrome'},
            'wsSettings': {
              'path': '/p',
              'headers': {'Host': 'h.com'},
            },
          },
        },
        {'protocol': 'freedom', 'tag': 'direct'},
      ],
    });
    final x = parseImport(xray);
    expect(x.length, 1);
    expect(x.first.name, 'x1');
    expect(x.first.outbound['tls']['server_name'], 's.com');
    expect(x.first.outbound['transport'], {
      'type': 'ws',
      'headers': {'Host': 'h.com'},
      'path': '/p',
    });
    final sb = parseImport(
      jsonEncode({
        'type': 'trojan',
        'tag': 'sb',
        'server': 't.com',
        'server_port': 443,
        'password': 'p',
      }),
    );
    expect(sb.single.name, 'sb');
    expect(
      parseImport('vless://u@e.com:443#n').single.link,
      'vless://u@e.com:443#n',
    );
    File('build/check_json.json').writeAsStringSync(
      jsonEncode(buildConfig([x.first.outbound, sb.first.outbound])),
    );
  });

  test('QR round trip (encode -> png -> decode)', () async {
    const text = 'vless://u@e.com:443?security=tls#round trip';
    final m = qrMatrix(text);
    const k = 8, q = 4; // module px, quiet zone
    final n = m.length;
    final im = img.Image(width: (n + 2 * q) * k, height: (n + 2 * q) * k);
    img.fill(im, color: img.ColorRgb8(255, 255, 255));
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (m[y][x]) {
          img.fillRect(
            im,
            x1: (x + q) * k,
            y1: (y + q) * k,
            x2: (x + q + 1) * k - 1,
            y2: (y + q + 1) * k - 1,
            color: img.ColorRgb8(0, 0, 0),
          );
        }
      }
    }
    File('build/qr.png').writeAsBytesSync(img.encodePng(im));
    expect(await decodeQrFile('build/qr.png'), text);
  });
}
