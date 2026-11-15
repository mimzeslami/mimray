// QR codes + native OS dialogs via built-in tools (no plugins):
// macOS: screencapture / osascript; Linux: zenity|kdialog, gnome-screenshot|spectacle|grim|import;
// Windows: PowerShell + WinForms dialogs, Snipping Tool (ms-screenclip:).
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// QR module matrix for [text] (true = dark).
List<List<bool>> qrMatrix(String text) {
  final m = Encoder.encode(text, ErrorCorrectionLevel.l).matrix!;
  return [
    for (var y = 0; y < m.height; y++)
      [for (var x = 0; x < m.width; x++) m.get(x, y) == 1],
  ];
}

/// Decodes the first QR code in an image file, or null.
Future<String?> decodeQrFile(String path) async {
  final im = img.decodeImage(await File(path).readAsBytes());
  if (im == null) return null;
  final px = Int32List(im.width * im.height);
  var i = 0;
  for (final p in im) {
    px[i++] =
        0xFF000000 | (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();
  }
  final bmp = BinaryBitmap(
    HybridBinarizer(RGBLuminanceSource(im.width, im.height, px)),
  );
  try {
    return QRCodeReader().decode(bmp).text;
  } catch (_) {
    return null;
  }
}

Future<bool> _has(String cmd) async =>
    (await Process.run('which', [cmd])).exitCode == 0;

/// Runs a PowerShell script in STA mode (needed for WinForms dialogs/clipboard).
Future<ProcessResult> _ps(String script) => Process.run('powershell', [
  '-NoProfile',
  '-STA',
  '-Command',
  'Add-Type -AssemblyName System.Windows.Forms,System.Drawing; $script',
]);

String _psq(String s) => "'${s.replaceAll("'", "''")}'";

Future<String> _tmp(String name) async =>
    '${(await Directory.systemTemp.createTemp('mimray')).path}/$name';

/// Android: camera QR scanner and system file picker (set by android_vpn.dart).
Future<String?> Function()? androidScanQr;
Future<String?> Function(String mime)? androidPickFile;

/// Desktop: lets the user drag a box around a QR on screen. Android: opens the
/// camera scanner. Returns the decoded text, or null if cancelled / not found.
/// Throws a readable message if no screenshot tool is available.
Future<String?> scanScreenQr() async {
  if (Platform.isAndroid) return androidScanQr!();
  final f = await _tmp('qr.png');
  if (Platform.isMacOS) {
    await Process.run('screencapture', ['-i', '-x', f]); // interactive region
  } else if (Platform.isWindows) {
    // Snipping Tool puts the selection on the clipboard; wait up to 60s for it
    await _ps(
      '[Windows.Forms.Clipboard]::Clear(); Start-Process "ms-screenclip:"; '
      'for (\$i = 0; \$i -lt 120; \$i++) { Start-Sleep -Milliseconds 500; '
      '\$img = [Windows.Forms.Clipboard]::GetImage(); '
      'if (\$img) { \$img.Save(${_psq(f)}, [Drawing.Imaging.ImageFormat]::Png); exit 0 } }; exit 1',
    );
  } else {
    final tools = <String, List<String>>{
      'gnome-screenshot': ['-a', '-f', f],
      'spectacle': ['-r', '-b', '-n', '-o', f],
      'flameshot': ['gui', '--raw'], // writes PNG to stdout
      'import': [f], // ImageMagick
    };
    String? used;
    for (final t in tools.keys) {
      if (await _has(t)) {
        used = t;
        break;
      }
    }
    if (used == null && await _has('grim') && await _has('slurp')) {
      final g = await Process.run('slurp', []);
      await Process.run('grim', ['-g', (g.stdout as String).trim(), f]);
    } else if (used == 'flameshot') {
      final r = await Process.run(
        'flameshot',
        tools[used]!,
        stdoutEncoding: null,
      );
      await File(f).writeAsBytes(r.stdout as List<int>);
    } else if (used != null) {
      await Process.run(used, tools[used]!);
    } else {
      throw 'No screenshot tool found. Install gnome-screenshot, spectacle, flameshot or grim+slurp.';
    }
  }
  if (!await File(f).exists()) return null; // cancelled
  return decodeQrFile(f);
}

/// Native "open file" dialog ([image]: pictures only on Android). Null if cancelled.
Future<String?> pickOpenFile(String title, {bool image = false}) async {
  if (Platform.isAndroid) return androidPickFile!(image ? 'image/*' : '*/*');
  final ProcessResult r;
  if (Platform.isMacOS) {
    r = await Process.run('osascript', [
      '-e',
      'POSIX path of (choose file with prompt "${_as(title)}")',
    ]);
  } else if (Platform.isWindows) {
    r = await _ps(
      '\$d = New-Object Windows.Forms.OpenFileDialog; \$d.Title = ${_psq(title)}; '
      'if (\$d.ShowDialog() -eq "OK") { \$d.FileName }',
    );
  } else if (await _has('zenity')) {
    r = await Process.run('zenity', ['--file-selection', '--title=$title']);
  } else if (await _has('kdialog')) {
    r = await Process.run('kdialog', [
      '--getopenfilename',
      '.',
      '--title',
      title,
    ]);
  } else {
    throw 'Install zenity or kdialog for file dialogs.';
  }
  final p = (r.stdout as String).trim();
  return r.exitCode == 0 && p.isNotEmpty ? p : null;
}

/// Native "save file" dialog, then writes [content]. Returns the path or null.
Future<String?> saveTextFile(String suggestedName, String content) async {
  if (Platform.isAndroid) {
    throw 'Saving files isn\'t available on Android yet — use Copy instead.';
  }
  final ProcessResult r;
  if (Platform.isMacOS) {
    r = await Process.run('osascript', [
      '-e',
      'POSIX path of (choose file name with prompt "Export" default name "${_as(suggestedName)}")',
    ]);
  } else if (Platform.isWindows) {
    r = await _ps(
      '\$d = New-Object Windows.Forms.SaveFileDialog; \$d.FileName = ${_psq(suggestedName)}; '
      '\$d.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*"; '
      'if (\$d.ShowDialog() -eq "OK") { \$d.FileName }',
    );
  } else if (await _has('zenity')) {
    r = await Process.run('zenity', [
      '--file-selection',
      '--save',
      '--confirm-overwrite',
      '--filename=$suggestedName',
    ]);
  } else if (await _has('kdialog')) {
    r = await Process.run('kdialog', ['--getsavefilename', suggestedName]);
  } else {
    // no dialog tool: drop it in ~/Downloads
    final p =
        '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE']}/Downloads/$suggestedName';
    await File(p).writeAsString(content);
    return p;
  }
  final p = (r.stdout as String).trim();
  if (r.exitCode != 0 || p.isEmpty) return null;
  await File(p).writeAsString(content);
  return p;
}

/// Show a file in Finder / Explorer / the file manager.
Future<void> reveal(String path) => Platform.isWindows
    ? Process.run('explorer', ['/select,', path.replaceAll('/', '\\')])
    : Process.run(
        Platform.isMacOS ? 'open' : 'xdg-open',
        Platform.isMacOS ? ['-R', path] : [File(path).parent.path],
      );

/// Android: set by android_vpn.dart (an ACTION_VIEW intent).
Future<void> Function(String url)? androidOpenUrl;

/// Opens an https [url] in the default browser.
Future<void> openUrl(String url) async {
  if (!url.startsWith('https://')) throw 'Refusing to open $url';
  if (Platform.isAndroid) return androidOpenUrl?.call(url);
  await Process.run(
    Platform.isMacOS
        ? 'open'
        : Platform.isWindows
        ? 'rundll32'
        : 'xdg-open',
    [if (Platform.isWindows) 'url.dll,FileProtocolHandler', url],
  );
}

String _as(String s) => s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
