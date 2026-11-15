// Maintains community/servers.json (on the `community` branch) from approved
// "Share a server" issues. Run by .github/workflows/community.yml.
//
//   dart run tool/community.dart add    <servers.json> <issue-number>   (body in $ISSUE_BODY)
//   dart run tool/community.dart remove <servers.json> <issue-number>
//
// The issue body is untrusted: it is only parsed as data, fields are
// length-limited and stripped of control characters, and the link must parse
// with the app's own parser.
import 'dart:convert';
import 'dart:io';

import 'package:mimray/links.dart';

/// Issue-form body ("### Label\n\nvalue\n\n### …") -> {label: value}.
Map<String, String> formFields(String body) {
  final out = <String, String>{};
  final parts = body
      .replaceAll('\r', '')
      .split(RegExp(r'^### ', multiLine: true));
  for (final p in parts.skip(1)) {
    final nl = p.indexOf('\n');
    if (nl < 0) continue;
    var v = p.substring(nl + 1).trim();
    v = v.replaceAll(RegExp(r'^```\w*\n|\n?```$'), '').trim(); // render: text
    if (v == '_No response_') v = '';
    out[p.substring(0, nl).trim()] = v;
  }
  return out;
}

String clean(String s, int max) {
  final t = s
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return t.length > max ? t.substring(0, max) : t;
}

/// Validates an issue and returns the entry to add, or throws a readable reason.
Map<String, dynamic> entryFromIssue(String body, int issue, DateTime now) {
  final f = formFields(body);
  final title = clean(f['Title shown in the app'] ?? '', 60);
  if (title.isEmpty) throw 'Missing title';
  final link = (f['Server link'] ?? '')
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.contains('://'), orElse: () => '');
  if (link.length > 4096) throw 'Link is too long';
  final server = parseLink(link);
  if (server == null) {
    throw 'The link could not be parsed (supported: vless, vmess, trojan, ss, hy2)';
  }
  return {
    'id': '$issue',
    'title': title,
    'donor': clean(f['Your name (optional)'] ?? '', 40),
    'link': link,
    'note': clean(f['Note (optional)'] ?? '', 200),
    'added': now.toUtc().toIso8601String().substring(0, 10),
    'issue': issue,
  };
}

Map<String, dynamic> load(File f) {
  if (!f.existsSync()) return {'version': 1, 'servers': <dynamic>[]};
  final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  j['servers'] ??= <dynamic>[];
  return j;
}

void save(File f, Map<String, dynamic> j) {
  f.parent.createSync(recursive: true);
  f.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(j)}\n');
}

void main(List<String> a) {
  if (a.length != 3) {
    stderr.writeln('usage: community.dart add|remove <servers.json> <issue>');
    exit(2);
  }
  final file = File(a[1]);
  final issue = int.parse(a[2]);
  final j = load(file);
  final servers = (j['servers'] as List).cast<Map<String, dynamic>>();
  servers.removeWhere((s) => s['issue'] == issue); // re-approval replaces
  if (a[0] == 'add') {
    try {
      final e = entryFromIssue(
        Platform.environment['ISSUE_BODY'] ?? '',
        issue,
        DateTime.now(),
      );
      if (servers.any((s) => s['link'] == e['link'])) {
        throw 'This server is already listed';
      }
      servers.add(e);
      stdout.writeln('Added "${e['title']}"');
    } catch (e) {
      stdout.writeln('REJECTED: $e');
      exit(1);
    }
  } else {
    stdout.writeln('Removed entry for issue #$issue');
  }
  j['servers'] = servers;
  save(file, j);
}
