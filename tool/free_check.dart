// ignore_for_file: avoid_print
// Real-world check of the free-server tester (no root, no TUN):
//   dart run tool/free_check.dart <path/to/sing-box> [source-url | all] [n]
// ("all" = what the app's Update does: every freeSources file, sampled)
// e.g. dart run tool/free_check.dart build/macos/Build/Products/Debug/mimray.app/Contents/MacOS/sing-box
import 'package:mimray/free.dart';

Future<void> main(List<String> a) async {
  final bin = a[0];
  final url = a.length > 1 ? a[1] : freeSources.first;
  final n = a.length > 2 ? int.parse(a[2]) : maxTested;
  final sw = Stopwatch()..start();
  final bodies = await Future.wait(
    (url == 'all' ? freeSources : [url]).map(fetchText),
  );
  final all = dedupe([for (final b in bodies) ...parseFree(b ?? '')]);
  final pick = sample(all, n);
  print(
    '$url: ${all.length} unique configs, testing ${pick.length} (fetch ${sw.elapsed.inMilliseconds} ms)',
  );
  sw.reset();
  var last = 0, tested = 0;
  final r = await coreTest(
    bin,
    [for (final s in pick) s.outbound],
    progress: (d, t) {
      tested = t;
      if (d - last >= 25 || d == t) print('  testing $d/$t…');
      if (d - last >= 25) last = d;
    },
  );
  final ok = [
    for (var i = 0; i < r.length; i++)
      if (r[i] != null) (pick[i], r[i]!),
  ]..sort((x, y) => x.$2.compareTo(y.$2));
  final types = <String, int>{};
  for (final (s, _) in ok) {
    types.update(s.outbound['type'], (v) => v + 1, ifAbsent: () => 1);
  }
  print(
    '${pick.length - tested} refused by the core and dropped; ${ok.length} of ${pick.length} worked in ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s; by type: $types',
  );
  for (final (s, d) in ok.take(10)) {
    print('  $d ms  ${s.outbound['type']}  ${s.host}:${s.port}');
  }
}
