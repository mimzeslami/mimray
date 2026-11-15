import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimray/main.dart';

import 'fonts.dart';
import 'sample.dart';

const desktop = Size(360, 600), phone = Size(390, 844);

Future<void> show(
  WidgetTester t,
  Size size,
  Map<String, dynamic> d, {
  bool mobile = false,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: appTheme,
      home: Home(demo: d, mobile: mobile),
    ),
  );
  await t.pump(const Duration(milliseconds: 500));
}

/// Pump past sheet / panel animations (infinite power animations rule out pumpAndSettle).
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapAndSettle(WidgetTester t, Finder f) async {
  await t.tap(f.first);
  await settle(t);
  expect(t.takeException(), isNull);
}

void main() {
  setUpAll(loadFonts);

  for (final phase in ['off', 'connecting', 'on']) {
    for (final empty in [true, false]) {
      testWidgets('desktop renders: $phase empty=$empty', (t) async {
        await show(t, desktop, demo(phase: phase, empty: empty));
        expect(t.takeException(), isNull);
        expect(
          find.text(empty ? 'Add your first server' : 'Germany'),
          findsOneWidget,
        );
        if (!empty) {
          await t.scrollUntilVisible(
            find.text('Other'),
            200,
          ); // unflagged group
          expect(t.takeException(), isNull);
        }
      });
      testWidgets('mobile renders: $phase empty=$empty', (t) async {
        await show(t, phone, demo(phase: phase, empty: empty), mobile: true);
        expect(t.takeException(), isNull);
        expect(
          find.text(empty ? 'Add your first server' : 'LOCATION'),
          findsOneWidget,
        );
      });
    }
  }

  for (final phase in ['off', 'on']) {
    testWidgets('update banner fits: desktop + mobile, $phase', (t) async {
      final d = {...demo(phase: phase), '_update': '9.9.9'};
      await show(t, desktop, d);
      expect(find.text('mimray 9.9.9 is available'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
      expect(t.takeException(), isNull);
      await show(t, phone, d, mobile: true);
      expect(find.text('mimray 9.9.9 is available'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('old state files (no favorites/recent, v1 layout) still load', (
    t,
  ) async {
    final d = demo();
    final old = {
      'servers': (d['subs'] as List).first['servers'],
      'sub': '',
      'sel': 1,
    };
    await show(t, desktop, old);
    expect(t.takeException(), isNull);
    expect(find.text('Berlin'), findsWidgets); // selected, group auto-expanded
    await tapAndSettle(t, find.byTooltip('Favorites'));
    expect(find.text('Frankfurt'), findsNothing);
  });

  testWidgets('desktop: os title controls', (t) async {
    await show(t, desktop, demo(os: 'win'));
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
  });

  testWidgets('desktop: tabs, groups, favorites', (t) async {
    await show(t, desktop, demo());
    expect(find.text('Frankfurt'), findsOneWidget); // DE expanded
    expect(find.text('Amsterdam'), findsNothing);
    await tapAndSettle(t, find.text('Netherlands'));
    expect(find.text('Amsterdam'), findsOneWidget);
    await tapAndSettle(t, find.byTooltip('Favorites'));
    expect(find.text('Helsinki'), findsOneWidget);
    expect(
      find.textContaining('on any location to pin it here', findRichText: true),
      findsOneWidget,
    );
    await tapAndSettle(t, find.byTooltip('Recent'));
    expect(find.text('New York'), findsOneWidget);
    await tapAndSettle(t, find.byTooltip('All'));
    await tapAndSettle(t, find.byIcon(Icons.search_rounded));
    await t.enterText(find.byType(TextField), 'tok');
    await settle(t);
    expect(find.text('Tokyo'), findsOneWidget);
    expect(find.text('Frankfurt'), findsNothing);
  });

  testWidgets('desktop: star toggles favorite', (t) async {
    await show(t, desktop, demo(tab: 'fav'));
    expect(find.text('Helsinki'), findsOneWidget);
    await tapAndSettle(t, find.byIcon(Icons.star_rounded).last);
    expect(find.text('Helsinki'), findsNothing);
  });

  testWidgets('desktop: every sheet and panel opens', (t) async {
    await show(t, desktop, demo(phase: 'on'));
    await tapAndSettle(t, find.text('Nova Premium'));
    expect(find.text('SWITCH SUBSCRIPTION'), findsOneWidget);
    await t.tapAt(const Offset(180, 20));
    await settle(t);
    await tapAndSettle(t, find.byIcon(Icons.more_horiz_rounded));
    expect(find.text('PROTOCOL'), findsOneWidget);
    expect(find.text('Delete server'), findsNothing); // locked while connected
    await t.tapAt(const Offset(180, 20));
    await settle(t);
    await tapAndSettle(t, find.byIcon(Icons.chevron_right_rounded));
    expect(find.text('LAST 60 SECONDS'), findsOneWidget);
    await t.tapAt(const Offset(180, 20));
    await settle(t);
    await tapAndSettle(t, find.byIcon(Icons.tune_rounded));
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Changes apply on next connect.'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Core log'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tapAndSettle(t, find.text('Core log'));
    expect(find.textContaining('WARN outbound'), findsOneWidget);
  });

  testWidgets('desktop: add sheet (off)', (t) async {
    await show(t, desktop, demo());
    await tapAndSettle(t, find.byIcon(Icons.add_rounded));
    expect(find.text('Subscription URL'), findsOneWidget);
    expect(find.text('Scan QR on screen'), findsOneWidget);
  });

  testWidgets('desktop: selection locked while connected', (t) async {
    await show(t, desktop, demo(phase: 'on', sel: 1));
    await tapAndSettle(t, find.text('Frankfurt'));
    expect(find.text('Berlin'), findsWidgets); // still the title
    expect(find.text('Frankfurt'), findsOneWidget);
  });

  testWidgets('mobile: tabs and sheets', (t) async {
    await show(t, phone, demo(phase: 'on'), mobile: true);
    await tapAndSettle(t, find.text('Download'));
    expect(find.text('Connection'), findsOneWidget);
    await t.tapAt(const Offset(195, 40));
    await settle(t);
    await tapAndSettle(t, find.text('Data used'));
    expect(find.text('Copy links'), findsOneWidget);
    await t.tapAt(const Offset(195, 40));
    await settle(t);
    await tapAndSettle(t, find.text('Locations').last);
    expect(find.text('Search city or country'), findsOneWidget);
    await tapAndSettle(t, find.byIcon(Icons.more_horiz_rounded));
    expect(find.text('Copy link'), findsOneWidget);
    await t.tapAt(const Offset(195, 40));
    await settle(t);
    await tapAndSettle(t, find.text('Settings').last);
    expect(find.text('SUBSCRIPTIONS'), findsOneWidget);
    await t.drag(find.byType(ListView).first, const Offset(0, -600));
    await settle(t);
    await tapAndSettle(t, find.text('Core log'));
    expect(find.textContaining('WARN outbound'), findsOneWidget);
  });

  testWidgets('mobile: add sheet (off) + picking a node returns home', (
    t,
  ) async {
    await show(t, phone, demo(), mobile: true);
    await tapAndSettle(t, find.text('Locations').last);
    await tapAndSettle(t, find.text('Berlin'));
    expect(find.text('Berlin, Germany'), findsOneWidget);
    await tapAndSettle(t, find.text('Locations').last);
    await tapAndSettle(t, find.byIcon(Icons.add_rounded));
    expect(find.text('Add subscription'), findsOneWidget);
  });

  group('Free tab', () {
    for (final (name, size, mobile) in [
      ('desktop', desktop, false),
      ('mobile', phone, true),
    ]) {
      for (final st in ['off', 'empty', 'testing', 'loaded']) {
        testWidgets('$name renders: $st', (t) async {
          await show(
            t,
            size,
            demo(tab: 'free', nav: mobile ? 1 : 0, free: st),
            mobile: mobile,
          );
          expect(t.takeException(), isNull);
          switch (st) {
            case 'off':
              expect(find.text('Turn on free servers'), findsOneWidget);
            case 'empty':
              expect(find.text('Not tested yet'), findsOneWidget);
              expect(find.text('Not tested yet. Tap Update.'), findsOneWidget);
            case 'testing':
              expect(find.text('Testing 37/200…'), findsOneWidget);
            case 'loaded':
              expect(find.text('Updated 12 min ago'), findsOneWidget);
              expect(find.text('6 working'), findsOneWidget);
              await t.scrollUntilVisible(
                find.text('Fast DE server for students'),
                200,
                scrollable: find.byType(Scrollable).last,
              );
              expect(find.textContaining('by alice'), findsOneWidget);
          }
          await t.scrollUntilVisible(
            find.text('Share your server'),
            200,
            scrollable: find.byType(Scrollable).last,
          );
          expect(t.takeException(), isNull);
        });
      }
      testWidgets('$name: Android-style "reachable" label', (t) async {
        await show(
          t,
          size,
          demo(
            tab: 'free',
            nav: mobile ? 1 : 0,
            free: 'loaded',
            reachOnly: true,
          ),
          mobile: mobile,
        );
        expect(find.text('6 reachable'), findsOneWidget);
      });
    }

    testWidgets('opt-in needs the warning to be accepted', (t) async {
      await show(t, desktop, demo(tab: 'free'));
      await tapAndSettle(t, find.text('Turn on free servers'));
      expect(find.text('Before you turn this on'), findsOneWidget);
      expect(find.textContaining('logins, banking'), findsWidgets);
      expect(
        find.textContaining('reviewed before they appear'),
        findsOneWidget,
      );
      await tapAndSettle(t, find.text('Cancel'));
      expect(find.text('Turn on free servers'), findsOneWidget); // still off
      await tapAndSettle(t, find.text('Turn on free servers'));
      await tapAndSettle(t, find.text('I understand, turn on'));
      expect(find.text('Not tested yet'), findsOneWidget);
    });

    testWidgets('picking a free server: header shows it with a FREE badge', (
      t,
    ) async {
      await show(t, desktop, demo(tab: 'free', free: 'loaded'));
      await tapAndSettle(t, find.text('NL Free'));
      expect(find.text('NL Free'), findsNWidgets(2)); // header + row
      expect(find.text('FREE'), findsWidgets);
      await tapAndSettle(t, find.byTooltip('All'));
      expect(find.text('NL Free'), findsOneWidget); // still the pool in use
    });

    testWidgets('connected on Free: no re-test, locked selection', (t) async {
      await show(
        t,
        desktop,
        demo(tab: 'free', free: 'loaded', onFree: true, phase: 'on'),
      );
      expect(find.text('Disconnect to re-test'), findsOneWidget);
      expect(find.text('Auto · DE Free 1'), findsOneWidget);
    });

    testWidgets('Preferences switch turns it off and removes the list', (
      t,
    ) async {
      await show(t, desktop, demo(free: 'loaded', view: 'prefs'));
      await t.scrollUntilVisible(
        find.text('Free servers (community)'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Auto-update'), findsOneWidget);
      await tapAndSettle(t, find.text('Free servers (community)'));
      expect(find.text('Auto-update'), findsNothing);
      await tapAndSettle(t, find.byIcon(Icons.arrow_back_rounded));
      await tapAndSettle(t, find.byTooltip('Free'));
      expect(find.text('Turn on free servers'), findsOneWidget);
    });

    testWidgets('share warns that the link becomes public', (t) async {
      await show(t, phone, demo(nav: 1, tab: 'free'), mobile: true);
      await tapAndSettle(t, find.text('Share your server'));
      expect(find.textContaining('PUBLIC'), findsOneWidget);
      expect(find.text('Continue on GitHub'), findsOneWidget);
      await tapAndSettle(t, find.text('Frankfurt'));
      await tapAndSettle(t, find.text('Cancel'));
    });

    testWidgets('first run links to the Free tab', (t) async {
      await show(t, desktop, demo(empty: true));
      await tapAndSettle(t, find.text('Or try free servers'));
      expect(find.text('Turn on free servers'), findsOneWidget);
    });
  });
}
