// Prints the Linux client config the app would generate for a share link.
// Usage: dart run tool/gen_config.dart <link> [ipv6=true|false]
import 'dart:convert';
import 'dart:io';

import 'package:mimray/core.dart';
import 'package:mimray/links.dart';

void main(List<String> a) {
  final s = parseLink(a[0])!;
  final ipv6 = a.length > 1 && a[1] == 'true';
  stdout.writeln(
    jsonEncode(buildConfig([s.outbound], stack: 'gvisor', ipv6: ipv6)),
  );
}
