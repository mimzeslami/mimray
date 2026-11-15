// Windows end-to-end test (CI, admin runner): the app's real Core + UAC launcher
// start sing-box in TUN mode against a local shadowsocks server; HTTPS must go
// through the proxy, and stop() must end the session cleanly (exit 0).
// Usage: MIMRAY_CORE=<path to sing-box.exe> dart run tool/win_e2e.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mimray/core.dart';
import 'package:mimray/links.dart';

Future<void> main() async {
  final core = Platform.environment['MIMRAY_CORE']!;
  final dir = await Directory.systemTemp.createTemp('mimray-e2e');
  final serverCfg = File('${dir.path}\\server.json')
    ..writeAsStringSync(
      jsonEncode({
        'log': {'level': 'info'},
        'inbounds': [
          {
            'type': 'shadowsocks',
            'listen': '127.0.0.1',
            'listen_port': 8388,
            'method': 'aes-256-gcm',
            'password': 'testpass',
          },
        ],
        'outbounds': [
          {'type': 'direct'},
        ],
      }),
    );
  final serverLog = File('${dir.path}\\server.log');
  final server = await Process.start(core, ['run', '-c', serverCfg.path]);
  final sink = serverLog.openWrite();
  server.stdout.listen(sink.add);
  server.stderr.listen(sink.add);
  await Future.delayed(const Duration(seconds: 2));

  final link =
      'ss://${base64.encode(utf8.encode('aes-256-gcm:testpass'))}@127.0.0.1:8388#e2e';
  final c = Core();
  final exited = Completer<int>();
  await c.start([parseLink(link)!.outbound], exited.complete);

  var up = false;
  for (var i = 0; i < 40 && !up; i++) {
    await Future.delayed(const Duration(milliseconds: 500));
    up = await c.stats() != null;
    if (exited.isCompleted) break;
  }
  if (!up) {
    stderr.writeln('FAIL: tunnel did not come up\n${await c.logTail(40)}');
    exit(1);
  }
  stdout.writeln('PASS: tunnel up via UAC launcher');

  final http = HttpClient();
  final res = await (await http.getUrl(
    Uri.parse('https://www.gstatic.com/generate_204'),
  )).close();
  stdout.writeln('HTTPS status ${res.statusCode}');
  if (res.statusCode != 204) exit(1);
  await Future.delayed(const Duration(seconds: 1));
  final seen = serverLog.readAsStringSync();
  if (!seen.contains('inbound connection to')) {
    stderr.writeln('FAIL: request did not go through the proxy\n$seen');
    exit(1);
  }
  stdout.writeln('PASS: HTTPS went through the proxy server');

  await c.stop();
  final code = await exited.future.timeout(const Duration(seconds: 15));
  if (code != 0) {
    stderr.writeln('FAIL: stop() ended with $code');
    exit(1);
  }
  stdout.writeln('PASS: stopped cleanly');
  server.kill();
  exit(0);
}
