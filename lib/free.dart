// Opt-in "Free" servers: public free configs + community-shared ones, kept
// only when they work from this device. Pure Dart (no Flutter) so it's testable.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'links.dart';

/// Public free configs (github.com/barry-far/V2ray-Config, MIT), ~500 plain
/// share links per file. Add SubN.txt files here to widen the pool (up to Sub19).
const _barry = 'https://raw.githubusercontent.com/barry-far/V2ray-Config/main';
const freeSources = [
  '$_barry/Sub1.txt',
  '$_barry/Sub2.txt',
  '$_barry/Sub3.txt',
  '$_barry/Sub4.txt',
];

/// Moderated community-shared servers (maintainer-approved).
const communitySource =
    'https://raw.githubusercontent.com/mimzeslami/mimray/community/community/servers.json';

/// Where "Share your server" sends people (GitHub issue form).
const shareUrl =
    'https://github.com/mimzeslami/mimray/issues/new?template=share-server.yml';

const testUrl = 'https://www.gstatic.com/generate_204';
const maxTested = 200; // configs tested per update
const maxKept = 50; // working ones kept

/// Stable server id: type://host:port (no credentials).
String serverKey(Server s) => '${s.outbound['type']}://${s.host}:${s.port}';

/// A free or community server plus its last test result.
class FreeServer {
  final Server server;
  final int? delay; // ms through the server (desktop) or TCP connect (Android)
  final String? title, donor; // community only
  FreeServer(this.server, {this.delay, this.title, this.donor});
  bool get community => title != null;
  FreeServer withDelay(int? d) =>
      FreeServer(server, delay: d, title: title, donor: donor);
  Map<String, dynamic> toJson() => {
    'server': server,
    'delay': delay,
    'title': ?title,
    'donor': ?donor,
  };
  static FreeServer? fromJson(Map j) {
    try {
      return FreeServer(
        Server.fromJson(Map<String, dynamic>.from(j['server'])),
        delay: j['delay'] as int?,
        title: j['title'] as String?,
        donor: j['donor'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Plain-link source file -> servers (comment lines skipped, deduped).
List<Server> parseFree(String body) => dedupe(
  parseImport(
    body
        .split(RegExp(r'[\r\n]+'))
        .where((l) => !l.trimLeft().startsWith('#'))
        .join('\n'),
  ),
);

List<Server> dedupe(Iterable<Server> l) {
  final seen = <String>{};
  return [
    for (final s in l)
      if (seen.add(serverKey(s))) s,
  ];
}

/// Up to [n] random items (all of them, shuffled, if fewer).
List<T> sample<T>(List<T> l, int n, [Random? r]) =>
    (List.of(l)..shuffle(r)).take(n).toList();

/// Untrusted text from the community file: plain, single line, length-capped.
String? _clip(Object? v, int max) {
  if (v is! String && v is! num) return null;
  final s = '$v'
      .replaceAll(
        RegExp(r'[\x00-\x1f\x7f\u200b-\u200f\u202a-\u202e\u2066-\u2069]'),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.isEmpty) return null;
  return s.length <= max ? s : '${s.substring(0, max - 1)}…';
}

/// community/servers.json -> servers. Every field is untrusted: entries that
/// don't parse are dropped, text is plain and length-limited.
List<FreeServer> parseCommunity(String body) {
  if (body.length > 2 << 20) return []; // 2 MB is far beyond any real list
  Object? j;
  try {
    j = jsonDecode(body);
  } catch (_) {
    return [];
  }
  final list = j is Map ? j['servers'] : null;
  if (list is! List) return [];
  final out = <FreeServer>[];
  for (final e in list.take(500)) {
    if (e is! Map) continue;
    final link = e['link'];
    if (link is! String || link.length > 4096) continue;
    final s = parseLink(link);
    final title = _clip(e['title'], 60);
    if (s == null || title == null) continue;
    out.add(
      FreeServer(
        Server(title, s.outbound, s.link),
        title: title,
        donor: _clip(e['donor'], 32) ?? 'anonymous',
      ),
    );
  }
  return dedupeFree(out);
}

List<FreeServer> dedupeFree(Iterable<FreeServer> l) {
  final seen = <String>{};
  return [
    for (final s in l)
      if (seen.add(serverKey(s.server))) s,
  ];
}

/// GET [url] as text. Null on 404 (e.g. no community file yet).
Future<String?> fetchText(String url) async {
  final c = HttpClient()
    ..userAgent = 'mimray'
    ..connectionTimeout = const Duration(seconds: 15);
  try {
    final res = await (await c.getUrl(
      Uri.parse(url),
    )).close().timeout(const Duration(seconds: 30));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
    return await res.transform(utf8.decoder).join();
  } finally {
    c.close();
  }
}

// ---------- testing through the core (desktop) ----------

/// sing-box config with only the outbounds s0..sN + direct and the local API.
/// No inbounds, no TUN: nothing on the system is routed through it.
Map<String, dynamic> testConfig(
  List<Map<String, dynamic>> outbounds,
  String api,
  String secret,
) => {
  'log': {'level': 'error'},
  'dns': {
    'servers': [
      {'type': 'local', 'tag': 'local'},
    ],
  },
  'outbounds': [
    for (var i = 0; i < outbounds.length; i++) {...outbounds[i], 'tag': 's$i'},
    {'type': 'direct', 'tag': 'direct'},
  ],
  'route': {'default_domain_resolver': 'local', 'final': 'direct'},
  'experimental': {
    'clash_api': {'external_controller': api, 'secret': secret},
  },
};

/// Index of the outbound sing-box refused, from its startup error
/// ("initialize outbound[17]: …", "outbounds[3].transport: …"), or null.
int? badOutbound(String log) {
  final m = RegExp(r'outbounds?\[(\d+)\]').firstMatch(log);
  return m == null ? null : int.parse(m[1]!);
}

/// Real test: run [binary] (the bundled sing-box) as the normal user and ask
/// it to fetch [testUrl] through each outbound. Returns delay (ms) per input
/// index, null = failed. Invalid outbounds are dropped and the core restarted
/// (at most [maxRetries] times).
Future<List<int?>> coreTest(
  String binary,
  List<Map<String, dynamic>> outbounds, {
  void Function(int done, int total)? progress,
  int concurrency = 16,
  int maxRetries = 25,
}) async {
  final result = List<int?>.filled(outbounds.length, null);
  var idx = [for (var i = 0; i < outbounds.length; i++) i]; // live -> input
  final dir = await Directory.systemTemp.createTemp('mimray-test');
  Process? p;
  try {
    for (var attempt = 0; ; attempt++) {
      if (idx.isEmpty) return result;
      final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final api = '127.0.0.1:${sock.port}';
      await sock.close();
      final r = Random.secure();
      final secret = base64Url.encode(List.generate(24, (_) => r.nextInt(256)));
      final cfg = File('${dir.path}/test.json');
      await cfg.writeAsString(
        jsonEncode(
          testConfig([for (final i in idx) outbounds[i]], api, secret),
        ),
      );
      p = await _startCore(binary, cfg.path);
      _running = p;
      final out = StringBuffer();
      p.stdout.transform(utf8.decoder).listen(out.write, onError: (_) {});
      p.stderr.transform(utf8.decoder).listen(out.write, onError: (_) {});
      int? exit;
      p.exitCode.then((c) => exit = c);
      final auth = {'Authorization': 'Bearer $secret'};
      var up = false;
      for (var t = 0; t < 100 && exit == null && !up; t++) {
        await Future.delayed(const Duration(milliseconds: 100));
        up = await _get('http://$api/version', auth) != null;
      }
      if (!up) {
        p.kill();
        await p.exitCode;
        final bad = badOutbound('$out');
        if (bad == null || bad >= idx.length || attempt >= maxRetries) {
          throw 'Core failed to start: ${'$out'.trim().split('\n').last}';
        }
        idx = [...idx]..removeAt(bad); // drop the config sing-box refused
        continue;
      }
      var next = 0, done = 0;
      Future<void> worker() async {
        while (next < idx.length) {
          final k = next++;
          final j = await _get(
            'http://$api/proxies/s$k/delay?timeout=5000&url=${Uri.encodeQueryComponent(testUrl)}',
            auth,
            const Duration(seconds: 8),
          );
          final d = j?['delay'];
          if (d is int && d > 0) result[idx[k]] = d;
          progress?.call(++done, idx.length);
        }
      }

      await Future.wait([for (var w = 0; w < concurrency; w++) worker()]);
      return result;
    }
  } finally {
    p?.kill();
    _running = null;
    await dir.delete(recursive: true).catchError((_) => dir);
  }
}

Process? _running;

/// Stops a test core that's still running (call before the app quits).
void stopCoreTest() => _running?.kill();

/// macOS/Linux: a small sh watchdog runs the core and kills it when this app
/// dies, so a crash or quit mid-test never leaves a stray core behind.
Future<Process> _startCore(String binary, String cfg) => Platform.isWindows
    ? Process.start(binary, ['run', '-c', cfg])
    : Process.start('/bin/sh', [
        '-c',
        r'"$0" run -c "$1" & p=$!; trap "kill $p 2>/dev/null; exit 1" TERM INT; '
            r'while kill -0 $p 2>/dev/null && kill -0 "$2" 2>/dev/null; do sleep 1; done; '
            r'kill $p 2>/dev/null; wait $p',
        binary,
        cfg,
        '$pid',
      ]);

Future<Map<String, dynamic>?> _get(
  String url,
  Map<String, String> headers, [
  Duration timeout = const Duration(seconds: 2),
]) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final req = await c.getUrl(Uri.parse(url));
    headers.forEach(req.headers.set);
    final res = await req.close().timeout(timeout);
    final body = await res.transform(utf8.decoder).join().timeout(timeout);
    final j = jsonDecode(body);
    return j is Map<String, dynamic> ? j : null;
  } catch (_) {
    return null;
  } finally {
    c.close(force: true);
  }
}
