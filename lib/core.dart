// Builds the sing-box TUN config and runs the core as root (macOS admin prompt).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

final _home = Platform.environment['HOME'];
final appDir = Platform.isWindows
    ? '${Platform.environment['APPDATA']}\\mimray'
    : Platform.isMacOS
    ? '$_home/Library/Application Support/mimray'
    : '${Platform.environment['XDG_CONFIG_HOME'] ?? '$_home/.config'}/mimray';

/// Owner-only file permissions (files hold credentials). On Windows the
/// per-user AppData folder already restricts access.
Future<void> privateFile(String path) async {
  if (!Platform.isWindows) await Process.run('chmod', ['600', path]);
}

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

/// Root helper service (see helper/): starts the core without a password prompt.
final helperSock = Platform.isMacOS
    ? '/var/run/mimray.sock'
    : '/run/mimray.sock';
final _exeDir = File(Platform.resolvedExecutable).parent.path;

/// The install script ships inside the app when the helper was built
/// (macOS: Contents/Resources, since scripts in Contents/MacOS break signing).
final _helperScript = Platform.isMacOS
    ? '$_exeDir/../Resources/install-helper.sh'
    : '$_exeDir/install-helper.sh';
bool get helperBundled => File(_helperScript).existsSync();

Future<Socket> _helperConnect() => Socket.connect(
  InternetAddress(helperSock, type: InternetAddressType.unix),
  0,
  timeout: const Duration(seconds: 2),
);

/// Helper version if it's installed and answering, else null.
Future<String?> helperVersion() async {
  if (!File(helperSock).existsSync()) return null;
  try {
    final s = await _helperConnect();
    s.write('{"cmd":"version"}\n');
    final line = await s
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 2));
    s.destroy();
    return jsonDecode(line)['version'] as String?;
  } catch (_) {
    return null;
  }
}

/// Installs (or removes) the helper. Asks for the admin password once.
Future<String?> setupHelper({bool uninstall = false}) async {
  final uid = (await Process.run('id', ['-u'])).stdout.toString().trim();
  final script = _helperScript;
  final sh = uninstall
      ? 'sh ${_sq(script)} --uninstall'
      : 'sh ${_sq(script)} ${_sq(_exeDir)} $uid';
  final ProcessResult r;
  if (Platform.isMacOS) {
    final as = sh.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    r = await Process.run('osascript', [
      '-e',
      'do shell script "$as" with administrator privileges',
    ]);
  } else {
    r = await Process.run('pkexec', ['/bin/sh', '-c', sh]);
  }
  return r.exitCode == 0 ? null : '${r.stderr}${r.stdout}'.trim();
}

class Core {
  Process? _p;
  Socket? _h; // helper session
  String? _api, _secret;
  bool get running => _p != null || _h != null;
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
    final config = buildConfig(
      proxies,
      ai: ai,
      opt: opt,
      api: _api,
      secret: _secret,
      // gvisor on Linux (ufw/firewalld can drop the system stack's TCP) and
      // Windows (avoids firewall prompts); mixed is fastest on macOS
      stack: Platform.isMacOS ? 'mixed' : 'gvisor',
      ipv6: !Platform.isLinux || _linuxV6(),
    );
    _stopping = false;
    if (await helperVersion() != null) {
      return _startViaHelper(config, onExit);
    }
    await cfg.writeAsString(jsonEncode(config));
    await privateFile(cfg.path); // contains credentials
    final stop = File(_stop);
    if (await stop.exists()) await stop.delete();

    _stopping = false;
    if (Platform.isWindows) return _startWindows(cfg.path, onExit);
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
      onExit(_stopping ? 0 : c); // a stop the user asked for is not an error
    });
  }

  /// Windows: UAC prompt per connect; the elevated PowerShell runs the core and
  /// stops it when the app exits or the stop file appears (same as macOS/Linux).
  Future<void> _startWindows(String cfg, void Function(int) onExit) async {
    String q(String s) => "'${s.replaceAll("'", "''")}'";
    final bin =
        Platform.environment['MIMRAY_CORE'] ??
        '$_exeDir\\sing-box.exe'; // env: tests
    final inner =
        '\$p = Start-Process -FilePath ${q(bin)} -ArgumentList ${q('run -c "$cfg"')} '
        '-NoNewWindow -PassThru -RedirectStandardError ${q(log)}\n'
        'while (-not \$p.HasExited -and (Get-Process -Id $pid -ErrorAction SilentlyContinue) '
        '-and -not (Test-Path ${q(_stop)})) { Start-Sleep -Milliseconds 500 }\n'
        'if (-not \$p.HasExited) { Stop-Process -Id \$p.Id -Force; \$p.WaitForExit() }\n'
        'exit \$p.ExitCode\n';
    // -EncodedCommand takes UTF-16LE base64: no quoting problems with paths
    final enc = base64.encode([
      for (final c in inner.codeUnits) ...[c & 0xff, c >> 8],
    ]);
    final outer =
        "try { \$r = Start-Process powershell -Verb RunAs -WindowStyle Hidden -Wait -PassThru "
        "-ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand','$enc'; "
        "exit \$r.ExitCode } catch { exit 1 }";
    final p = await Process.start('powershell', [
      '-NoProfile',
      '-Command',
      outer,
    ]);
    _p = p;
    p.exitCode.then((c) {
      _p = null;
      onExit(_stopping ? 0 : c);
    });
  }

  /// No password: the helper runs the core for as long as this socket is open.
  Future<void> _startViaHelper(
    Map<String, dynamic> config,
    void Function(int code) onExit,
  ) async {
    final s = await _helperConnect();
    _h = s;
    final logSink = File(log).openWrite();
    var code = 1;
    s.write('${jsonEncode({'cmd': 'start', 'config': config})}\n');
    s
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            try {
              final m = jsonDecode(line) as Map;
              if (m['log'] != null) logSink.writeln(m['log']);
              if (m['error'] != null) logSink.writeln('helper: ${m['error']}');
              if (m['exit'] != null) code = m['exit'];
            } catch (_) {}
          },
          onDone: () {
            logSink.close();
            s.destroy();
            _h = null;
            onExit(_stopping ? 0 : code);
          },
          onError: (_) {},
          cancelOnError: false,
        );
  }

  bool _stopping = false;

  Future<void> stop() async {
    _stopping = true;
    final h = _h;
    if (h != null) {
      h.write('{"cmd":"stop"}\n');
      return;
    }
    await File(_stop).writeAsString('');
  }

  int _lastUp = 0, _lastDown = 0;

  /// Totals + per-second rates from the core. Null until the core is up.
  /// Call once a second.
  Future<Stats?> stats() async {
    if (!running) return null;
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
