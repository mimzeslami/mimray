// Renders every main screen / sheet with the real fonts to
// build/redesign_shots/*.png (2x) for visual review against the design.
//   flutter test --run-skipped --tags shots test/shots_test.dart
@Tags(['shots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimray/main.dart';

import 'fonts.dart';
import 'sample.dart';

final _key = GlobalKey();

Future<void> shot(
  WidgetTester t,
  String name,
  Map<String, dynamic> d, {
  bool mobile = false,
  Future<void> Function()? then,
}) async {
  final size = mobile ? const Size(390, 844) : const Size(360, 600);
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  if (mobile) {
    t.view.padding = const FakeViewPadding(top: 47 * 2, bottom: 34 * 2);
  }
  addTearDown(t.view.reset);
  await t.pumpWidget(
    RepaintBoundary(
      key: _key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme,
        home: Home(demo: d, mobile: mobile),
      ),
    ),
  );
  Future<void> settle() async {
    for (var i = 0; i < 3; i++) {
      await t.runAsync(
        () => Future.delayed(const Duration(milliseconds: 150)),
      ); // flag SVGs
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  await settle();
  if (then != null) {
    await then();
    await settle();
  }
  expect(t.takeException(), isNull);
  // autoUpdateGoldenFiles: the golden comparator just writes the PNG
  await expectLater(
    find.byKey(_key),
    matchesGoldenFile('../build/redesign_shots/$name.png'),
  );
}

void main() {
  setUpAll(() async {
    autoUpdateGoldenFiles = true;
    await loadFonts();
  });

  Future<void> Function() tap(WidgetTester t, Finder f) => () async {
    await t.tap(f.first);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  };

  // Desktop D1–D12
  testWidgets('D1 off mac', (t) => shot(t, 'D01_off_mac', demo()));
  testWidgets(
    'D2 connecting win',
    (t) => shot(
      t,
      'D02_connecting_win',
      demo(phase: 'connecting', os: 'win', sel: 2, expanded: ['NL']),
    ),
  );
  testWidgets(
    'D3 on linux',
    (t) => shot(t, 'D03_on_linux', demo(phase: 'on', os: 'linux')),
  );
  testWidgets(
    'D4 favorites',
    (t) => shot(t, 'D04_favorites', demo(tab: 'fav', sel: 0)),
  );
  testWidgets(
    'D5 add',
    (t) => shot(
      t,
      'D05_add',
      demo(),
      then: tap(t, find.byIcon(Icons.add_rounded)),
    ),
  );
  testWidgets(
    'D6 subscription',
    (t) => shot(
      t,
      'D06_subscription',
      demo(),
      then: tap(t, find.text('Nova Premium')),
    ),
  );
  testWidgets(
    'D7 preferences',
    (t) => shot(t, 'D07_preferences', demo(view: 'prefs')),
  );
  testWidgets(
    'D7b preferences connected',
    (t) => shot(
      t,
      'D07b_preferences_on',
      demo(view: 'prefs', phase: 'on', helper: false),
    ),
  );
  testWidgets(
    'D8 server',
    (t) => shot(
      t,
      'D08_server',
      demo(expanded: ['NL']),
      then: tap(t, find.byIcon(Icons.more_horiz_rounded)),
    ),
  );
  testWidgets(
    'D9 stats',
    (t) => shot(
      t,
      'D09_stats',
      demo(phase: 'on'),
      then: tap(t, find.byIcon(Icons.chevron_right_rounded)),
    ),
  );
  testWidgets(
    'D10 log',
    (t) => shot(
      t,
      'D10_log',
      demo(phase: 'on', view: 'prefs'),
      then: () async {
        await t.scrollUntilVisible(
          find.text('Core log'),
          100,
          scrollable: find.byType(Scrollable).last,
        );
        await tap(t, find.text('Core log'))();
      },
    ),
  );
  testWidgets(
    'D11 first run',
    (t) => shot(t, 'D11_first_run', demo(empty: true)),
  );
  testWidgets(
    'D13 recent',
    (t) => shot(t, 'D13_recent', demo(tab: 'recent', sel: 7)),
  );
  testWidgets(
    'D14 other group',
    (t) => shot(
      t,
      'D14_other',
      demo(expanded: ['US', '']),
      then: () async {
        await t.scrollUntilVisible(find.text('Backup node'), 200);
      },
    ),
  );

  // Mobile M1–M9
  testWidgets(
    'M1 home off',
    (t) => shot(t, 'M01_home_off', demo(), mobile: true),
  );
  testWidgets(
    'M2 home connecting',
    (t) => shot(
      t,
      'M02_home_connecting',
      demo(phase: 'connecting', sel: 2),
      mobile: true,
    ),
  );
  testWidgets(
    'M3 home on',
    (t) => shot(t, 'M03_home_on', demo(phase: 'on'), mobile: true),
  );
  testWidgets(
    'M4 locations',
    (t) => shot(t, 'M04_locations', demo(nav: 1), mobile: true),
  );
  testWidgets(
    'M5 favorites',
    (t) => shot(
      t,
      'M05_favorites',
      demo(nav: 1, tab: 'fav', sel: 0),
      mobile: true,
    ),
  );
  testWidgets(
    'M6 settings',
    (t) => shot(t, 'M06_settings', demo(nav: 2), mobile: true),
  );
  testWidgets(
    'M7 add',
    (t) => shot(
      t,
      'M07_add',
      demo(nav: 1),
      mobile: true,
      then: tap(t, find.byIcon(Icons.add_rounded)),
    ),
  );
  testWidgets(
    'M8 subscription',
    (t) => shot(
      t,
      'M08_subscription',
      demo(),
      mobile: true,
      then: tap(t, find.text('Data used')),
    ),
  );
  testWidgets(
    'M9 server',
    (t) => shot(
      t,
      'M09_server',
      demo(nav: 1),
      mobile: true,
      then: tap(t, find.byIcon(Icons.more_horiz_rounded)),
    ),
  );
  testWidgets(
    'M10 stats',
    (t) => shot(
      t,
      'M10_stats',
      demo(phase: 'on'),
      mobile: true,
      then: tap(t, find.text('Download')),
    ),
  );
  testWidgets(
    'M11 log',
    (t) => shot(
      t,
      'M11_log',
      demo(nav: 2),
      mobile: true,
      then: () async {
        await t.drag(find.byType(ListView).first, const Offset(0, -600));
        await t.pump(const Duration(milliseconds: 300));
        await tap(t, find.text('Core log'))();
      },
    ),
  );
  testWidgets(
    'M12 first run',
    (t) => shot(t, 'M12_first_run', demo(empty: true), mobile: true),
  );
}
