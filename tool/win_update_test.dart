// Windows in-app update swap, for real: zip made like release.sh, a file kept
// locked for a while (like the elevated sing-box.exe), a pid to wait for,
// a non-ASCII path, and the relaunch. Run on Windows: dart run tool/win_update_test.dart
import 'dart:io';

import 'package:mimray/updater.dart';

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('mimray-up');
  final app = Directory('${root.path}\\برنامه app')..createSync();
  final src = Directory('${root.path}\\src')..createSync();
  File('${app.path}\\a.txt').writeAsStringSync('old');
  File('${src.path}\\a.txt').writeAsStringSync('new');
  Directory('${src.path}\\sub').createSync();
  File('${src.path}\\sub\\b.txt').writeAsStringSync('new');
  File(
    '${src.path}\\run.cmd',
  ).writeAsStringSync('echo hi> "%~dp0relaunched.txt"');
  final zip = '${root.path}\\u.zip';
  await _ps("Compress-Archive -Path '${src.path}\\*' -DestinationPath '$zip'");

  // holds a.txt exclusively for 6s; the swap must retry past it
  final lock = await Process.start('powershell', [
    '-NoProfile',
    '-Command',
    "\$f=[IO.File]::Open('${app.path}\\a.txt','Open','Read','None'); Start-Sleep 6; \$f.Close()",
  ]);
  await Future.delayed(const Duration(seconds: 1));
  final waitFor = await Process.start('ping', ['-n', '3', '127.0.0.1']);

  final ps = File('${root.path}\\update.ps1');
  final log = '${root.path}\\update.log';
  ps.writeAsStringSync(
    '﻿${winUpdateScript(waitFor.pid, zip, app.path, '${app.path}\\run.cmd', log)}',
  );
  final r = await Process.run('powershell', [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    ps.path,
  ]);
  await lock.exitCode;
  final relaunched = File('${app.path}\\relaunched.txt');
  for (var i = 0; i < 20 && !relaunched.existsSync(); i++) {
    await Future.delayed(const Duration(milliseconds: 500));
  }
  final logText = File(log).readAsStringSync();
  stdout.writeln(logText);
  void check(bool ok, String what) {
    if (!ok) {
      stderr.writeln('FAIL: $what\n${r.stdout}\n${r.stderr}');
      exit(1);
    }
  }

  check(
    File('${app.path}\\a.txt').readAsStringSync() == 'new',
    'a.txt replaced',
  );
  check(
    File('${app.path}\\sub\\b.txt').readAsStringSync() == 'new',
    'sub/b.txt',
  );
  check(logText.contains('attempt 1 failed'), 'retried past the lock');
  check(logText.contains('updated'), 'log says updated');
  check(relaunched.existsSync(), 'relaunched');
  stdout.writeln('win update swap OK');
}

Future<void> _ps(String cmd) async {
  final r = await Process.run('powershell', ['-NoProfile', '-Command', cmd]);
  if (r.exitCode != 0) throw '${r.stdout}${r.stderr}';
}
