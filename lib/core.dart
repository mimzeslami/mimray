// Builds the sing-box TUN config and runs the core as root (macOS admin prompt).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

final _home = Platform.environment['HOME'];
final appDir = Platform.isMacOS
    ? '$_home/Library/Application Support/mimray'
    : '${Platform.environment['XDG_CONFIG_HOME'] ?? '$_home/.config'}/mimray';

/// Gemini / Google AI endpoints. Google gates these by exit-IP country.
const aiDomains = [
  'gemini.google.com',
  'gemini.google',
  'bard.google.com',
  'aistudio.google.com',
  'makersuite.google.com',
  'ai.google.dev',
  'notebooklm.google.com',
  'labs.google',
  'deepmind.google',
  'generativelanguage.googleapis.com',
  'alkalimakersuite-pa.clients6.google.com',
  'proactivebackend-pa.googleapis.com',
  'robinfrontend-pa.googleapis.com',
  'geller-pa.googleapis.com',
];

/// User-tunable connection options (Settings screen).
class Settings {
  String dns; // DoH resolver IP, queried through the tunnel
  bool blockQuic, bypassLan, smartAi, autoConnect;
  Settings({
    this.dns = '1.1.1.1',
    this.blockQuic = true,
    this.bypassLan = true,
    this.smartAi = true,
    this.autoConnect = false,
  });
  Map<String, dynamic> toJson() => {
    'dns': dns,
    'blockQuic': blockQuic,
    'bypassLan': bypassLan,
    'smartAi': smartAi,
    'autoConnect': autoConnect,
  };
  factory Settings.fromJson(Map? j) => j == null
      ? Settings()
      : Settings(
          dns: j['dns'] ?? '1.1.1.1',
          blockQuic: j['blockQuic'] ?? true,
          bypassLan: j['bypassLan'] ?? true,
          smartAi: j['smartAi'] ?? true,
          autoConnect: j['autoConnect'] ?? false,
        );
}

/// DoH resolvers whose TLS certs cover their IPs (no bootstrap lookup needed).
const dnsChoices = {
  '1.1.1.1': 'Cloudflare',
  '8.8.8.8': 'Google',
  '9.9.9.9': 'Quad9',
};

/// [ai] = optional separate server for [aiDomains] (e.g. one in a Gemini-supported country).
/// [proxies]: one server, or several -> 'urltest' group that keeps using the
/// lowest-latency working one and fails over by itself (no tunnel restart).
/// [api] = "127.0.0.1:port" for sing-box's local stats API, guarded by [secret].
/// [stack]: 'mixed' (fast) on macOS; 'gvisor' on Linux, where ufw/firewalld can drop
/// the system stack's TCP. [ipv6]: false when the host has IPv6 disabled (tun setup fails).
Map<String, dynamic> buildConfig(
  List<Map<String, dynamic>> proxies, {
  Map<String, dynamic>? ai,
  String? api,
  String? secret,
  String stack = 'mixed',
  bool ipv6 = true,
  Settings? opt,
}) => _build(proxies, ai, api, secret, stack, ipv6, opt ?? Settings());

Map<String, dynamic> _build(
  List<Map<String, dynamic>> proxies,
  Map<String, dynamic>? ai,
  String? api,
  String? secret,
  String stack,
  bool ipv6,
  Settings opt,
) => {
  'log': {'level': 'warn'},
  'dns': {
    'servers': [
      // all DNS goes over the tunnel via DoH -> no DNS leaks
      {'type': 'https', 'tag': 'remote', 'server': opt.dns, 'detour': 'proxy'},
      {'type': 'local', 'tag': 'local'},
    ],
    'final': 'remote',
    'strategy': 'ipv4_only',
  },
  'inbounds': [
    {
      'type': 'tun',
      'tag': 'tun-in',
      // v6 address too, so IPv6 is captured instead of leaking around the tunnel
      'address': ['172.19.0.1/30', if (ipv6) 'fdfe:dcba:9876::1/126'],
      'auto_route': true,
      'strict_route': true,
      'stack': stack,
    },
  ],
  'outbounds': [
    if (proxies.length == 1)
      {...proxies.first, 'tag': 'proxy'}
    else ...[
      for (var i = 0; i < proxies.length; i++) {...proxies[i], 'tag': 's$i'},
      {
        'type': 'urltest',
        'tag': 'proxy',
        'outbounds': [for (var i = 0; i < proxies.length; i++) 's$i'],
        'url': 'https://www.gstatic.com/generate_204',
        'interval': '1m',
        'tolerance': 50,
      },
    ],
    if (ai != null) {...ai, 'tag': 'ai'},
    {'type': 'direct', 'tag': 'direct'},
  ],
  'route': {
    'rules': [
      {'action': 'sniff'},
      {'protocol': 'dns', 'action': 'hijack-dns'},
      // Block QUIC: browsers fall back to TCP, which proxies far more reliably
      // (fixes Google sites half-loading on servers that drop UDP).
      if (opt.blockQuic) {'network': 'udp', 'port': 443, 'action': 'reject'},
      if (ai != null) {'domain_suffix': aiDomains, 'outbound': 'ai'},
      if (opt.bypassLan) {'ip_is_private': true, 'outbound': 'direct'},
    ],
    'auto_detect_interface': true,
    'default_domain_resolver':
        'local', // resolves the proxy server's own hostname
    'final': 'proxy',
  },
  if (api != null)
    'experimental': {
      'clash_api': {'external_controller': api, 'secret': secret},
    },
};

bool _linuxV6() {
  try {
    return File(
          '/proc/sys/net/ipv6/conf/all/disable_ipv6',
        ).readAsStringSync().trim() !=
        '1';
  } catch (_) {
    return false;
  }
}

String _sq(String s) => "'${s.replaceAll("'", "'\\''")}'";

class Stats {
  final int up, down, upRate, downRate, conns;
  final int? active; // index into the auto pool currently in use
  const Stats(
    this.up,
    this.down,
    this.upRate,
    this.downRate,
    this.conns,
    this.active,
  );
}

class Core {
  Process? _p;
  String? _api, _secret;
  bool get running => _p != null;
  String get log => '$appDir/core.log';
  String get _stop => '$appDir/stop';

  /// Starts the tunnel. [onExit] fires when the core stops for any reason
  /// (user stop, password prompt cancelled, core crash).
  Future<void> start(
    List<Map<String, dynamic>> proxies,
    void Function(int code) onExit, {
    Map<String, dynamic>? ai,
    Settings? opt,
  }) async {
    await Directory(appDir).create(recursive: true);
    final cfg = File('$appDir/config.json');
    final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _api = '127.0.0.1:${sock.port}';
    await sock.close();
    final r = Random.secure();
    _secret = base64Url.encode(List.generate(24, (_) => r.nextInt(256)));
    await cfg.writeAsString(
      jsonEncode(
        buildConfig(
          proxies,
          ai: ai,
          opt: opt,
          api: _api,
          secret: _secret,
          stack: Platform.isLinux ? 'gvisor' : 'mixed',
          ipv6: !Platform.isLinux || _linuxV6(),
        ),
      ),
    );
    await Process.run('chmod', ['600', cfg.path]); // contains credentials
    final stop = File(_stop);
    if (await stop.exists()) await stop.delete();

    final bin = '${File(Platform.resolvedExecutable).parent.path}/sing-box';
    // Root shell: run core, kill it when the app dies or the stop file appears,
    // so a crashed UI never leaves the network hijacked.
    final sh =
        '${_sq(bin)} run -c ${_sq(cfg.path)} > ${_sq(log)} 2>&1 & p=\$!; '
        'while kill -0 \$p 2>/dev/null && kill -0 $pid 2>/dev/null && [ ! -e ${_sq(_stop)} ]; '
        'do sleep 1; done; kill \$p 2>/dev/null; wait \$p';
    final Process p;
    if (Platform.isMacOS) {
      final as = sh.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      p = await Process.start('osascript', [
        '-e',
        'do shell script "$as" with administrator privileges',
      ]);
    } else {
      p = await Process.start('pkexec', [
        '/bin/sh',
        '-c',
        sh,
      ]); // polkit password dialog
    }
    _p = p;
    p.exitCode.then((c) {
      _p = null;
      onExit(c);
    });
  }

  Future<void> stop() => File(_stop).writeAsString('');

  int _lastUp = 0, _lastDown = 0;

  /// Totals + per-second rates from the core. Null until the core is up.
  /// Call once a second.
  Future<Stats?> stats() async {
    if (_p == null) return null;
    try {
      final auth = {'Authorization': 'Bearer $_secret'};
      final j = await _get('http://$_api/connections', auth);
      int? active;
      try {
        final now = (await _get('http://$_api/proxies/proxy', auth))['now'];
        if (now is String && now.startsWith('s')) {
          active = int.parse(now.substring(1));
        }
      } catch (_) {} // single server: no group
      final up = j['uploadTotal'] as int, down = j['downloadTotal'] as int;
      final s = Stats(
        up,
        down,
        max(0, up - _lastUp),
        max(0, down - _lastDown),
        (j['connections'] as List?)?.length ?? 0,
        active,
      );
      _lastUp = up;
      _lastDown = down;
      return s;
    } catch (_) {
      _lastUp = _lastDown = 0;
      return null;
    }
  }

  Future<String> logTail([int n = 5]) async {
    try {
      final l = await File(log).readAsLines();
      return l.skip(l.length > n ? l.length - n : 0).join('\n');
    } catch (_) {
      return '';
    }
  }
}

/// TCP connect latency in ms (null = unreachable).
// ponytail: TCP handshake only; hy2 is UDP so it shows unreachable. Real URL test via core if needed.
Future<int?> ping(String host, int port) async {
  final sw = Stopwatch()..start();
  try {
    (await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 3),
    )).destroy();
    return sw.elapsedMilliseconds;
  } catch (_) {
    return null;
  }
}

/// GET a JSON url. Through the tunnel when connected.
Future<Map<String, dynamic>> _get(
  String url, [
  Map<String, String> headers = const {},
]) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await c.getUrl(Uri.parse(url));
    headers.forEach(req.headers.set);
    final res = await req.close().timeout(const Duration(seconds: 8));
    return jsonDecode(await res.transform(utf8.decoder).join());
  } finally {
    c.close();
  }
}

/// Exit IP as the internet sees it: {ip, city, country, org}.
Future<Map<String, dynamic>?> exitIp() async {
  try {
    return await _get('https://ipinfo.io/json');
  } catch (_) {
    return null;
  }
}

/// Parses the `subscription-userinfo` header: upload/download/total bytes, expire unix ts.
Map<String, int> parseUserinfo(String? h) => {
  for (final kv in (h ?? '').split(';'))
    if (kv.contains('='))
      kv.split('=')[0].trim(): int.tryParse(kv.split('=')[1].trim()) ?? 0,
};

String fmtBytes(num b) {
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  while (b >= 1024 && i < u.length - 1) {
    b /= 1024;
    i++;
  }
  return '${b.toStringAsFixed(i == 0 ? 0 : 1)} ${u[i]}';
}
