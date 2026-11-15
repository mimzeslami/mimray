// Android: the VPN runs in MimrayVpnService (Kotlin + sing-box libbox).
// This wires it into Core via the platformVpn hook; desktop never loads it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'core.dart';
import 'native.dart';
import 'updater.dart';

const _method = MethodChannel('mimray/vpn');
const _events = EventChannel('mimray/vpn/events');

Future<void> initAndroidVpn() async {
  if (!Platform.isAndroid) return;
  appDir = await _method.invokeMethod<String>('filesDir') ?? appDir;
  installApk = (path) =>
      _method.invokeMethod<void>('installApk', {'path': path});
  androidOpenUrl = (url) => _method.invokeMethod<void>('openUrl', {'url': url});
  androidScanQr = () => _method.invokeMethod<String>('scanQr');
  androidPickFile = (mime) =>
      _method.invokeMethod<String>('pickFile', {'mime': mime});
  androidSaveFile = (name, content) => _method.invokeMethod<String>(
    'saveFile',
    {'name': name, 'content': content},
  );
  void Function(int)? onExit;

  void log(String line) {
    try {
      File(
        '$appDir/core.log',
      ).writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {}
  }

  _events.receiveBroadcastStream().listen((e) {
    final m = Map<String, dynamic>.from(e as Map);
    if (m['status'] != 'stopped') return;
    final err = m['error'] as String?;
    if (err != null) log(err);
    final f = onExit;
    onExit = null;
    f?.call(err == null ? 0 : 1);
  });

  platformVpn = (
    start: (config, exit) async {
      File('$appDir/core.log').writeAsStringSync('');
      onExit = exit;
      final ok = await _method.invokeMethod<bool>('start', {
        'config': jsonEncode(config),
      });
      if (ok != true) {
        log('VPN permission was declined');
        onExit = null;
        exit(1);
      }
    },
    stop: () => _method.invokeMethod<void>('stop'),
  );
}
