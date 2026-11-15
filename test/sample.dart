// Sample state for UI tests and screenshots (Home(demo: ...)).

const _nodes = [
  ('🇩🇪 Frankfurt', 'vless', 'fra1.nova.net', 42),
  ('🇩🇪 Berlin', 'vmess', 'ber.nova.net', 58),
  ('🇳🇱 Amsterdam', 'trojan', 'ams.nova.net', 38),
  ('🇳🇱 Rotterdam', 'vless', 'rtm.nova.net', 61),
  ('🇫🇮 Helsinki', 'hysteria2', 'hel.nova.net', 71),
  ('🇬🇧 London', 'vless', 'lon.nova.net', 64),
  ('🇹🇷 Istanbul', 'shadowsocks', 'ist.nova.net', 96),
  ('🇺🇸 New York', 'vless', 'nyc.nova.net', 142),
  ('🇺🇸 Los Angeles', 'vmess', 'lax.nova.net', 188),
  ('🇺🇸 Miami', 'trojan', 'mia.nova.net', null),
  ('🇯🇵 Tokyo', 'trojan', 'tyo.nova.net', 231),
  ('🇸🇬 Singapore', 'vless', 'sg.nova.net', 384),
  ('Backup node', 'shadowsocks', 'backup.example.org', 120),
];

Map<String, dynamic> _server((String, String, String, int?) n) {
  final (name, type, host, _) = n;
  return {
    'name': name,
    'link':
        '$type://00000000-0000-0000-0000-000000000000@$host:443#${Uri.encodeComponent(name)}',
    'outbound': {
      'type': type,
      'server': host,
      'server_port': 443,
      if (type == 'vless')
        'tls': {
          'enabled': true,
          'reality': {'enabled': true},
        },
      if (type == 'vmess') ...{
        'transport': {'type': 'ws'},
        'tls': {'enabled': true},
      },
      if (type == 'trojan') 'transport': {'type': 'grpc'},
    },
  };
}

String id(int i) => '${_nodes[i].$2}://${_nodes[i].$3}:443';

/// [phase]: off | connecting | on. [sel]: -1 = Auto.
Map<String, dynamic> demo({
  bool empty = false,
  String phase = 'off',
  int sel = -1,
  String tab = 'all',
  List<String> expanded = const ['DE'],
  String os = 'mac',
  int nav = 0,
  String view = 'main',
  bool helper = true,
}) {
  final exp =
      DateTime.now()
          .add(const Duration(days: 18, hours: 2))
          .millisecondsSinceEpoch ~/
      1000;
  const gb = 1024 * 1024 * 1024;
  return {
    'subs': empty
        ? []
        : [
            {
              'name': 'Nova Premium',
              'src': 'https://sub.nova.net/u/a8d1c0ffee77e2b93f9a',
              'servers': [for (final n in _nodes) _server(n)],
              'usage': {
                'upload': (1.2 * gb).round(),
                'download': (11.2 * gb).round(),
                'total': 50 * gb,
                'expire': exp,
              },
            },
            {
              'name': 'Local',
              'src': '',
              'servers': [for (final n in _nodes.take(3)) _server(n)],
            },
          ],
    'cur': 0,
    'sel': sel,
    'favorites': [id(0), id(2), id(4)],
    'recent': [id(7), id(1), id(6)],
    '_phase': phase,
    '_pings': [for (final n in _nodes) n.$4],
    '_stats': [
      96 * 1024 * 1024,
      (1.3 * gb).round(),
      380 * 1024,
      (4.2 * 1024 * 1024).round(),
      23,
      0,
    ],
    '_ip': {'ip': '185.212.44.9', 'city': 'Frankfurt', 'country': 'DE'},
    '_helper': helper ? '0.3.0' : null,
    '_helperBundled': true,
    '_log': [
      '+0000 2026-11-15 14:02:11 INFO network: updated default interface en0',
      '+0000 2026-11-15 14:02:11 INFO inbound/tun[tun-in]: started at utun7',
      '+0000 2026-11-15 14:02:11 INFO outbound/urltest[proxy]: selected fra1.nova.net 42ms',
      '+0000 2026-11-15 14:02:12 INFO dns: exchanged A gemini.google.com via ai',
      '+0000 2026-11-15 14:02:14 WARN outbound/trojan[s9]: dial mia.nova.net: i/o timeout',
      '+0000 2026-11-15 14:02:14 INFO router: sniffed protocol tls domain github.com',
      '+0000 2026-11-15 14:02:19 INFO outbound/urltest[proxy]: keep fra1.nova.net',
      '+0000 2026-11-15 14:02:41 INFO router: reject udp 443 (block QUIC)',
    ].join('\n'),
    '_tab': tab,
    '_expanded': expanded,
    '_os': os,
    '_nav': nav,
    '_view': view,
  };
}
