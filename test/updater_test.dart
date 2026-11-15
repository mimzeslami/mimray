import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimray/updater.dart';

void main() {
  test('version comparison never downgrades', () {
    expect(isNewer('0.3.1', '0.3.0'), isTrue);
    expect(isNewer('v1.0.0', '0.9.9'), isTrue);
    expect(isNewer('0.3.10', '0.3.9'), isTrue);
    expect(isNewer('0.3.0', '0.3.0'), isFalse);
    expect(isNewer('0.2.9', '0.3.0'), isFalse);
    expect(isNewer('0.3.0+5', '0.3.0'), isFalse); // build number ignored
  });

  test('picks an asset for this platform', () {
    expect(assetSuffix(), isNotNull);
  });

  group('download verifies sha256', () {
    late HttpServer server;
    final body = List<int>.generate(200000, (i) => i % 251);
    var served = body;

    setUp(() async {
      served = body;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        if (req.uri.path == '/SHA256SUMS') {
          req.response.write(
            '${sha256.convert(body)}  mimray-9.9.9-test.bin\n',
          );
        } else {
          req.response.contentLength = served.length;
          req.response.add(served);
        }
        req.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    Update u() => Update(
      '9.9.9',
      '',
      '',
      'mimray-9.9.9-test.bin',
      'http://127.0.0.1:${server.port}/asset',
      'http://127.0.0.1:${server.port}/SHA256SUMS',
    );

    test('accepts a matching file and reports progress', () async {
      var last = 0.0;
      final path = await download(u(), (p) => last = p);
      expect(await File(path).readAsBytes(), body);
      expect(last, 1.0);
    });

    test('rejects a tampered file and deletes it', () async {
      served = [...body]..[1000] ^= 0xff;
      await expectLater(
        download(u(), (_) {}),
        throwsA(contains('Checksum mismatch')),
      );
    });
  });

  group('check reads the github.com latest redirect (no API)', () {
    late HttpServer server;
    var latest = '9.9.9';
    var assetStatus = 200;

    setUp(() async {
      latest = '9.9.9';
      assetStatus = 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        final p = req.uri.path;
        if (p.endsWith('/releases/latest')) {
          req.response.statusCode = 302;
          req.response.headers.set(
            'location',
            'http://127.0.0.1:${server.port}/mimzeslami/mimray/releases/tag/v$latest',
          );
        } else if (p.contains('/releases/download/')) {
          req.response.statusCode = assetStatus;
        } else {
          req.response.statusCode = 404;
        }
        req.response.close();
      });
      githubBase = 'http://127.0.0.1:${server.port}';
    });
    tearDown(() {
      githubBase = 'https://github.com';
      return server.close(force: true);
    });

    test('offers a newer version with the right asset URL', () async {
      expect(await latestVersion(), '9.9.9');
      final u = (await check('0.5.2'))!;
      expect(u.version, '9.9.9');
      expect(u.assetName, 'mimray-9.9.9${assetSuffix()}');
      expect(u.assetUrl, endsWith('/releases/download/v9.9.9/${u.assetName}'));
      expect(u.sumsUrl, endsWith('/releases/download/v9.9.9/SHA256SUMS'));
    });

    test('same or older version = up to date', () async {
      latest = '0.5.2';
      expect(await check('0.5.2'), isNull);
      expect(await check('0.6.0'), isNull);
    });

    test('release without files yet = clear error, not "up to date"', () async {
      assetStatus = 404;
      await expectLater(
        check('0.5.2'),
        throwsA(contains('still being published')),
      );
    });
  });
}
