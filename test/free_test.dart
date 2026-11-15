import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimray/free.dart';

void main() {
  group('free list', () {
    final body = File('test/fixtures/free_sub.txt').readAsStringSync();

    test(
      'skips headers/comments and bad links, dedupes by type://host:port',
      () {
        final l = parseFree(body);
        expect(l.map(serverKey), [
          'shadowsocks://1.2.3.4:8080',
          'shadowsocks://1.2.3.4:8443',
          'shadowsocks://5.6.7.8:19999',
          'hysteria2://9.9.9.1:443',
          'vless://b.example:443',
          'trojan://t.example:443',
        ]);
        expect(l.first.name, contains('DE-1')); // first one wins
        expect(l.any((s) => s.host == '6.6.6.6'), isFalse); // commented out
      },
    );

    test('sample caps and keeps distinct items', () {
      final l = List.generate(500, (i) => i);
      final s = sample(l, maxTested, Random(1));
      expect(s.length, maxTested);
      expect(s.toSet().length, maxTested);
      expect(sample([1, 2, 3], 10, Random(1)).toSet(), {1, 2, 3});
    });
  });

  group('core test', () {
    test('bad outbound index from sing-box startup errors', () {
      expect(
        badOutbound(
          'FATAL[0000] start service: initialize outbound[17]: invalid key',
        ),
        17,
      );
      expect(
        badOutbound(
          'FATAL[0000] decode config at test.json: outbounds[3].transport: unknown type',
        ),
        3,
      );
      expect(badOutbound('FATAL[0000] listen tcp 127.0.0.1:1: bind'), isNull);
      expect(badOutbound(''), isNull);
    });

    test('test config: outbounds + local API only, no inbounds/TUN', () {
      final c = testConfig(
        [
          {'type': 'shadowsocks', 'server': 'a', 'server_port': 1},
          {'type': 'vless', 'server': 'b', 'server_port': 2},
        ],
        '127.0.0.1:9999',
        'sec',
      );
      expect(c.containsKey('inbounds'), isFalse);
      expect(
        [for (final o in c['outbounds']) o['tag']],
        ['s0', 's1', 'direct'],
      );
      expect(c['experimental']['clash_api'], {
        'external_controller': '127.0.0.1:9999',
        'secret': 'sec',
      });
      expect(jsonEncode(c), isNot(contains('tun')));
    });

    test(
      'drops refused outbounds and retries, maps results to inputs',
      () async {
        // fake core: a script that refuses outbound[1] until it's gone, then
        // serves the clash API with fixed delays
        if (Platform.isWindows) return;
        final dir = Directory.systemTemp.createTempSync('mimray-fake');
        addTearDown(() => dir.deleteSync(recursive: true));
        final fake = File('${dir.path}/fake-core.dart')
          ..writeAsStringSync(r'''
import 'dart:convert';
import 'dart:io';
Future<void> main(List<String> a) async {
  final c = jsonDecode(File(a[2]).readAsStringSync());
  final outs = (c['outbounds'] as List).where((o) => o['tag'] != 'direct').toList();
  for (var i = 0; i < outs.length; i++) {
    if (outs[i]['server'] == 'bad') {
      stderr.writeln('FATAL[0000] start service: initialize outbound[$i]: bad');
      exit(1);
    }
  }
  final api = c['experimental']['clash_api'];
  final port = int.parse((api['external_controller'] as String).split(':')[1]);
  final s = await HttpServer.bind('127.0.0.1', port);
  await for (final r in s) {
    final ok = r.headers.value('authorization') == 'Bearer ${api['secret']}';
    final m = RegExp(r'/proxies/s(\d+)/delay').firstMatch(r.uri.path);
    final o = m == null ? null : outs[int.parse(m[1]!)];
    r.response.write(jsonEncode(!ok
        ? {'message': 'unauthorized'}
        : m == null
        ? {'version': 'fake'}
        : o['server'] == 'dead'
        ? {'message': 'timeout'}
        : {'delay': o['server_port']}));
    await r.response.close();
  }
}
''');
        // the fake core runs on this SDK's dart (flutter_tester isn't one)
        final root = Platform.environment['FLUTTER_ROOT'];
        final which = (await Process.run('which', [
          'dart',
        ])).stdout.toString().trim();
        final dart = root != null ? '$root/bin/dart' : which;
        if (dart.isEmpty || !File(dart).existsSync()) {
          markTestSkipped('dart not found');
          return;
        }
        final sh = File('${dir.path}/sing-box')
          ..writeAsStringSync('#!/bin/sh\nexec "$dart" "${fake.path}" "\$@"\n');
        await Process.run('chmod', ['+x', sh.path]);
        final outs = [
          {'type': 'shadowsocks', 'server': 'ok', 'server_port': 120},
          {'type': 'shadowsocks', 'server': 'bad', 'server_port': 1},
          {'type': 'shadowsocks', 'server': 'dead', 'server_port': 1},
          {'type': 'shadowsocks', 'server': 'bad', 'server_port': 1},
          {'type': 'shadowsocks', 'server': 'ok', 'server_port': 45},
        ];
        final seen = <int>[];
        final r = await coreTest(
          sh.path,
          outs,
          progress: (d, t) => seen.add(t),
        );
        expect(r, [120, null, null, null, 45]);
        expect(seen.last, 3); // 2 refused configs dropped
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('community', () {
    const vless = 'vless://u@c.example:443?security=tls&sni=c.example#x';
    String file(List<Object?> servers) =>
        jsonEncode({'version': 1, 'servers': servers});

    test('valid entries parse; text is plain and capped', () {
      final l = parseCommunity(
        file([
          {
            'id': '12',
            'title': 'Fast DE server\nfor\u202e students',
            'donor': 'alice',
            'link': vless,
            'note': 'n',
            'added': '2026-11-15',
            'issue': 12,
          },
          {
            'title': 'x' * 5000,
            'donor': 'y' * 5000,
            'link': vless.replaceFirst('c.', 'd.'),
          },
        ]),
      );
      expect(l.length, 2);
      expect(l[0].title, 'Fast DE server for students');
      expect(l[0].donor, 'alice');
      expect(l[0].community, isTrue);
      expect(l[0].server.host, 'c.example');
      expect(l[1].title!.length, lessThanOrEqualTo(60));
      expect(l[1].donor!.length, lessThanOrEqualTo(32));
    });

    test('malformed and hostile entries are dropped', () {
      final l = parseCommunity(
        file([
          null,
          42,
          'vless://u@a:1',
          {'title': 'no link'},
          {'title': 'bad link', 'link': 'javascript:alert(1)'},
          {'title': 'not a string', 'link': 7},
          {'title': 'huge', 'link': 'vless://u@h.example:443#${'a' * 10000}'},
          {'link': vless}, // no title
          {'title': '   ', 'link': vless}, // blank title
          {'title': 'dup 1', 'link': vless},
          {'title': 'dup 2', 'link': vless},
          {'title': 'no donor', 'link': 'trojan://p@t.example:443#t'},
        ]),
      );
      expect(l.map((e) => e.title), ['dup 1', 'no donor']);
      expect(l.last.donor, 'anonymous');
    });

    test('empty, 404-ish and non-JSON bodies mean no servers', () {
      for (final b in [
        '',
        '404: Not Found',
        '[]',
        '{}',
        '{"servers":"x"}',
        'null',
      ]) {
        expect(parseCommunity(b), isEmpty, reason: b);
      }
      expect(
        parseCommunity(
          '{"servers":[${'{"title":"t","link":"$vless"},' * 3}{}]}',
        ).length,
        1,
      );
    });

    test('FreeServer round-trips through state.json', () {
      final f = parseCommunity(
        file([
          {'title': 't', 'donor': 'd', 'link': vless},
        ]),
      ).single.withDelay(80);
      final g = FreeServer.fromJson(jsonDecode(jsonEncode(f)))!;
      expect(
        (g.title, g.donor, g.delay, g.server.host),
        ('t', 'd', 80, 'c.example'),
      );
      expect(FreeServer.fromJson({'server': 'junk'}), isNull);
    });
  });
}
