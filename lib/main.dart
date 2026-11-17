import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'android_vpn.dart';
import 'core.dart';
import 'countries.dart';
import 'free.dart';
import 'links.dart';
import 'native.dart';
import 'updater.dart' as updater;

part 'ui/kit.dart';
part 'ui/shared.dart';
part 'ui/list.dart';
part 'ui/desktop.dart';
part 'ui/mobile.dart';
part 'ui/free_tab.dart';

const appVersion = '0.5.4';

bool get _desktopOs =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAndroidVpn(); // no-op on desktop
  if (_desktopOs) {
    await windowManager.ensureInitialized();
    // macOS and Linux are frameless + fixed natively (MainFlutterWindow.swift,
    // my_application.cc); Windows goes through window_manager.
    if (Platform.isWindows) {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await windowManager.setResizable(false);
      await windowManager.setMaximizable(false);
    }
  }
  runApp(
    MaterialApp(
      title: 'mimray',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      home: const Home(),
    ),
  );
}

enum Phase { off, connecting, on }

/// A subscription (https URL) or the local list (src == '') of imported servers.
class Sub {
  String name, src;
  List<Server> servers;
  Map<String, int> usage;
  Sub(this.name, this.src, [List<Server>? servers, Map<String, int>? usage])
    : servers = servers ?? [],
      usage = usage ?? {};
  bool get local => src.isEmpty;
  Map<String, dynamic> toJson() => {
    'name': name,
    'src': src,
    'servers': servers,
    'usage': usage,
  };
  factory Sub.fromJson(Map j) => Sub(j['name'], j['src'] ?? '', [
    for (final s in j['servers']) Server.fromJson(s),
  ], Map<String, int>.from(j['usage'] ?? {}));
}

class Home extends StatefulWidget {
  /// [mobile] picks the shell (default: Android/iOS). [demo] = state.json
  /// content for tests/screenshots: nothing is read, saved, pinged or
  /// started; `_`-prefixed keys fake runtime state (see `_applyDemo`).
  const Home({super.key, this.mobile, this.demo});
  final bool? mobile;
  final Map<String, dynamic>? demo;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with TrayListener {
  final core = Core();
  final state = File('$appDir/state.json');
  List<Sub> subs = [];
  Settings opt = Settings();
  int cur = 0; // current subscription
  int selected = -1; // -1 = Auto (best server)
  Map<int, int?> pings = {};
  bool busy = false;
  String? helper; // helper version when installed (no password prompts)
  updater.Update? update; // newer release available
  double? updateProgress;
  bool checkingUpdate = false; // non-null while downloading
  Timer? _updateTimer;
  String? msg;

  Phase phase = Phase.off;
  DateTime? since;
  Stats? stats;
  Map<String, dynamic>? ip;
  final down = <double>[], up = <double>[]; // last 60s rates
  Timer? _tick;

  // redesign state
  Set<String> favorites = {}; // server ids (see _id)
  List<String> recent = []; // last connected server ids, newest first
  String tab = 'all'; // all | fav | recent | free
  final expanded = <String>{}; // open country groups ('' = Other)
  String query = '';
  bool searching = false;
  String view = 'main'; // desktop overlay: main | prefs
  int nav = 0; // mobile tab: home | locations | settings
  String logText = '';
  final _rev = ValueNotifier(0); // bumps on every setState: keeps sheets live

  // free servers (opt-in): working public + community servers, tested here
  bool freeOn = false, freeAuto = true;
  List<FreeServer> free = [], shared = []; // sorted by delay
  DateTime? freeUpdated;
  bool freeBusy = false;
  String? freeStatus; // "Testing 37/200…" while updating
  double? freeProgress;
  Timer? _freeTimer;

  /// The connect pool is the free list (selected then indexes [freePool]).
  bool onFree = false;
  List<FreeServer> get freePool => [...free, ...shared];

  /// Servers the power button connects to: the current subscription, or Free.
  List<Server> get pool =>
      onFree ? [for (final f in freePool) f.server] : servers;

  /// Selection inside the subscription lists (-2 = none: Free is in use).
  int get subSel => onFree ? -2 : selected;

  /// Android has no core binary to test with: TCP reachability only.
  bool get reachOnly =>
      Platform.isAndroid || widget.demo?['_reachOnly'] == true;

  bool get demo => widget.demo != null;
  bool get mobile => widget.mobile ?? (Platform.isAndroid || Platform.isIOS);
  String get os =>
      widget.demo?['_os'] ??
      (Platform.isMacOS
          ? 'mac'
          : Platform.isWindows
          ? 'win'
          : 'linux');
  bool get helperAvailable => demo
      ? helper != null || widget.demo!['_helperBundled'] == true
      : helperBundled;

  List<Server> get servers => subs.isEmpty ? const [] : subs[cur].servers;
  bool get locked => phase != Phase.off;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _rev.value++;
    _syncTray();
  }

  /// setState for the UI parts (extensions can't call the protected one).
  void rebuild([VoidCallback? fn]) => setState(fn ?? () {});

  @override
  void initState() {
    super.initState();
    if (widget.demo case final d?) {
      _applyState(d);
      _applyDemo(d);
      return;
    }
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    _checkHelper();
    if (!mobile && _desktopOs) _initTray();
    _freeTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _autoFree(),
    );
    // check shortly after launch, then every 6 hours (cancellable timers)
    _updateTimer = Timer(const Duration(seconds: 5), _checkUpdate);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _updateTimer?.cancel();
    _freeTimer?.cancel();
    if (!demo) {
      stopCoreTest();
      core.stop();
      if (_trayReady) trayManager.removeListener(this);
    }
    super.dispose();
  }

  // ---------- persistence ----------

  Future<void> _load() async {
    try {
      final j = jsonDecode(await state.readAsString());
      setState(() => _applyState(j));
      _pingAll();
      if (opt.autoConnect && pool.isNotEmpty) {
        _toggle();
      } else {
        Timer(const Duration(seconds: 10), _autoFree);
      }
    } catch (_) {}
  }

  void _applyState(Map j) {
    if (j['subs'] != null) {
      subs = [for (final s in j['subs']) Sub.fromJson(s)];
    } else if (j['servers'] != null) {
      // migrate v1 single-subscription state
      subs = [
        Sub.fromJson({...j, 'name': 'My VPN', 'src': j['sub'] ?? ''}),
      ];
    }
    opt = Settings.fromJson(j['settings']);
    cur = ((j['cur'] ?? 0) as int).clamp(0, subs.isEmpty ? 0 : subs.length - 1);
    favorites = {...?(j['favorites'] as List?)?.cast<String>()};
    recent = [...?(j['recent'] as List?)?.cast<String>()];
    if (j['free'] case final Map f) {
      freeOn = f['on'] == true;
      freeAuto = f['auto'] != false;
      List<FreeServer> list(Object? l) => [
        for (final e in (l is List ? l : const []))
          if (e is Map) ?FreeServer.fromJson(e),
      ];
      free = list(f['servers']);
      shared = list(f['shared']);
      freeUpdated = f['updated'] is int
          ? DateTime.fromMillisecondsSinceEpoch(f['updated'])
          : null;
      onFree = freeOn && f['pool'] == true;
    }
    selected = j['sel'] ?? -1;
    if (selected >= pool.length) selected = -1;
    if (subSel >= 0) expanded.add(_group(servers[selected]));
  }

  /// Test/screenshot state: `_phase`, `_pings`, `_stats` [up, down, upRate,
  /// downRate, conns, active], `_ip`, `_uptime` (s), `_helper`, `_log`, `_tab`,
  /// `_expanded`, `_os`, `_nav`, `_view`, `_freeStatus`, `_freeProgress`,
  /// `_reachOnly`.
  void _applyDemo(Map d) {
    phase = Phase.values.byName(d['_phase'] ?? 'off');
    pings = {
      for (final (i, v) in ((d['_pings'] as List?) ?? const []).indexed) i: v,
    };
    helper = d['_helper'];
    if (d['_update'] case final String v) {
      update = updater.Update(v, '', '', '', '', '');
    }
    logText = d['_log'] ?? '';
    freeStatus = d['_freeStatus'];
    freeBusy = freeStatus != null;
    freeProgress = d['_freeProgress'];
    tab = d['_tab'] ?? 'all';
    nav = d['_nav'] ?? 0;
    view = d['_view'] ?? 'main';
    expanded.addAll(((d['_expanded'] as List?) ?? const []).cast<String>());
    if (phase == Phase.on) {
      since = DateTime.now().subtract(Duration(seconds: d['_uptime'] ?? 754));
      ip = d['_ip'];
      if (d['_stats'] case final List s) {
        stats = Stats(s[0], s[1], s[2], s[3], s[4], s.length > 5 ? s[5] : null);
      }
      for (var i = 0; i < 60; i++) {
        down.add(
          4e6 * (.55 + .45 * math.sin(i * .37 + 1) * math.cos(i * .13 + 2)),
        );
        up.add(
          4e5 * (.55 + .45 * math.sin(i * .37 + 4) * math.cos(i * .13 + 8)),
        );
      }
    }
  }

  Future<void> _save() async {
    if (demo) return;
    await Directory(appDir).create(recursive: true);
    await state.writeAsString(
      jsonEncode({
        'subs': subs,
        'cur': cur,
        'sel': selected,
        'settings': opt,
        'favorites': favorites.toList(),
        'recent': recent,
        'free': {
          'on': freeOn,
          'auto': freeAuto,
          'pool': onFree,
          'updated': freeUpdated?.millisecondsSinceEpoch,
          'servers': free,
          'shared': shared,
        },
      }),
    );
    await privateFile(state.path); // holds credentials
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(t),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

  // ---------- servers: ids, groups, favorites ----------

  /// Stable server id for favorites/recent: survives renames and re-fetches.
  // ponytail: two nodes on the same type+host+port share a star; add the path if that bites.
  String _id(Server s) => serverKey(s);

  String _group(Server s) => _cc(s.name) ?? '';

  bool _match(int i) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase(), s = servers[i];
    return s.name.toLowerCase().contains(q) ||
        s.host.toLowerCase().contains(q) ||
        countryName(_cc(s.name)).toLowerCase().contains(q);
  }

  /// Servers grouped by flag country, in list order; unflagged ('') last.
  List<(String, List<int>)> get groups {
    final m = <String, List<int>>{};
    for (var i = 0; i < servers.length; i++) {
      if (_match(i)) m.putIfAbsent(_group(servers[i]), () => []).add(i);
    }
    final other = m.remove('');
    return [
      for (final e in m.entries) (e.key, e.value),
      ?(other == null ? null : ('', other)),
    ];
  }

  /// Favorites / Recent tab rows (current subscription).
  List<int> get flat {
    final ids = [for (final s in servers) _id(s)];
    final l = tab == 'fav'
        ? [
            for (var i = 0; i < servers.length; i++)
              if (favorites.contains(ids[i])) i,
          ]
        : [
            for (final r in recent) ids.indexOf(r),
          ].where((i) => i >= 0).toList();
    return l.where(_match).toList();
  }

  bool isFav(int i) => favorites.contains(_id(servers[i]));

  void toggleFav(int i) {
    final id = _id(servers[i]);
    setState(
      () => favorites.contains(id) ? favorites.remove(id) : favorites.add(id),
    );
    _save();
  }

  void pick(int i) {
    if (locked) return;
    setState(() {
      onFree = false;
      selected = i;
      if (mobile) nav = 0;
    });
    _save();
  }

  void toggleGroup(String cc) => setState(
    () => expanded.contains(cc) ? expanded.remove(cc) : expanded.add(cc),
  );

  bool get allOpen => groups.every((g) => expanded.contains(g.$1));

  /// Expand every country group, or collapse all if they're already open.
  void toggleAll() => setState(
    () => allOpen ? expanded.clear() : expanded.addAll(groups.map((g) => g.$1)),
  );

  /// Server in use: the selected one, or the one Auto picked once connected.
  int? get activeIndex {
    final p = pool;
    if (p.isEmpty) return null;
    if (selected >= 0) return selected;
    final a = phase == Phase.on ? stats?.active : null;
    return a != null && a < p.length ? a : null;
  }

  String get locTitle {
    final p = pool;
    if (p.isEmpty) return onFree ? 'No free servers yet' : 'No servers yet';
    if (selected >= 0) return _clean(p[selected].name);
    final a = activeIndex;
    return a == null
        ? (onFree ? 'Auto · free server' : 'Auto · best server')
        : 'Auto · ${_clean(p[a].name)}';
  }

  String get locSub => switch (phase) {
    Phase.on when ip == null => 'Checking exit IP…',
    Phase.on => [
      ip!['ip'],
      [
        ip!['city'],
        if (ip!['country'] is String) countryName(ip!['country']),
      ].whereType<String>().join(', '),
    ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
    Phase.connecting => 'Waiting for permission…',
    Phase.off =>
      pool.isEmpty
          ? 'Add a server to start'
          : mobile
          ? 'Tap to connect'
          : 'Not connected',
  };

  // ---------- subscriptions & import ----------

  /// Fetch an https subscription. Local lists have nothing to fetch.
  Future<void> _refresh(Sub sub) async {
    if (sub.local) return;
    final uri = Uri.parse(sub.src.trim());
    if (uri.scheme != 'https') {
      throw 'Subscription must be https (http leaks your credentials)';
    }
    final c = HttpClient()
      ..userAgent = 'mimray'
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final res = await (await c.getUrl(uri)).close();
      if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
      final info = parseUserinfo(res.headers.value('subscription-userinfo'));
      final list = parseImport(await res.transform(utf8.decoder).join());
      if (list.isEmpty) throw 'No supported servers found';
      sub.servers = list;
      sub.usage = info;
    } finally {
      c.close();
    }
  }

  Future<void> _run(Future<void> Function() f) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await f();
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _updateAll() => _run(() async {
    var n = 0;
    for (final s in subs.where((s) => !s.local)) {
      await _refresh(s);
      n++;
    }
    await _save();
    setState(() {});
    _pingAll();
    _toast(
      n == 0 ? 'No subscriptions to update' : 'Updated $n subscription(s)',
    );
  });

  /// Text from clipboard / QR / file: a subscription URL, or servers.
  Future<void> _importText(String? text, String from) => _run(() async {
    final t = (text ?? '').trim();
    if (t.isEmpty) throw 'Nothing found in $from';
    if (RegExp(r'^https?://\S+$').hasMatch(t)) {
      final uri = Uri.parse(t);
      final sub = Sub(uri.host, t);
      await _refresh(sub);
      subs.add(sub);
      _select(subs.length - 1);
      _toast('Added subscription · ${sub.servers.length} servers');
      return;
    }
    final list = parseImport(t);
    if (list.isEmpty) throw 'No supported servers in $from';
    var i = subs.indexWhere((s) => s.local);
    if (i < 0) {
      subs.add(Sub('Local', ''));
      i = subs.length - 1;
    }
    subs[i].servers.addAll(list);
    _select(i);
    _toast('Imported ${list.length} server(s) from $from');
  });

  void _select(int i) {
    setState(() {
      cur = i;
      selected = -1;
      onFree = false;
    });
    _save();
    _pingAll();
  }

  /// Switch subscription (not while connected).
  void selectSub(int i) {
    if (locked || i == cur) return;
    _select(i);
  }

  Future<void> _addMenu(String a) async {
    switch (a) {
      case 'clip':
        final d = await Clipboard.getData('text/plain');
        return _importText(d?.text, 'clipboard');
      case 'screen':
        try {
          final t = await scanScreenQr();
          // Android: null = user closed the camera, nothing to report
          if (t == null) {
            return Platform.isAndroid ? null : _toast('No QR code found');
          }
          return await _importText(t, 'QR code');
        } catch (e) {
          return _toast('$e');
        }
      case 'qrfile':
      case 'file':
        try {
          final p = await pickOpenFile(
            a == 'qrfile' ? 'Choose a QR image' : 'Choose a config file',
            image: a == 'qrfile',
          );
          if (p == null) return;
          final t = a == 'qrfile'
              ? await decodeQrFile(p)
              : await File(p).readAsString();
          if (t == null) return _toast('No QR code found in image');
          return await _importText(t, a == 'qrfile' ? 'QR image' : 'file');
        } catch (e) {
          return _toast('$e');
        }
      case 'sub':
        return _editSub();
      case 'manual':
        final t = await _textSheet(
          'Add servers',
          'Paste vmess:// vless:// trojan:// ss:// hy2:// links or JSON config',
          lines: 8,
        );
        if (t != null) return _importText(t, 'input');
      case 'update':
        return _updateAll();
    }
  }

  /// New https subscription from the Add sheet / first-run.
  Future<void> _addSub(String url, [String name = '']) async {
    url = url.trim();
    if (url.isEmpty) return;
    final host = Uri.tryParse(url)?.host ?? '';
    final n = name.trim().isNotEmpty
        ? name.trim()
        : (host.isNotEmpty ? host : 'Subscription');
    await _run(() async {
      final sub = Sub(n, url);
      await _refresh(sub);
      subs.add(sub);
      _select(subs.length - 1);
      _toast('${sub.servers.length} servers loaded');
    });
  }

  Future<void> _editSub([int? i]) async {
    final s = i == null ? null : subs[i];
    final name = TextEditingController(text: s?.name ?? '');
    final src = TextEditingController(text: s?.src ?? '');
    final r = await _sheet<String>(
      (c) => _formSheet(
        c,
        title: s == null
            ? 'Add subscription'
            : s.local
            ? 'Rename list'
            : 'Edit subscription',
        fields: [
          _field(name, 'Name (optional)'),
          if (s == null || !s.local)
            _field(
              src,
              'https://… subscription URL',
              autofocus: s == null,
              mono: true,
              lines: 2,
            ),
        ],
        ok: s == null ? 'Add' : 'Save',
      ),
    );
    if (r != 'ok') return;
    final url = src.text.trim();
    if (s == null) return _addSub(url, name.text);
    if (s.local) {
      s.name = name.text.trim().isEmpty ? s.name : name.text.trim();
      setState(() {});
      return _save();
    }
    if (url.isEmpty) return;
    final host = Uri.tryParse(url)?.host ?? '';
    final n = name.text.trim().isNotEmpty
        ? name.text.trim()
        : (host.isNotEmpty ? host : 'Subscription');
    await _run(() async {
      final sub = Sub(n, url);
      await _refresh(sub);
      s
        ..name = n
        ..src = url
        ..servers = sub.servers
        ..usage = sub.usage;
      _select(i!);
      _toast('${sub.servers.length} servers loaded');
    });
  }

  // ---------- export / actions ----------

  String _serverExport(Server s) => s.link ?? jsonEncode(s.outbound);

  String _subExport(Sub s) => s.servers.map(_serverExport).join('\n');

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    _toast('$what copied');
  }

  Future<void> _saveFile(String name, String text) async {
    try {
      final p = await saveTextFile(name, text);
      if (p != null) _toast('Saved to $p');
    } catch (e) {
      _toast('$e');
    }
  }

  /// Subscription sheet grid actions.
  Future<void> _subAction(int i, String a) async {
    final s = subs[i];
    switch (a) {
      case 'edit':
        return _editSub(i);
      case 'copyurl':
        return _copy(s.src, 'Subscription URL');
      case 'qrurl':
        return _showQr(s.name, s.src);
      case 'copyall':
        return _copy(_subExport(s), '${s.servers.length} links');
      case 'file':
        return _saveFile('${_slug(s.name)}.txt', _subExport(s));
      case 'update':
        return _run(() async {
          await _refresh(s);
          await _save();
          setState(() {});
          _pingAll();
          _toast('${s.servers.length} servers updated');
        });
      case 'delete':
        subs.removeAt(i);
        _select(0);
    }
  }

  /// Server sheet actions.
  Future<void> _serverAction(int i, String a) async {
    final s = servers[i];
    switch (a) {
      case 'copy':
        return _copy(_serverExport(s), s.link != null ? 'Link' : 'JSON');
      case 'file':
        return _saveFile('${_slug(_clean(s.name))}.txt', _serverExport(s));
      case 'delete':
        setState(() {
          servers.removeAt(i);
          if (!onFree) selected = -1;
          pings = {};
        });
        await _save();
        _pingAll();
    }
  }

  // ---------- servers ----------

  void _pingAll() {
    if (demo) return;
    setState(() => pings = {});
    final list = servers;
    for (var i = 0; i < list.length; i++) {
      ping(list[i].host, list[i].port).then((ms) {
        if (mounted && identical(list, servers)) setState(() => pings[i] = ms);
      });
    }
  }

  /// Gemini refuses exit IPs in some countries. If the server(s) we'd use include
  /// one, send Gemini to the fastest server in a supported country.
  // ponytail: country comes from the flag emoji in the name; unflagged = unknown.
  Map<String, dynamic>? _aiServer() {
    if (!opt.smartAi) return null;
    final all = pool;
    int? ms(int i) => onFree ? freePool[i].delay : pings[i];
    final use = selected < 0 ? all : [all[selected]];
    if (!use.any((s) => _geminiBlocked.contains(_cc(s.name)))) return null;
    final ok = [
      for (var i = 0; i < all.length; i++)
        if (_cc(all[i].name) case final c? when !_geminiBlocked.contains(c)) i,
    ]..sort((a, b) => (ms(a) ?? 1 << 30).compareTo(ms(b) ?? 1 << 30));
    return ok.isEmpty ? null : all[ok.first].outbound;
  }

  // ---------- connection ----------

  Future<void> _poll() async {
    if (phase == Phase.off) return;
    final s = await core.stats();
    if (!mounted || s == null) return;
    setState(() {
      stats = s;
      _push(down, s.downRate.toDouble());
      _push(up, s.upRate.toDouble());
      if (phase == Phase.connecting) {
        phase = Phase.on;
        since = DateTime.now();
        msg = null;
        exitIp().then((v) => mounted ? setState(() => ip = v) : null);
        if (!onFree) _remember(selected >= 0 ? selected : s.active);
      }
    });
  }

  /// Recent = last connected servers (max 5).
  void _remember(int? i) {
    if (i == null || i < 0 || i >= servers.length) return;
    final id = _id(servers[i]);
    recent
      ..remove(id)
      ..insert(0, id);
    if (recent.length > 5) recent.removeRange(5, recent.length);
    _save();
  }

  void _push(List<double> l, double v) {
    l.add(v);
    if (l.length > 60) l.removeAt(0);
  }

  Future<void> _toggle() async {
    if (demo) return;
    if (phase != Phase.off) return core.stop();
    final all = pool;
    if (all.isEmpty) return;
    setState(() {
      phase = Phase.connecting;
      msg = null;
      ip = null;
      stats = null;
      down.clear();
      up.clear();
    });
    final proxies = selected < 0
        ? [for (final s in all) s.outbound]
        : [all[selected].outbound];
    try {
      await core.start(proxies, ai: _aiServer(), opt: opt, (code) async {
        final tail = code == 0 ? '' : await core.logTail();
        if (!mounted) return;
        setState(() {
          if (code != 0) msg = 'Stopped ($code) $tail'.trim();
          phase = Phase.off;
          since = null;
          stats = null;
        });
      });
    } catch (e) {
      // e.g. pkexec missing on Linux
      setState(() {
        phase = Phase.off;
        msg = 'Error: $e';
      });
    }
  }

  // ---------- free servers ----------

  /// Opt in (after the warning) / out (removes the list).
  Future<void> setFree(bool on) async {
    if (on == freeOn) return;
    if (!on) {
      if (locked && onFree) return _toast('Disconnect first');
      setState(() {
        freeOn = false;
        free = [];
        shared = [];
        freeUpdated = null;
        if (onFree) selected = -1;
        onFree = false;
      });
      return _save();
    }
    if (await _freeWarning() != true) return;
    setState(() => freeOn = true);
    await _save();
    updateFree();
  }

  void pickFree(int i) {
    if (locked) return;
    setState(() {
      onFree = true;
      selected = i;
      if (mobile) nav = 0;
    });
    _save();
  }

  /// Every 6 h while open and disconnected (if auto-update is on).
  void _autoFree() {
    final u = freeUpdated;
    if (!freeOn || !freeAuto || locked || freeBusy || demo) return;
    if (u != null && DateTime.now().difference(u) < const Duration(hours: 6)) {
      return;
    }
    updateFree();
  }

  /// Fetch the free + community lists and keep the ones that work from here.
  Future<void> updateFree() async {
    if (!freeOn || freeBusy || demo) return;
    if (locked) return _toast('Disconnect to re-test');
    setState(() {
      freeBusy = true;
      freeStatus = 'Downloading lists…';
      freeProgress = null;
    });
    try {
      Future<String?> get(String u) => fetchText(u).catchError((_) => null);
      final bodies = await Future.wait(freeSources.map(get));
      final comm = parseCommunity(await get(communitySource) ?? '');
      final cand = sample(
        dedupe([for (final b in bodies) ...parseFree(b ?? '')]),
        maxTested,
      );
      if (cand.isEmpty && bodies.every((b) => b == null)) {
        throw 'Couldn\'t download the free lists';
      }
      final all = [for (final c in comm) c.server, ...cand];
      void progress(int d, int t) {
        if (mounted) {
          setState(() {
            freeStatus = 'Testing $d/$t…';
            freeProgress = d / t;
          });
        }
      }

      final delays = reachOnly
          ? await _reachTest(all, progress)
          : await coreTest(coreBinary, [
              for (final s in all) s.outbound,
            ], progress: progress);
      if (locked) throw 'Connected during the test — disconnect to re-test';
      List<FreeServer> ok(Iterable<(FreeServer, int?)> l) => [
        for (final (f, d) in l)
          if (d != null) f.withDelay(d),
      ]..sort((a, b) => a.delay!.compareTo(b.delay!));
      if (!mounted) return;
      setState(() {
        shared = ok([
          for (var i = 0; i < comm.length; i++) (comm[i], delays[i]),
        ]);
        free = ok([
          for (var i = 0; i < cand.length; i++)
            (FreeServer(cand[i]), delays[comm.length + i]),
        ]).take(maxKept).toList();
        freeUpdated = DateTime.now();
        if (onFree) selected = -1; // indexes changed
      });
      await _save();
    } catch (e) {
      _toast('Free servers: $e');
    } finally {
      if (mounted) {
        setState(() {
          freeBusy = false;
          freeStatus = null;
          freeProgress = null;
        });
      }
    }
  }

  /// Android: TCP connect time only ("reachable", not proven working).
  Future<List<int?>> _reachTest(
    List<Server> l,
    void Function(int, int) progress,
  ) async {
    final r = List<int?>.filled(l.length, null);
    var next = 0, done = 0;
    Future<void> worker() async {
      while (next < l.length) {
        final k = next++;
        r[k] = await ping(l[k].host, l[k].port);
        progress(++done, l.length);
      }
    }

    await Future.wait([for (var w = 0; w < 16; w++) worker()]);
    return r;
  }

  // ---------- helper / log ----------

  /// Background: 5 s after launch, then every 6 h; after a failure (flaky or
  /// blocked network) retry in 15 min instead of waiting 6 h.
  /// Manual (Check for updates): always says what happened.
  Future<void> _checkUpdate({bool manual = false}) async {
    if (demo || checkingUpdate) return;
    setState(() => checkingUpdate = true);
    var next = const Duration(hours: 6);
    try {
      final u = await updater.check(appVersion);
      if (!mounted) return;
      setState(() => update = u);
      if (manual) {
        _toast(
          u == null
              ? 'You have the latest version ($appVersion)'
              : 'mimray ${u.version} is available — tap Update',
        );
      }
    } catch (e) {
      next = const Duration(minutes: 15);
      if (manual) _toast('Couldn\'t check for updates: $e');
    } finally {
      if (mounted) setState(() => checkingUpdate = false);
      _updateTimer?.cancel();
      if (mounted) _updateTimer = Timer(next, _checkUpdate);
    }
  }

  Future<void> _installUpdate() async {
    final u = update;
    if (u == null || updateProgress != null) return;
    setState(() => updateProgress = 0);
    try {
      final file = await updater.download(
        u,
        (p) => mounted ? setState(() => updateProgress = p) : null,
      );
      if (Platform.isAndroid) {
        await updater.install(file); // system installer takes over
        setState(() => updateProgress = null);
        return;
      }
      if (await updater.install(file)) {
        _toast('Installing mimray ${u.version}… the app will reopen');
        await core.stop(); // the tunnel must not outlive the old app
        await Future.delayed(const Duration(seconds: 2));
        exit(0);
      }
      // app folder not writable (e.g. installed by another user): manual install
      setState(() => updateProgress = null);
      _toast('Opened the update — install it like a normal download');
      await reveal(file);
    } catch (e) {
      setState(() => updateProgress = null);
      _toast('Update failed: $e');
    }
  }

  /// "mimray X is available" + Update button (download progress while running).
  Widget _updateBanner({bool mobile = false}) {
    final u = update;
    if (u == null) return const SizedBox.shrink();
    final p = updateProgress;
    return Container(
      margin: mobile ? EdgeInsets.zero : const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: EdgeInsets.fromLTRB(mobile ? 16 : 12, 9, 6, 9),
      decoration: BoxDecoration(
        color: _selBg,
        borderRadius: BorderRadius.circular(mobile ? 16 : 10),
        border: Border.all(color: _blue.withValues(alpha: .45)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.system_update_alt_rounded,
            size: mobile ? 20 : 16,
            color: _blueLight,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'mimray ${u.version} is available',
                  style: _t(mobile ? 14 : 12, FontWeight.w600),
                ),
                if (p != null) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: p == 0 ? null : p,
                    minHeight: 3,
                    color: _blue,
                    backgroundColor: _line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ] else
                  Text(
                    'You have $appVersion',
                    style: _t(mobile ? 12 : 11, FontWeight.w400, _muted),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: p == null ? _installUpdate : null,
            child: Text(
              p == null ? 'Update' : '${(p * 100).round()}%',
              style: _t(
                mobile ? 14 : 12,
                FontWeight.w700,
                p == null ? _blueLight : _muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkHelper() async {
    final v = await helperVersion();
    if (mounted) setState(() => helper = v);
  }

  Future<void> _helperAction(bool uninstall) async {
    final err = await setupHelper(uninstall: uninstall);
    await _checkHelper();
    _toast(
      err != null
          ? 'Helper: ${err.split('\n').last}'
          : uninstall
          ? 'Helper removed — you\'ll be asked for your password again'
          : 'Helper installed — no more password prompts',
    );
  }

  void setOpt(VoidCallback f) {
    setState(f);
    _save();
  }

  Future<void> _openLog() async {
    if (!demo) logText = await core.logTail(200);
    await _logSheet();
  }

  // ---------- tray / window ----------

  bool _trayReady = false;
  String _traySig = '';

  Future<void> _initTray() async {
    try {
      trayManager.addListener(this);
      await trayManager.setIcon(
        Platform.isWindows
            ? 'assets/tray/tray.ico'
            : Platform.isMacOS
            ? 'assets/tray/tray_mac.png'
            : 'assets/tray/tray.png',
        isTemplate: Platform.isMacOS,
      );
      if (!Platform.isLinux) await trayManager.setToolTip('mimray');
      _trayReady = true;
      _syncTray();
    } catch (e) {
      debugPrint('tray unavailable: $e'); // e.g. GNOME without AppIndicator
    }
  }

  /// Native tray menu: status, location, connect, favorites, open, quit.
  void _syncTray() {
    if (!_trayReady) return;
    final favs = [
      for (var i = 0; i < servers.length; i++)
        if (isFav(i)) i,
    ];
    final status = switch (phase) {
      Phase.on => 'Connected',
      Phase.connecting => 'Connecting…',
      Phase.off => 'Disconnected',
    };
    final items = [
      MenuItem(label: status, disabled: true),
      MenuItem(label: locTitle, disabled: true),
      MenuItem(
        key: 'toggle',
        label: phase == Phase.off ? 'Connect' : 'Disconnect',
        disabled: pool.isEmpty,
      ),
      MenuItem.separator(),
      if (favs.isNotEmpty) ...[
        MenuItem(label: 'Favorites', disabled: true),
        for (final i in favs)
          MenuItem.checkbox(
            key: 'fav:$i',
            label: _clean(servers[i].name),
            checked: subSel == i,
            disabled: locked,
          ),
        MenuItem.separator(),
      ],
      MenuItem(key: 'open', label: 'Open mimray'),
      MenuItem(key: 'quit', label: 'Quit'),
    ];
    final sig = items
        .map((e) => '${e.key}${e.label}${e.disabled}${e.checked}')
        .join('|');
    if (sig == _traySig) return;
    _traySig = sig;
    trayManager.setContextMenu(Menu(items: items));
  }

  @override
  void onTrayIconMouseDown() =>
      Platform.isWindows ? _showWindow() : trayManager.popUpContextMenu();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem m) {
    final k = m.key ?? '';
    if (k == 'toggle') _toggle();
    if (k == 'open') _showWindow();
    if (k == 'quit') _quit();
    if (k.startsWith('fav:') && !locked) {
      pick(int.parse(k.substring(4)));
      _toggle(); // quick connect
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    stopCoreTest();
    if (phase != Phase.off) await core.stop();
    exit(0); // the root core watchdog / helper session stop with us
  }

  void minimizeWindow() => demo ? null : windowManager.minimize();
  void closeWindow() => demo ? null : windowManager.close();
  void dragWindow() => demo ? null : windowManager.startDragging();

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) =>
      mobile ? _mobileShell() : _desktopShell();
}

String _proto(String t) =>
    const {
      'vmess': 'VMess',
      'vless': 'VLESS',
      'trojan': 'Trojan',
      'shadowsocks': 'Shadowsocks',
      'hysteria2': 'Hysteria2',
    }[t] ??
    t;

/// "VLESS · Reality", "VMess · WS + TLS".
String _protoLong(Map<String, dynamic> o) {
  final tr = (o['transport'] as Map?)?['type'] as String?;
  final tls = o['tls'] as Map?;
  final reality = (tls?['reality'] as Map?)?['enabled'] == true;
  final extra = [
    if (tr != null)
      const {
            'ws': 'WS',
            'grpc': 'gRPC',
            'http': 'HTTP',
            'httpupgrade': 'HTTPUpgrade',
          }[tr] ??
          tr,
    if (reality)
      'Reality'
    else if (tls?['enabled'] == true && tr != null)
      'TLS',
  ].join(' + ');
  return [_proto(o['type']), if (extra.isNotEmpty) extra].join(' · ');
}

final _flagRe = RegExp(r'[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true);

/// Country code from the first flag emoji in [name], e.g. "🇩🇪 Berlin" -> "DE".
String? _cc(String name) {
  final m = _flagRe.firstMatch(name);
  return m == null
      ? null
      : String.fromCharCodes(m[0]!.runes.map((r) => r - 0x1F1A5));
}

/// Name without flag emoji (shown separately) and leftover empty brackets.
String _clean(String n) {
  final s = n
      .replaceAll(_flagRe, '')
      .replaceAll(RegExp(r'[\[(]\s*[\])]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return s.isEmpty ? n : s;
}

String _slug(String s) {
  final t = s
      .replaceAll(RegExp(r'[^\w\-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return t.isEmpty ? 'mimray-export' : t;
}

const _geminiBlocked = {'CN', 'HK', 'MO', 'IR', 'RU', 'BY', 'KP', 'CU', 'SY'};

String _dur(Duration d) =>
    '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
