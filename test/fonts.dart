import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the bundled Geist fonts (and Material Icons from the Flutter SDK) so
/// tests measure and render text like the app does, instead of the Ahem
/// test font.
Future<void> loadFonts() async {
  final geist = FontLoader('Geist');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    geist.addFont(rootBundle.load('assets/fonts/Geist-$w.ttf'));
  }
  await geist.load();
  final mono = FontLoader('GeistMono');
  for (final w in ['Regular', 'Medium']) {
    mono.addFont(rootBundle.load('assets/fonts/GeistMono-$w.ttf'));
  }
  await mono.load();
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      File(
        Platform.resolvedExecutable,
      ).parent.parent.parent.parent.parent.parent.path;
  final icons = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
  }
}
