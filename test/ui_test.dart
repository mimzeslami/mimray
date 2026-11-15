import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimray/main.dart';

void main() {
  for (final size in [
    const Size(380, 600),
    const Size(420, 760),
    const Size(1000, 700),
  ]) {
    testWidgets('renders without overflow at $size', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MaterialApp(home: Home()));
      await t.pump();
      expect(find.text('mimray'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
