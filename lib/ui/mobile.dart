part of '../main.dart';

/// Mobile shell (Android / iOS): Home / Locations / Settings tabs + sheets.
extension _MobileShell on _HomeState {
  Widget _mobileShell() => Scaffold(
    backgroundColor: _bg,
    body: switch (nav) {
      1 => _mLocations(),
      2 => _mSettings(),
      _ => _mHome(),
    },
    bottomNavigationBar: DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _divider2)),
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: _bottomBar,
          indicatorColor: _navPill,
          indicatorShape: const StadiumBorder(),
          height: 64,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (s) => _t(
              11,
              _w6,
              s.contains(WidgetState.selected) ? Colors.white : _muted,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (s) => IconThemeData(
              size: 22,
              color: s.contains(WidgetState.selected) ? Colors.white : _muted,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: nav,
          elevation: 0,
          onDestinationSelected: (i) => rebuild(() => nav = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.shield_outlined),
              selectedIcon: Icon(Icons.shield_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.public_rounded),
              label: 'Locations',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    ),
  );

  Widget _mHome() {
    final (c1, c2, sc, label) = _phaseLook(phase);
    final on = phase == Phase.on;
    final top = MediaQuery.paddingOf(context).top;
    final header = AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: EdgeInsets.fromLTRB(20, top + 8, 20, 26),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c1, c2],
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                _wordmark(17, right: on ? _green : _blue),
                const SizedBox(width: 12),
                if (subs.isNotEmpty)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _tap(
                        color: _w(.1),
                        hover: _w(.06),
                        radius: 16,
                        onTap: subSheet,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
                          child: SizedBox(
                            height: 32,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  subs[cur].local
                                      ? Icons.folder_rounded
                                      : Icons.rss_feed_rounded,
                                  size: 15,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    subs[cur].name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: _t(13, _w6),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.expand_more_rounded,
                                  size: 16,
                                  color: _w(.7),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 34),
          _PowerButton(
            phase: phase,
            size: 148,
            mobile: true,
            onTap: pool.isEmpty ? null : _toggle,
          ),
          const SizedBox(height: 26),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _dot(sc, 8),
              const SizedBox(width: 7),
              Text(label, style: _t(12, _w7, sc, 1.4)),
              if (since != null) ...[
                const SizedBox(width: 7),
                Text(
                  _dur(DateTime.now().difference(since!)),
                  style: _tm(12, _w(.7)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            locSub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _t(15, FontWeight.w400, _w(.75)),
          ),
          if (msg != null) ...[
            const SizedBox(height: 8),
            Text(
              msg!,
              maxLines: 3,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: _t(12, FontWeight.w400, const Color(0xFFFFB3BA)),
            ),
          ],
        ],
      ),
    );
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (pool.isEmpty && !onFree) _mEmpty() else _mCards(),
        ],
      ),
    );
  }

  Widget _mCard(Widget child, VoidCallback onTap) => _tap(
    color: _card,
    radius: 18,
    hover: _card2,
    side: const BorderSide(color: _line),
    onTap: onTap,
    child: Padding(padding: const EdgeInsets.all(14), child: child),
  );

  Widget _mCards() {
    final a = activeIndex, cc = a == null ? null : _cc(pool[a].name);
    final title = selected >= 0 && !onFree
        ? '${_clean(pool[selected].name)}, ${countryName(cc)}'
        : locTitle;
    final s = stats, u = _Usage(subs.isEmpty ? const {} : subs[cur].usage);
    Widget rate(bool dl) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              dl ? Icons.south_rounded : Icons.north_rounded,
              size: 15,
              color: dl ? _muted : _green,
            ),
            const SizedBox(width: 4),
            Text(
              dl ? 'Download' : 'Upload',
              style: _t(12, FontWeight.w400, dl ? _muted : _green),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(_rate(dl ? s?.downRate ?? 0 : s?.upRate ?? 0), style: _t(20, _w7)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: _gap([
        if (update != null) _updateBanner(mobile: true),
        _mCard(
          Row(
            children: [
              a != null ? _flag(cc, 36) : _boltBadge(36, 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('LOCATION', style: _t(11, _w6, _muted, .6)),
                        if (onFree) ...[const SizedBox(width: 6), _freeBadge()],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _t(16, _w6),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 22, color: _muted),
            ],
          ),
          () => rebuild(() {
            nav = 1;
            if (onFree) tab = 'free';
          }),
        ),
        if (phase == Phase.on)
          _mCard(
            _gap([
              Row(
                children: [
                  Expanded(child: rate(true)),
                  const SizedBox(width: 10),
                  Expanded(child: rate(false)),
                ],
              ),
              SizedBox(
                height: 34,
                child: CustomPaint(painter: _Spark(down, up, stroke: 1.4)),
              ),
            ], 10),
            statsSheet,
          ),
        if (u.total > 0)
          _mCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Data used',
                        style: _t(13, FontWeight.w400, _muted),
                      ),
                    ),
                    Text(
                      _pair(u.used, u.total),
                      style: _tm(13, Colors.white, _w5),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: u.frac,
                    minHeight: 5,
                    color: u.frac > .9 ? _red : _blue,
                    backgroundColor: _line,
                  ),
                ),
                if (u.days case final d?) ...[
                  const SizedBox(height: 8),
                  Text(
                    d < 0
                        ? 'Expired · ${u.date}'
                        : 'Renews in $d days · ${u.date}',
                    style: _t(12, FontWeight.w400, d < 3 ? _red : _muted),
                  ),
                ],
              ],
            ),
            subSheet,
          ),
      ], 10),
    );
  }

  Widget _mEmpty() => Padding(
    padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
    child: _gap([
      Text(
        'Add your first server',
        textAlign: TextAlign.center,
        style: _t(19, _w7),
      ),
      Text(
        'Add a subscription, paste a link or scan a QR code to get started',
        textAlign: TextAlign.center,
        style: _t(14, FontWeight.w400, _muted).copyWith(height: 1.5),
      ),
      const SizedBox(height: 0),
      _btn(
        'Add subscription',
        busy ? null : addSheet,
        icon: Icons.rss_feed_rounded,
        h: 52,
        font: 15,
        r: 14,
      ),
      Row(
        children: [
          Expanded(
            child: _btn(
              'Clipboard',
              busy ? null : () => _addMenu('clip'),
              icon: Icons.content_paste_rounded,
              primary: false,
              h: 52,
              font: 14,
              r: 14,
              pad: 8,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _btn(
              'Scan QR',
              busy ? null : () => _addMenu('screen'),
              icon: Icons.qr_code_scanner_rounded,
              primary: false,
              h: 52,
              font: 14,
              r: 14,
              pad: 8,
            ),
          ),
        ],
      ),
      _tryFree(),
    ], 14),
  );

  Widget _mLocations() {
    final top = MediaQuery.paddingOf(context).top;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, top + 12, 20, 12),
          child: Row(
            children: [
              Expanded(child: Text('Locations', style: _t(28, _w7, null, -.5))),
              Opacity(
                opacity: locked ? .3 : 1,
                child: _tap(
                  color: _blue,
                  radius: 20,
                  hover: _w(.1),
                  onTap: locked || busy ? null : addSheet,
                  child: const SizedBox.square(
                    dimension: 40,
                    child: Icon(
                      Icons.add_rounded,
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _gap([
            SizedBox(
              height: 42,
              child: TextField(
                onChanged: (v) => rebuild(() => query = v),
                style: _t(15, FontWeight.w400, Colors.white),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: _card,
                  hintText: 'Search city or country',
                  hintStyle: _t(15, FontWeight.w400, _faint),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: _faint,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 40),
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _blue, width: 1.5),
                  ),
                ),
              ),
            ),
            _tabs(),
          ], 10),
        ),
        Expanded(
          child: servers.isEmpty && tab != 'free'
              ? Center(
                  child: Text(
                    'No servers yet',
                    style: _t(14, FontWeight.w400, _muted),
                  ),
                )
              : _locations(),
        ),
      ],
    );
  }

  Widget _mSettings() => ListView(
    padding: EdgeInsets.fromLTRB(
      16,
      MediaQuery.paddingOf(context).top + 12,
      16,
      20,
    ),
    children: [
      _gap([
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('Settings', style: _t(28, _w7, null, -.5)),
        ),
        ..._settingsSections(),
      ], 18),
    ],
  );
}
