part of '../main.dart';

/// Desktop shell (macOS / Windows / Linux): fixed 360 × 600 frameless window.
/// Header (state-coloured, draggable) → tabs → location list → usage bar,
/// plus the slide-in Preferences panel.
extension _DesktopShell on _HomeState {
  Widget _desktopShell() => Scaffold(
    backgroundColor: _bg,
    body: Stack(
      children: [
        Column(
          children: [
            _dHeader(),
            if (servers.isEmpty && tab != 'free')
              Expanded(child: _dEmpty())
            else ...[
              _dToolbar(),
              Expanded(child: _locations()),
            ],
            if (update != null) _updateBanner(),
            if (subs.isNotEmpty) _dUsage(),
          ],
        ),
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (c, a) => SlideTransition(
              position: Tween(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
              child: c,
            ),
            child: view == 'prefs' ? _dPrefs() : const SizedBox.shrink(),
          ),
        ),
      ],
    ),
  );

  Widget _lights() {
    Widget l(Color c, VoidCallback? f, String tip) => Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: f,
        child: MouseRegion(
          cursor: f == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: _dot(c, 11),
        ),
      ),
    );
    return Row(
      children: [
        l(const Color(0xFFFF5F57), closeWindow, 'Close'),
        const SizedBox(width: 7),
        l(const Color(0xFFFEBC2E), minimizeWindow, 'Minimize'),
        const SizedBox(width: 7),
        l(_w(.25), null, ''),
      ],
    );
  }

  Widget _dHeader() {
    final (c1, c2, sc, label) = _phaseLook(phase);
    final on = phase == Phase.on;
    final a = activeIndex;
    final cc = a == null ? null : _cc(pool[a].name);
    return GestureDetector(
      onPanStart: (_) => dragWindow(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c1, c2],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 24,
              child: Row(
                children: [
                  if (os == 'mac') ...[_lights(), const SizedBox(width: 14)],
                  _wordmark(14, right: on ? _green : _blue),
                  const Spacer(),
                  _iconBtn(
                    Icons.tune_rounded,
                    () => rebuild(() => view = 'prefs'),
                    color: _w(.8),
                    tip: 'Preferences',
                  ),
                  if (os != 'mac') ...[
                    const SizedBox(width: 2),
                    _iconBtn(
                      Icons.remove_rounded,
                      minimizeWindow,
                      color: _w(.7),
                      tip: 'Minimize',
                    ),
                    _iconBtn(
                      Icons.close_rounded,
                      closeWindow,
                      color: _w(.7),
                      tip: 'Close',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _dot(sc, 7),
                const SizedBox(width: 6),
                Text(label, style: _t(10, _w7, sc, 1.2)),
                const Spacer(),
                if (since != null)
                  Text(
                    _dur(DateTime.now().difference(since!)),
                    style: _tm(11, _w(.7)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          a != null
                              ? _flag(cc, 22)
                              : const Icon(
                                  Icons.bolt_rounded,
                                  size: 20,
                                  color: _bolt,
                                ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              locTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _t(20, _w7, Colors.white, -.2),
                            ),
                          ),
                          if (onFree) ...[
                            const SizedBox(width: 8),
                            _freeBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        locSub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _t(12, FontWeight.w400, _w(.7)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _PowerButton(
                  phase: phase,
                  size: 64,
                  onTap: pool.isEmpty ? null : _toggle,
                ),
              ],
            ),
            if (msg != null) ...[
              const SizedBox(height: 8),
              Text(
                msg!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: _t(11, FontWeight.w400, const Color(0xFFFFB3BA)),
              ),
            ],
            if (on) ...[const SizedBox(height: 14), _dStrip()],
          ],
        ),
      ),
    );
  }

  /// ↓ / ↑ rates + sparkline; opens the Stats sheet.
  Widget _dStrip() {
    final s = stats;
    Widget rate(IconData i, Color c, int v) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(i, size: 14, color: c),
        const SizedBox(width: 4),
        Text(_rate(v), style: _t(12, _w6)),
      ],
    );
    return _tap(
      color: const Color(0x47050C28), // rgba(5,12,40,.28)
      hover: _w(.05),
      radius: 10,
      onTap: statsSheet,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            rate(Icons.south_rounded, _w(.6), s?.downRate ?? 0),
            const SizedBox(width: 14),
            rate(Icons.north_rounded, _green, s?.upRate ?? 0),
            const SizedBox(width: 14),
            Expanded(
              child: SizedBox(
                height: 20,
                child: CustomPaint(
                  painter: _Spark(down, up, ca: _w(.85), stroke: 1.3),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Text(
              _b((s?.up ?? 0) + (s?.down ?? 0)),
              style: _t(12, _w6, _w(.6)),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 16, color: _w(.6)),
          ],
        ),
      ),
    );
  }

  /// Tabs (or search field) + search toggle + add.
  Widget _dToolbar() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
    child: Row(
      children: [
        Expanded(
          child: searching
              ? SizedBox(
                  height: 32,
                  child: TextField(
                    autofocus: true,
                    onChanged: (v) => rebuild(() => query = v),
                    style: _t(12, FontWeight.w400, Colors.white),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search city, country or host',
                      hintStyle: _t(12, FontWeight.w400, _faint),
                      filled: true,
                      fillColor: _card,
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: _muted,
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 32),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: const BorderSide(color: _line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: const BorderSide(color: _blue, width: 1.5),
                      ),
                    ),
                  ),
                )
              : _tabs(),
        ),
        if (!searching && tab == 'all') ...[
          const SizedBox(width: 6),
          _iconBtn(
            allOpen ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
            toggleAll,
            pad: 5,
            tip: allOpen ? 'Collapse all' : 'Expand all',
          ),
        ],
        const SizedBox(width: 6),
        _iconBtn(
          searching ? Icons.close_rounded : Icons.search_rounded,
          () => rebuild(() {
            searching = !searching;
            query = '';
          }),
          pad: 5,
          tip: searching ? 'Close search' : 'Search',
        ),
        const SizedBox(width: 6),
        Opacity(
          opacity: locked ? .3 : 1,
          child: _tap(
            color: _blue,
            hover: _w(.1),
            radius: 9,
            onTap: locked || busy ? null : addSheet,
            child: SizedBox.square(
              dimension: 30,
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.add_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
            ),
          ),
        ),
      ],
    ),
  );

  /// Bottom bar: current subscription + usage; opens the Subscription sheet.
  Widget _dUsage() {
    final s = subs[cur], u = _Usage(s.usage), d = u.days;
    final text = u.total > 0
        ? '${_pair(u.used, u.total)}${d == null
              ? ''
              : d < 0
              ? ' · expired'
              : ' · ${d}d'}'
        : '${s.servers.length} servers';
    return Material(
      color: _bottomBar,
      child: InkWell(
        onTap: subSheet,
        hoverColor: _w(.03),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: _divider2)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 11),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    s.local ? Icons.folder_rounded : Icons.rss_feed_rounded,
                    size: 14,
                    color: s.local ? _muted : _blue,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _t(12, _w6),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.unfold_more_rounded,
                    size: 14,
                    color: _muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      text,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      style: _tm(11, d != null && d < 3 ? _red : _muted),
                    ),
                  ),
                ],
              ),
              if (u.total > 0) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: u.frac,
                    minHeight: 3,
                    color: u.frac > .9 ? _red : _blue,
                    backgroundColor: _line,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// First run: no servers yet.
  Widget _dEmpty() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _card,
              shape: BoxShape.circle,
              border: Border.all(color: _line),
            ),
            child: const Icon(Icons.public_rounded, size: 32, color: _blue),
          ),
          const SizedBox(height: 14),
          Text('Add your first server', style: _t(16, _w7)),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              'Add a subscription, paste a link or scan a QR code to get started',
              textAlign: TextAlign.center,
              style: _t(12, FontWeight.w400, _muted).copyWith(height: 1.5),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 260,
            child: _gap([
              _btn(
                'Add subscription',
                busy ? null : addSheet,
                icon: Icons.rss_feed_rounded,
                h: 38,
                font: 13,
                r: 10,
              ),
              Row(
                children: [
                  Expanded(
                    child: _btn(
                      'Clipboard',
                      busy ? null : () => _addMenu('clip'),
                      icon: Icons.content_paste_rounded,
                      primary: false,
                      h: 38,
                      r: 10,
                      pad: 8,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _btn(
                      'Scan QR',
                      busy ? null : () => _addMenu('screen'),
                      icon: Icons.qr_code_scanner_rounded,
                      primary: false,
                      h: 38,
                      r: 10,
                      pad: 8,
                    ),
                  ),
                ],
              ),
              _tryFree(),
            ], 8),
          ),
        ],
      ),
    ),
  );

  /// Full-window Preferences panel.
  Widget _dPrefs() => SizedBox.expand(
    child: Material(
      color: _bg,
      child: Column(
        children: [
          GestureDetector(
            onPanStart: (_) => dragWindow(),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _divider2)),
              ),
              child: Row(
                children: [
                  _iconBtn(
                    Icons.arrow_back_rounded,
                    () => rebuild(() => view = 'main'),
                    size: 20,
                    color: Colors.white,
                    tip: 'Back',
                  ),
                  const SizedBox(width: 8),
                  Text('Preferences', style: _t(15, _w7)),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              child: _gap(_settingsSections(), 14),
            ),
          ),
        ],
      ),
    ),
  );
}
