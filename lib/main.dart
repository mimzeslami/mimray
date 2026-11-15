import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'android_vpn.dart';
import 'core.dart';
import 'links.dart';
import 'native.dart';
import 'updater.dart' as updater;

const appVersion = '0.3.0';

// Palette
const _bg = Color(0xFF0B1220);
const _card = Color(0xFF151F35);
const _card2 = Color(0xFF1B2742);
const _line = Color(0xFF22304D);
const _muted = Color(0xFF8A97B4);
const _blue = Color(0xFF2F7BFF);
const _green = Color(0xFF3DDC97);
const _amber = Color(0xFFFFB547);
const _red = Color(0xFFFF5D6C);

final _theme = ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  scaffoldBackgroundColor: _bg,
  visualDensity: VisualDensity.compact,
  colorScheme: const ColorScheme.dark(
    primary: _blue,
    surface: _card,
    error: _red,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: _bg,
    isDense: true,
    hintStyle: const TextStyle(color: _muted, fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _blue, width: 1.5),
    ),
  ),
  popupMenuTheme: PopupMenuThemeData(
    color: _card2,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: _line),
    ),
    textStyle: const TextStyle(fontSize: 13, color: Colors.white),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: _card,
    showDragHandle: true,
    dragHandleColor: _line,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
  ),
  switchTheme: SwitchThemeData(
    thumbColor: WidgetStateProperty.all(Colors.white),
    trackColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.selected) ? _blue : _line,
    ),
    trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
  ),
  snackBarTheme: const SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: _card2,
    contentTextStyle: TextStyle(color: Colors.white),
  ),
  dividerColor: _line,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAndroidVpn(); // no-op on desktop
  runApp(
    MaterialApp(
      title: 'mimray',
      debugShowCheckedModeBanner: false,
      theme: _theme,
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
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
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
  double? updateProgress; // non-null while downloading
  Timer? _updateTimer;
  String? msg;

  Phase phase = Phase.off;
  DateTime? since;
  Stats? stats;
  Map<String, dynamic>? ip;
  final down = <double>[], up = <double>[]; // last 60s rates
  Timer? _tick;

  List<Server> get servers => subs.isEmpty ? const [] : subs[cur].servers;
  bool get locked => phase != Phase.off;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    _checkHelper();
    // check shortly after launch, then every 6 hours (cancellable timers)
    _updateTimer = Timer(const Duration(seconds: 5), () {
      _checkUpdate();
      _updateTimer = Timer.periodic(
        const Duration(hours: 6),
        (_) => _checkUpdate(),
      );
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _updateTimer?.cancel();
    core.stop();
    super.dispose();
  }

  // ---------- persistence ----------

  Future<void> _load() async {
    try {
      final j = jsonDecode(await state.readAsString());
      setState(() {
        if (j['subs'] != null) {
          subs = [for (final s in j['subs']) Sub.fromJson(s)];
        } else if (j['servers'] != null) {
          // migrate v1 single-subscription state
          subs = [
            Sub.fromJson({...j, 'name': 'My VPN', 'src': j['sub'] ?? ''}),
          ];
        }
        opt = Settings.fromJson(j['settings']);
        cur = ((j['cur'] ?? 0) as int).clamp(
          0,
          subs.isEmpty ? 0 : subs.length - 1,
        );
        selected = j['sel'] ?? -1;
        if (selected >= servers.length) selected = -1;
      });
      _pingAll();
      if (opt.autoConnect && servers.isNotEmpty) _toggle();
    } catch (_) {}
  }

  Future<void> _save() async {
    await Directory(appDir).create(recursive: true);
    await state.writeAsString(
      jsonEncode({'subs': subs, 'cur': cur, 'sel': selected, 'settings': opt}),
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
          width: 360,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

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
    });
    _save();
    _pingAll();
  }

  Future<void> _addMenu(String a) async {
    switch (a) {
      case 'clip':
        final d = await Clipboard.getData('text/plain');
        return _importText(d?.text, 'clipboard');
      case 'screen':
        try {
          final t = await scanScreenQr();
          if (t == null) return _toast('No QR code found');
          return await _importText(t, 'QR code');
        } catch (e) {
          return _toast('$e');
        }
      case 'qrfile':
      case 'file':
        try {
          final p = await pickOpenFile(
            a == 'qrfile' ? 'Choose a QR image' : 'Choose a config file',
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

  Future<void> _editSub([int? i]) async {
    final s = i == null ? null : subs[i];
    final name = TextEditingController(text: s?.name ?? '');
    final src = TextEditingController(text: s?.src ?? '');
    final r = await _sheet<String>(
      (c) => _sheetBody(
        c,
        title: s == null ? 'Add subscription' : 'Edit subscription',
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(hintText: 'Name (optional)'),
          ),
          if (s == null || !s.local) ...[
            const SizedBox(height: 10),
            TextField(
              controller: src,
              autofocus: s == null,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'https://… subscription URL',
                prefixIcon: Icon(Icons.link_rounded, size: 18),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              if (s != null)
                TextButton.icon(
                  onPressed: () => Navigator.pop(c, 'delete'),
                  icon: const Icon(Icons.delete_outline, color: _red, size: 18),
                  label: const Text('Delete', style: TextStyle(color: _red)),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.pop(c, 'ok'),
                child: Text(s == null ? 'Add' : 'Save'),
              ),
            ],
          ),
        ],
      ),
    );
    if (r == 'delete' && i != null) {
      subs.removeAt(i);
      _select(0);
      return;
    }
    if (r != 'ok') return;
    final url = src.text.trim();
    if (s != null && s.local) {
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
      if (s == null) {
        subs.add(sub);
        _select(subs.length - 1);
      } else {
        s
          ..name = n
          ..src = url
          ..servers = sub.servers
          ..usage = sub.usage;
        _select(i!);
      }
      _toast('${sub.servers.length} servers loaded');
    });
  }

  // ---------- export ----------

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

  Future<void> _subMenu(int i) async {
    final s = subs[i];
    final a = await _actions(s.name, [
      ('edit', Icons.edit_rounded, s.local ? 'Rename' : 'Edit'),
      if (!s.local) ('copyurl', Icons.link_rounded, 'Copy subscription URL'),
      if (!s.local) ('qrurl', Icons.qr_code_rounded, 'Show subscription QR'),
      ('copyall', Icons.copy_all_rounded, 'Copy all server links'),
      ('file', Icons.save_alt_rounded, 'Export servers to file'),
      if (!s.local) ('update', Icons.refresh_rounded, 'Update'),
      ('delete', Icons.delete_outline, 'Delete'),
    ]);
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

  Future<void> _serverMenu(int i) async {
    final s = servers[i];
    final a = await _actions(_clean(s.name), [
      ('copy', Icons.copy_rounded, s.link != null ? 'Copy link' : 'Copy JSON'),
      ('qr', Icons.qr_code_rounded, 'Show QR code'),
      ('file', Icons.save_alt_rounded, 'Export to file'),
      if (!locked) ('delete', Icons.delete_outline, 'Delete server'),
    ]);
    switch (a) {
      case 'copy':
        return _copy(_serverExport(s), s.link != null ? 'Link' : 'JSON');
      case 'qr':
        return _showQr(_clean(s.name), _serverExport(s));
      case 'file':
        return _saveFile('${_slug(_clean(s.name))}.txt', _serverExport(s));
      case 'delete':
        setState(() {
          servers.removeAt(i);
          selected = -1;
          pings = {};
        });
        await _save();
        _pingAll();
    }
  }

  Future<void> _showQr(String title, String data) async {
    List<List<bool>> m;
    try {
      m = qrMatrix(data);
    } catch (_) {
      return _toast('Too long for a QR code — use Export to file');
    }
    await _sheet(
      (c) => _sheetBody(
        c,
        title: title,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SizedBox.square(
                dimension: 240,
                child: CustomPaint(painter: _QrPainter(m)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: TextButton.icon(
              onPressed: () => _copy(data, 'Copied'),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy text'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- servers ----------

  void _pingAll() {
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
    final pool = selected < 0 ? servers : [servers[selected]];
    if (!pool.any((s) => _geminiBlocked.contains(_cc(s.name)))) return null;
    final ok = [
      for (var i = 0; i < servers.length; i++)
        if (_cc(servers[i].name) case final c? when !_geminiBlocked.contains(c))
          i,
    ]..sort((a, b) => (pings[a] ?? 1 << 30).compareTo(pings[b] ?? 1 << 30));
    return ok.isEmpty ? null : servers[ok.first].outbound;
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
      }
    });
  }

  void _push(List<double> l, double v) {
    l.add(v);
    if (l.length > 60) l.removeAt(0);
  }

  Future<void> _toggle() async {
    if (phase != Phase.off) return core.stop();
    if (servers.isEmpty) return;
    setState(() {
      phase = Phase.connecting;
      msg = null;
      ip = null;
      stats = null;
      down.clear();
      up.clear();
    });
    final proxies = selected < 0
        ? [for (final s in servers) s.outbound]
        : [servers[selected].outbound];
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

  // ---------- sheets ----------

  Future<T?> _sheet<T>(Widget Function(BuildContext) b) =>
      showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        constraints: const BoxConstraints(maxWidth: 460),
        builder: (c) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
          child: b(c),
        ),
      );

  Widget _sheetBody(
    BuildContext c, {
    required String title,
    required List<Widget> children,
  }) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );

  Future<String?> _actions(
    String title,
    List<(String, IconData, String)> items,
  ) => _sheet<String>(
    (c) => _sheetBody(
      c,
      title: title,
      children: [
        for (final (id, icon, label) in items)
          ListTile(
            dense: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: Icon(icon, size: 20, color: id == 'delete' ? _red : null),
            title: Text(
              label,
              style: TextStyle(color: id == 'delete' ? _red : null),
            ),
            onTap: () => Navigator.pop(c, id),
          ),
      ],
    ),
  );

  Future<String?> _textSheet(String title, String hint, {int lines = 1}) {
    final t = TextEditingController();
    return _sheet<String>(
      (c) => _sheetBody(
        c,
        title: title,
        children: [
          TextField(
            controller: t,
            autofocus: true,
            minLines: lines,
            maxLines: lines,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            decoration: InputDecoration(hintText: hint),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton.icon(
                onPressed: () async {
                  final d = await Clipboard.getData('text/plain');
                  t.text = d?.text ?? '';
                },
                icon: const Icon(Icons.content_paste_rounded, size: 16),
                label: const Text('Paste'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.pop(c, t.text),
                child: const Text('Import'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _checkUpdate({bool manual = false}) async {
    try {
      final u = await updater.check(appVersion);
      if (!mounted) return;
      setState(() => update = u);
      if (manual && u == null) {
        _toast('mimray $appVersion is the latest version');
      }
    } catch (e) {
      if (manual) _toast('Update check failed: $e');
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

  Widget _updateBanner() {
    final u = update;
    if (u == null) return const SizedBox.shrink();
    final p = updateProgress;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: _blue.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _blue.withValues(alpha: .5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update_alt_rounded, size: 18, color: _blue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'mimray ${u.version} is available',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (p != null) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: p == 0 ? null : p,
                    minHeight: 3,
                    backgroundColor: _line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ] else
                  Text(
                    'You have $appVersion',
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: p == null ? _installUpdate : null,
            child: Text(p == null ? 'Update' : '${(p * 100).round()}%'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkHelper() async {
    final v = await helperVersion();
    if (mounted) setState(() => helper = v);
  }

  Future<void> _helperAction(
    bool uninstall,
    void Function(VoidCallback) set,
  ) async {
    final err = await setupHelper(uninstall: uninstall);
    await _checkHelper();
    set(() {});
    _toast(
      err != null
          ? 'Helper: ${err.split('\n').last}'
          : uninstall
          ? 'Helper removed — you\'ll be asked for your password again'
          : 'Helper installed — no more password prompts',
    );
  }

  Future<void> _settings() async {
    await _sheet(
      (c) => StatefulBuilder(
        builder: (c, set) {
          void upd(VoidCallback f) {
            set(f);
            setState(() {});
            _save();
          }

          Widget sw(String t, String sub, bool v, void Function(bool) f) =>
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t, style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  sub,
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
                value: v,
                onChanged: (x) => upd(() => f(x)),
              );

          return _sheetBody(
            c,
            title: 'Settings',
            children: [
              if (locked)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Changes apply on next connect.',
                    style: TextStyle(color: _amber, fontSize: 12),
                  ),
                ),
              _section('Connection'),
              sw(
                'Connect on launch',
                'Start the tunnel when mimray opens',
                opt.autoConnect,
                (x) => opt.autoConnect = x,
              ),
              sw(
                'Smart Gemini routing',
                'Send Gemini via a supported country when needed',
                opt.smartAi,
                (x) => opt.smartAi = x,
              ),
              sw(
                'Block QUIC',
                'Forces TCP — more reliable through proxies',
                opt.blockQuic,
                (x) => opt.blockQuic = x,
              ),
              sw(
                'Bypass LAN',
                'Local network (printers, NAS, router) stays direct',
                opt.bypassLan,
                (x) => opt.bypassLan = x,
              ),
              const SizedBox(height: 8),
              _section('Secure DNS (DoH, through the tunnel)'),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final e in dnsChoices.entries)
                    ButtonSegment(value: e.key, label: Text(e.value)),
                ],
                selected: {opt.dns},
                onSelectionChanged: (v) => upd(() => opt.dns = v.first),
              ),
              const SizedBox(height: 18),
              if (helperBundled) ...[
                _section('Password prompt'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    helper != null
                        ? Icons.verified_user_rounded
                        : Icons.key_rounded,
                    color: helper != null ? _green : _amber,
                  ),
                  title: Text(
                    helper != null
                        ? 'Background helper installed'
                        : 'Asked for password on every connect',
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    helper != null
                        ? 'Connects without a password'
                        : 'Install the helper once to stop the prompts',
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                  trailing: helper != null
                      ? TextButton(
                          onPressed: locked
                              ? null
                              : () => _helperAction(true, set),
                          child: const Text('Remove'),
                        )
                      : FilledButton(
                          onPressed: () => _helperAction(false, set),
                          child: const Text('Install'),
                        ),
                ),
                const SizedBox(height: 8),
              ],
              _section('About'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.shield_rounded, color: _blue),
                title: const Text('mimray $appVersion'),
                subtitle: const Text(
                  'sing-box core · github.com/mimzeslami/mimray',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
                trailing: TextButton(
                  onPressed: () => _checkUpdate(manual: true),
                  child: const Text('Check for updates'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 2),
    child: Text(
      t.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        color: _muted,
        letterSpacing: 1,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Future<void> _showLog() async {
    final l = await core.logTail(200);
    await _sheet(
      (c) => _sheetBody(
        c,
        title: 'Core log',
        children: [
          Container(
            height: 320,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _line),
            ),
            child: SingleChildScrollView(
              reverse: true,
              child: SelectableText(
                l.isEmpty ? 'No log yet.' : l,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: _muted,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => reveal(core.log),
              icon: const Icon(Icons.folder_open_rounded, size: 16),
              label: const Text('Show file'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              children: [
                _hero(),
                _updateBanner(),
                _subsBar(),
                Expanded(child: _serverList()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hero() {
    final on = phase == Phase.on;
    final s = stats;
    final int? active = servers.isEmpty
        ? null
        : selected >= 0
        ? selected
        : (s?.active ?? -1);
    final title = active == null
        ? 'No servers yet'
        : active < 0
        ? 'Auto · best server'
        : _clean(servers[active].name);
    final flag = active != null && active >= 0
        ? _flag(_cc(servers[active].name))
        : '⚡';
    final (c1, c2, label, lc) = switch (phase) {
      Phase.on => (
        const Color(0xFF1C5BFF),
        const Color(0xFF0E2D7A),
        'ON',
        _green,
      ),
      Phase.connecting => (
        const Color(0xFF6B4E17),
        const Color(0xFF2A2214),
        'CONNECTING',
        _amber,
      ),
      Phase.off => (
        const Color(0xFF1B2540),
        const Color(0xFF111A2E),
        'OFF',
        _muted,
      ),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      padding: const EdgeInsets.fromLTRB(10, 8, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1, c2],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
        boxShadow: [
          if (on)
            BoxShadow(color: _blue.withValues(alpha: .35), blurRadius: 28),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PopupMenuButton<String>(
                tooltip: 'Menu',
                icon: const Icon(Icons.menu_rounded, size: 20),
                onSelected: (a) => switch (a) {
                  'settings' => _settings(),
                  'update' => _updateAll(),
                  'log' => _showLog(),
                  _ => null,
                },
                itemBuilder: (_) => [
                  _mi('settings', Icons.tune_rounded, 'Settings'),
                  _mi(
                    'update',
                    Icons.refresh_rounded,
                    'Update all subscriptions',
                  ),
                  _mi('log', Icons.receipt_long_rounded, 'Core log'),
                ],
              ),
              const Text(
                'mimray',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: .4,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 10),
              _pill(label, lc),
              const Spacer(),
              _Switch(
                value: phase != Phase.off,
                busy: phase == Phase.connecting,
                onTap: servers.isEmpty ? null : _toggle,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(flag, style: const TextStyle(fontSize: 24)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _subtitle(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (since != null)
                      Text(
                        _dur(DateTime.now().difference(since!)),
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _stat(
                      Icons.south_rounded,
                      '${fmtBytes(s?.downRate ?? 0)}/s',
                      fmtBytes(s?.down ?? 0),
                    ),
                    _stat(
                      Icons.north_rounded,
                      '${fmtBytes(s?.upRate ?? 0)}/s',
                      fmtBytes(s?.up ?? 0),
                    ),
                    _stat(Icons.hub_rounded, '${s?.conns ?? 0}', 'connections'),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 28,
                  width: double.infinity,
                  child: CustomPaint(painter: _Spark(down, up)),
                ),
                if (msg != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    msg!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFFFB3BA),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _mi(String v, IconData i, String t) => PopupMenuItem(
    value: v,
    height: 40,
    child: Row(
      children: [
        Icon(i, size: 18, color: _muted),
        const SizedBox(width: 12),
        Text(t),
      ],
    ),
  );

  String _subtitle() => switch (phase) {
    Phase.on when ip == null => 'Checking exit IP…',
    Phase.on => [
      ip!['ip'],
      [ip!['city'], ip!['country']].whereType<String>().join(', '),
    ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
    Phase.connecting => 'Waiting for permission…',
    Phase.off => servers.isEmpty ? 'Add a server to start' : 'Not connected',
  };

  Widget _stat(IconData i, String big, String small) => Expanded(
    child: Row(
      children: [
        Icon(i, size: 14, color: Colors.white60),
        const SizedBox(width: 4),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                big,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              Text(
                small,
                maxLines: 1,
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _addButton() => PopupMenuButton<String>(
    tooltip: 'Add',
    enabled: !locked && !busy,
    onSelected: _addMenu,
    itemBuilder: (_) => [
      _mi('clip', Icons.content_paste_rounded, 'Import from clipboard'),
      _mi('screen', Icons.qr_code_scanner_rounded, 'Scan QR on screen'),
      _mi('qrfile', Icons.image_outlined, 'Import QR image…'),
      _mi('file', Icons.file_open_outlined, 'Import config file…'),
      const PopupMenuDivider(),
      _mi('sub', Icons.rss_feed_rounded, 'Add subscription'),
      _mi('manual', Icons.edit_note_rounded, 'Add servers manually'),
      const PopupMenuDivider(),
      _mi('update', Icons.refresh_rounded, 'Update all subscriptions'),
    ],
    child: Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _blue.withValues(alpha: locked ? .3 : 1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.add_rounded, size: 18),
          const SizedBox(width: 4),
          const Text(
            'Add',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );

  Widget _subsBar() {
    final u = subs.isEmpty ? const <String, int>{} : subs[cur].usage;
    final total = u['total'] ?? 0;
    final used = (u['upload'] ?? 0) + (u['download'] ?? 0);
    final exp = u['expire'] ?? 0;
    final days = exp > 0
        ? DateTime.fromMillisecondsSinceEpoch(
            exp * 1000,
          ).difference(DateTime.now()).inDays
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          SizedBox(
            height: 36,
            child: Row(
              children: [
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < subs.length; i++)
                        _chip(
                          subs[i].name,
                          icon: subs[i].local
                              ? Icons.folder_rounded
                              : Icons.rss_feed_rounded,
                          selected: i == cur,
                          onTap: locked ? null : () => _select(i),
                          onMenu: () => _subMenu(i),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Ping all',
                  onPressed: _pingAll,
                  iconSize: 18,
                  icon: const Icon(Icons.speed_rounded),
                ),
                _addButton(),
              ],
            ),
          ),
          if (total > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '${fmtBytes(used)} / ${fmtBytes(total)}',
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LinearProgressIndicator(
                    value: (used / total).clamp(0, 1),
                    minHeight: 4,
                    color: used / total > .9 ? _red : _blue,
                    backgroundColor: _line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                if (days != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    days < 0 ? 'expired' : '${days}d left',
                    style: TextStyle(
                      fontSize: 11,
                      color: days < 3 ? _red : _muted,
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Pill chip; ⋯ opens its menu (also right-click / long-press).
  Widget _chip(
    String text, {
    required IconData icon,
    bool selected = false,
    VoidCallback? onTap,
    VoidCallback? onMenu,
  }) => Padding(
    padding: const EdgeInsets.only(right: 6, top: 3, bottom: 3),
    child: Material(
      color: selected ? _blue.withValues(alpha: .18) : _card,
      shape: StadiumBorder(side: BorderSide(color: selected ? _blue : _line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        onLongPress: onMenu,
        onSecondaryTap: onMenu,
        child: Padding(
          padding: const EdgeInsets.only(left: 10, right: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: selected ? _blue : _muted),
              const SizedBox(width: 6),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              InkWell(
                customBorder: const CircleBorder(),
                onTap: onMenu,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.more_vert_rounded, size: 15, color: _muted),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _serverList() {
    if (subs.isEmpty || servers.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.public_rounded, size: 52, color: _line),
              const SizedBox(height: 12),
              const Text(
                'Add a subscription, paste a link\nor scan a QR code to get started',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, height: 1.4),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : () => _addMenu('sub'),
                    icon: const Icon(Icons.rss_feed_rounded, size: 18),
                    label: const Text('Subscription'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : () => _addMenu('clip'),
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    label: const Text('From clipboard'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : () => _addMenu('screen'),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Scan QR'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    final best = pings.values.whereType<int>().fold<int?>(
      null,
      (a, b) => a == null || b < a ? b : a,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: servers.length + 1,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, indent: 58, color: _line),
        itemBuilder: (_, k) {
          final i = k - 1; // row 0 = Auto
          final sel = i == selected;
          final s = i < 0 ? null : servers[i];
          final ms = i < 0 ? best : pings[i];
          final live = phase == Phase.on && selected < 0 && stats?.active == i;
          return Material(
            color: sel ? _blue.withValues(alpha: .14) : Colors.transparent,
            child: InkWell(
              onTap: locked
                  ? null
                  : () {
                      setState(() => selected = i);
                      _save();
                    },
              onLongPress: s == null ? null : () => _serverMenu(i),
              onSecondaryTap: s == null ? null : () => _serverMenu(i),
              child: Opacity(
                opacity: locked && !sel && !live ? .45 : 1,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 9, 4, 9),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Text(
                          s == null ? '⚡' : _flag(_cc(s.name)),
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s == null ? 'Auto' : _clean(s.name),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: sel
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              s == null
                                  ? 'Fastest working server, switches by itself'
                                  : '${_proto(s.outbound['type'])} · ${s.host}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: _muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (live) ...[
                        const Icon(Icons.circle, size: 8, color: _green),
                        const SizedBox(width: 6),
                      ],
                      _Bars(ms: ms, pending: i >= 0 && !pings.containsKey(i)),
                      SizedBox(
                        width: 36,
                        child: s == null
                            ? (sel
                                  ? const Icon(
                                      Icons.check_circle,
                                      size: 18,
                                      color: _blue,
                                    )
                                  : null)
                            : IconButton(
                                tooltip: 'More',
                                iconSize: 18,
                                padding: EdgeInsets.zero,
                                onPressed: () => _serverMenu(i),
                                icon: Icon(
                                  sel
                                      ? Icons.check_circle
                                      : Icons.more_vert_rounded,
                                  color: sel ? _blue : _muted,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _pill(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: c.withValues(alpha: .18),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: c.withValues(alpha: .6)),
    ),
    child: Text(
      t,
      style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700),
    ),
  );
}

/// Big pill on/off switch.
class _Switch extends StatelessWidget {
  final bool value, busy;
  final VoidCallback? onTap;
  const _Switch({required this.value, required this.busy, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 64,
        height: 34,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: value ? (busy ? _amber : _green) : Colors.white24,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutBack,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(7),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _amber,
                    ),
                  )
                : Icon(
                    Icons.power_settings_new_rounded,
                    size: 18,
                    color: value ? _green : Colors.grey,
                  ),
          ),
        ),
      ),
    ),
  );
}

/// Signal bars + ms.
class _Bars extends StatelessWidget {
  final int? ms;
  final bool pending;
  const _Bars({this.ms, this.pending = false});

  @override
  Widget build(BuildContext context) {
    final n = ms == null
        ? 0
        : ms! < 150
        ? 3
        : ms! < 350
        ? 2
        : 1;
    final c = n == 3
        ? _green
        : n == 2
        ? _amber
        : _red;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: 40,
          child: Text(
            pending
                ? ''
                : ms == null
                ? '—'
                : '$ms',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, color: _muted),
          ),
        ),
        const SizedBox(width: 6),
        for (var b = 0; b < 3; b++)
          Container(
            margin: const EdgeInsets.only(left: 2),
            width: 4,
            height: 6.0 + b * 4,
            decoration: BoxDecoration(
              color: b < n ? c : _line,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
      ],
    );
  }
}

/// Live down/up speed graph.
class _Spark extends CustomPainter {
  final List<double> a, b;
  _Spark(this.a, this.b);

  @override
  void paint(Canvas canvas, Size size) {
    final top = [...a, ...b, 1024.0].reduce((x, y) => x > y ? x : y);
    for (final (l, c) in [(a, Colors.white), (b, _green)]) {
      if (l.length < 2) continue;
      final p = Path();
      for (var i = 0; i < l.length; i++) {
        final x = size.width * (i + 60 - l.length) / 59;
        final y = size.height - 2 - (size.height - 4) * l[i] / top;
        i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
      }
      canvas.drawPath(
        p,
        Paint()
          ..color = c.withValues(alpha: .8)
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_Spark old) => true;
}

class _QrPainter extends CustomPainter {
  final List<List<bool>> m;
  _QrPainter(this.m);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / m.length;
    final p = Paint()..color = Colors.black;
    for (var y = 0; y < m.length; y++) {
      for (var x = 0; x < m.length; x++) {
        if (m[y][x]) {
          canvas.drawRect(Rect.fromLTWH(x * k, y * k, k + .5, k + .5), p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.m != m;
}

String _proto(String t) =>
    const {
      'vmess': 'VMess',
      'vless': 'VLESS',
      'trojan': 'Trojan',
      'shadowsocks': 'SS',
      'hysteria2': 'Hy2',
    }[t] ??
    t;

final _flagRe = RegExp(r'[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true);

/// Country code from the first flag emoji in [name], e.g. "🇩🇪 Berlin" -> "DE".
String? _cc(String name) {
  final m = _flagRe.firstMatch(name);
  return m == null
      ? null
      : String.fromCharCodes(m[0]!.runes.map((r) => r - 0x1F1A5));
}

String _flag(String? cc) => cc == null || cc.length != 2
    ? '🌐'
    : String.fromCharCodes(cc.toUpperCase().codeUnits.map((c) => c + 0x1F1A5));

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
