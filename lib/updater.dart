// In-app updates from GitHub Releases.
//
// check()   -> newer release + the right asset for this platform/CPU, or null
// download  -> file in temp, verified against the release's SHA256SUMS
// install() -> replaces the app and relaunches it (desktop), or opens the
//              Android package installer. Never downgrades.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _repo = 'mimzeslami/mimray';

class Update {
  final String version, notes, page, assetName, assetUrl, sumsUrl;
  const Update(
    this.version,
    this.notes,
    this.page,
    this.assetName,
    this.assetUrl,
    this.sumsUrl,
  );
}

/// Android installs the downloaded APK through the system installer; set by
/// android_vpn.dart (method channel). Null on desktop.
Future<void> Function(String apkPath)? installApk;

/// "1.2.10" > "1.2.9"; non-numeric parts count as 0.
bool isNewer(String a, String b) {
  List<int> p(String v) => v
      .replaceFirst(RegExp(r'^v'), '')
      .split(RegExp(r'[.+-]'))
      .take(3)
      .map((x) => int.tryParse(x) ?? 0)
      .toList();
  final x = p(a), y = p(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d > 0;
  }
  return false;
}

/// Release asset suffix for this OS + CPU, e.g. "-linux-x86_64.tar.gz".
String? assetSuffix() {
  // Platform.version ends with: on "macos_arm64" / "linux_x64" / "android_arm64" ...
  final arch = RegExp(r'on "\w+_(\w+)"').firstMatch(Platform.version)?[1] ?? '';
  if (Platform.isMacOS) return '-macos.dmg';
  if (Platform.isWindows) return '-windows-x64.zip';
  if (Platform.isLinux) {
    return arch == 'x64' ? '-linux-x86_64.tar.gz' : null;
  }
  if (Platform.isAndroid) {
    final abi = const {
      'arm64': 'arm64-v8a',
      'arm': 'armeabi-v7a',
      'x64': 'x86_64',
    }[arch];
    return abi == null ? null : '-android-$abi.apk';
  }
  return null;
}

Future<dynamic> _json(String url) async {
  final c = HttpClient()
    ..userAgent = 'mimray'
    ..connectionTimeout = const Duration(seconds: 10);
  try {
    final res = await (await c.getUrl(Uri.parse(url))).close();
    if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
    return jsonDecode(await res.transform(utf8.decoder).join());
  } finally {
    c.close();
  }
}

/// The latest release if it's newer than [current] and has an asset for this
/// device, else null. Throws on network errors.
Future<Update?> check(String current) async {
  final r = await _json('https://api.github.com/repos/$_repo/releases/latest');
  final version = (r['tag_name'] as String).replaceFirst(RegExp(r'^v'), '');
  if (!isNewer(version, current)) return null;
  final suffix = assetSuffix();
  if (suffix == null) return null;
  String? url, name, sums;
  for (final a in r['assets'] as List) {
    final n = a['name'] as String;
    if (n.endsWith(suffix)) {
      url = a['browser_download_url'];
      name = n;
    }
    if (n == 'SHA256SUMS') sums = a['browser_download_url'];
  }
  if (url == null || sums == null) return null;
  return Update(
    version,
    (r['body'] as String?) ?? '',
    r['html_url'] as String,
    name!,
    url,
    sums,
  );
}

/// Downloads the asset and verifies its sha256. Returns the local file path.
Future<String> download(
  Update u,
  void Function(double progress) onProgress,
) async {
  final c = HttpClient()..userAgent = 'mimray';
  try {
    final sumsRes = await (await c.getUrl(Uri.parse(u.sumsUrl))).close();
    final sums = await sumsRes.transform(utf8.decoder).join();
    final want = sums
        .split('\n')
        .map((l) => l.trim().split(RegExp(r'\s+')))
        .firstWhere(
          (p) => p.length == 2 && p[1].replaceFirst('*', '') == u.assetName,
          orElse: () => const [],
        );
    if (want.isEmpty) throw 'No checksum for ${u.assetName} in the release';

    final dir = await Directory.systemTemp.createTemp('mimray-update');
    final f = File('${dir.path}/${u.assetName}');
    final res = await (await c.getUrl(Uri.parse(u.assetUrl))).close();
    if (res.statusCode != 200) throw 'Download failed: HTTP ${res.statusCode}';
    final total = res.contentLength;
    var got = 0;
    final sink = f.openWrite();
    await for (final chunk in res) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress(got / total);
    }
    await sink.close();

    final digest = sha256.convert(await f.readAsBytes()).toString();
    if (digest != want[0].toLowerCase()) {
      await f.delete();
      throw 'Checksum mismatch — update rejected (download corrupted or tampered)';
    }
    return f.path;
  } finally {
    c.close();
  }
}

String _sq(String s) => "'${s.replaceAll("'", "'\\''")}'";
String _psq(String s) => "'${s.replaceAll("'", "''")}'";

/// Installs the verified file. Desktop: a detached script waits for this
/// process to exit, swaps the files and relaunches; the caller should then quit.
/// Returns false if the app location isn't writable (caller can open the file
/// for a manual install instead).
Future<bool> install(String file) async {
  final exe = File(Platform.resolvedExecutable);
  if (Platform.isAndroid) {
    await installApk!(file);
    return true;
  }
  if (Platform.isMacOS) {
    // .../mimray.app/Contents/MacOS/mimray -> .../mimray.app
    final app = exe.parent.parent.parent.path;
    final parent = Directory(app).parent.path;
    if (!await _writable(parent) || !await _writable(app)) return false;
    final sh =
        'while kill -0 $pid 2>/dev/null; do sleep 0.3; done\n'
        'M=\$(mktemp -d)\n'
        'hdiutil attach -nobrowse -quiet -mountpoint "\$M" ${_sq(file)} || exit 1\n'
        'rm -rf ${_sq(app)} && cp -R "\$M/mimray.app" ${_sq(app)}\n'
        'hdiutil detach -quiet "\$M"\n'
        'xattr -dr com.apple.quarantine ${_sq(app)} 2>/dev/null\n'
        'open ${_sq(app)}\n';
    return _detached('/bin/sh', ['-c', sh]);
  }
  if (Platform.isLinux) {
    final dir = exe.parent.path;
    if (!await _writable(dir)) return false;
    final sh =
        'while kill -0 $pid 2>/dev/null; do sleep 0.3; done\n'
        'tar xzf ${_sq(file)} -C ${_sq(dir)} || exit 1\n'
        'nohup ${_sq(exe.path)} >/dev/null 2>&1 &\n';
    return _detached('/bin/sh', ['-c', sh]);
  }
  if (Platform.isWindows) {
    final dir = exe.parent.path;
    if (!await _writable(dir)) return false;
    final ps =
        'Wait-Process -Id $pid -ErrorAction SilentlyContinue; '
        'Expand-Archive -Force ${_psq(file)} ${_psq(dir)}; '
        'Get-ChildItem ${_psq(dir)} -Recurse | Unblock-File; '
        'Start-Process ${_psq(exe.path)}';
    return _detached('powershell', [
      '-NoProfile',
      '-WindowStyle',
      'Hidden',
      '-Command',
      ps,
    ]);
  }
  return false;
}

Future<bool> _detached(String cmd, List<String> args) async {
  await Process.start(cmd, args, mode: ProcessStartMode.detached);
  return true;
}

Future<bool> _writable(String dir) async {
  try {
    final probe = File('$dir/.mimray-write-test');
    await probe.writeAsString('');
    await probe.delete();
    return true;
  } catch (_) {
    return false;
  }
}
