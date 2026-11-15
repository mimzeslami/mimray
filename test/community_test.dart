import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/community.dart';

String body({
  String title = 'Fast DE server',
  String link = 'vless://u@e.com:443?security=tls#x',
  String donor = 'alice',
  String note = '_No response_',
}) =>
    '### Title shown in the app\n\n$title\n\n'
    '### Server link\n\n```text\n$link\n```\n\n'
    '### Your name (optional)\n\n$donor\n\n'
    '### Note (optional)\n\n$note\n\n'
    '### Before you submit\n\n- [X] I run this server or I\'m allowed to share it publicly.\n';

void main() {
  final now = DateTime.utc(2026, 11, 15);

  test('parses an issue-form body into an entry', () {
    final e = entryFromIssue(body(), 12, now);
    expect(e['title'], 'Fast DE server');
    expect(e['donor'], 'alice');
    expect(e['link'], 'vless://u@e.com:443?security=tls#x');
    expect(e['note'], '');
    expect(e['added'], '2026-11-15');
    expect(e['issue'], 12);
  });

  test('rejects unparseable or missing links', () {
    expect(
      () => entryFromIssue(body(link: 'hello'), 1, now),
      throwsA(isA<String>()),
    );
    expect(
      () => entryFromIssue(body(link: 'http://evil.example/x'), 1, now),
      throwsA(isA<String>()),
    );
    expect(
      () => entryFromIssue(body(title: '_No response_'), 1, now),
      throwsA(contains('title')),
    );
  });

  test('hostile fields are cleaned and length-limited', () {
    final e = entryFromIssue(
      body(
        title: '${'A' * 500}\u0000\u001b[31m',
        donor: 'x\ny',
        note: 'n' * 999,
      ),
      2,
      now,
    );
    expect((e['title'] as String).length, 60);
    expect(e['title'], isNot(contains('\u0000')));
    expect(e['donor'], 'x y');
    expect((e['note'] as String).length, 200);
  });

  test('add + remove round trip on a file (via the CLI)', () async {
    final dir = await Directory.systemTemp.createTemp('community');
    final f = '${dir.path}/community/servers.json';
    Future<ProcessResult> run(String action, int issue, [String b = '']) =>
        Process.run(
          'dart',
          ['run', 'tool/community.dart', action, f, '$issue'],
          environment: {'ISSUE_BODY': b},
        );
    expect((await run('add', 5, body())).exitCode, 0);
    expect((await run('add', 6, body())).exitCode, 1); // duplicate link
    expect((await run('add', 7, body(link: 'nope'))).exitCode, 1);
    var j = jsonDecode(File(f).readAsStringSync());
    expect((j['servers'] as List).map((s) => s['issue']), [5]);
    expect((await run('remove', 5)).exitCode, 0);
    j = jsonDecode(File(f).readAsStringSync());
    expect(j['servers'], isEmpty);
  });
}
