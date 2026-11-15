part of '../main.dart';

/// Sheets + settings content shared by both shells; `m` switches to the
/// mobile sizes (28 px sheet radius, larger type).
extension _Sheets on _HomeState {
  bool get m => mobile;

  // ---------- building blocks ----------

  /// Bottom sheet that rebuilds on every state change (live stats, stars).
  Future<T?> _sheet<T>(Widget Function(BuildContext) b) {
    final h = MediaQuery.sizeOf(context).height;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      barrierColor: _scrim,
      elevation: 0,
      constraints: BoxConstraints(maxHeight: h * (m ? .86 : .88)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(m ? 28 : 18)),
        side: const BorderSide(color: _line),
      ),
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
        child: ValueListenableBuilder(
          valueListenable: _rev,
          builder: (_, _, _) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              m ? 20 : 16,
              m ? 10 : 8,
              m ? 20 : 16,
              (m ? 24 : 16) + MediaQuery.paddingOf(c).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: m ? 40 : 36,
                    height: m ? 5 : 4,
                    margin: EdgeInsets.only(bottom: m ? 16 : 12),
                    decoration: BoxDecoration(
                      color: _handle,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                b(c),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(String t, {Widget? trailing}) => Row(
    children: [
      Expanded(
        child: Text(
          t,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _t(m ? 20 : 16, _w7),
        ),
      ),
      ?trailing,
    ],
  );

  Widget _gap(List<Widget> c, double g, {bool stretch = true}) => Column(
    crossAxisAlignment: stretch
        ? CrossAxisAlignment.stretch
        : CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < c.length; i++) ...[
        if (i > 0) SizedBox(height: g),
        c[i],
      ],
    ],
  );

  /// Equal-width grid (rows of [cols]).
  Widget _grid(List<Widget> items, int cols, double gap, [double vgap = -1]) =>
      _gap([
        for (var r = 0; r < items.length; r += cols)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var k = r; k < r + cols; k++) ...[
                if (k > r) SizedBox(width: gap),
                Expanded(child: k < items.length ? items[k] : const SizedBox()),
              ],
            ],
          ),
      ], vgap < 0 ? gap : vgap);

  Widget _field(
    TextEditingController c,
    String hint, {
    bool autofocus = false,
    bool mono = false,
    int lines = 1,
    double vpad = -1,
    ValueChanged<String>? onSubmit,
  }) {
    final fs = m ? 14.0 : 12.0;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(m ? 12 : 8),
      borderSide: const BorderSide(color: _line),
    );
    return TextField(
      controller: c,
      autofocus: autofocus,
      minLines: lines,
      maxLines: lines,
      onSubmitted: onSubmit,
      style: mono
          ? _tm(fs, Colors.white)
          : _t(fs, FontWeight.w400, Colors.white),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: mono ? _tm(fs, _muted) : _t(fs, FontWeight.w400, _faint),
        contentPadding: EdgeInsets.symmetric(
          horizontal: m ? 12 : 10,
          vertical: vpad >= 0 ? vpad : (m ? 14 : 9),
        ),
        enabledBorder: border,
        border: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: _blue, width: 1.5),
        ),
      ),
    );
  }

  Widget _btn(
    String label,
    VoidCallback? onTap, {
    IconData? icon,
    double h = 32,
    double font = 12,
    double r = 8,
    bool primary = true,
    double pad = 16,
    Color? fg,
  }) => Opacity(
    opacity: onTap == null ? .45 : 1,
    child: _tap(
      color: primary ? _blue : _card2,
      hover: _w(.08),
      radius: r,
      side: primary ? BorderSide.none : const BorderSide(color: _line),
      onTap: onTap,
      child: SizedBox(
        height: h,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: font + 5,
                    color: fg ?? (primary ? Colors.white : _muted),
                  ),
                  SizedBox(width: primary ? 8 : 6),
                ],
                Text(
                  label,
                  style: _t(
                    font,
                    primary ? _w6 : _w5,
                    primary ? Colors.white : fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _link(String label, IconData icon, VoidCallback onTap) => _tap(
    radius: 6,
    hover: _w(.06),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: m ? 18 : 16, color: _blueLight),
          const SizedBox(width: 4),
          Text(label, style: _t(m ? 14 : 12, _w5, _blueLight)),
        ],
      ),
    ),
  );

  /// Card with hairline separators between rows.
  Widget _box(List<Widget> rows, {Color color = _card, double? r}) => Container(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(r ?? (m ? 16 : 12)),
      border: Border.all(color: _line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1, thickness: 1, color: _line),
          rows[i],
        ],
      ],
    ),
  );

  /// Icon + text list row inside a [_box].
  Widget _row(
    IconData icon,
    String text, {
    VoidCallback? onTap,
    Color? color,
    Color iconColor = _muted,
    String? sub,
    Widget? trailing,
    double? pad,
  }) => _tap(
    radius: 0,
    hover: _card2,
    onTap: onTap,
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: m ? 14 : 12,
        vertical: pad ?? (m ? 13 : 10),
      ),
      child: Row(
        children: [
          Icon(icon, size: m ? 20 : 18, color: color ?? iconColor),
          SizedBox(width: m ? 12 : 10),
          Expanded(
            child: sub == null
                ? Text(text, style: _t(m ? 15 : 13, FontWeight.w400, color))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(text, style: _t(m ? 15 : 13, _w5, color)),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: _t(m ? 12 : 11, FontWeight.w400, _muted),
                      ),
                    ],
                  ),
          ),
          ?trailing,
        ],
      ),
    ),
  );

  Widget _formSheet(
    BuildContext c, {
    required String title,
    required List<Widget> fields,
    required String ok,
  }) => _gap([
    _title(title),
    ...fields,
    Row(
      children: [
        const Spacer(),
        _btn(
          'Cancel',
          () => Navigator.pop(c),
          primary: false,
          h: m ? 44 : 32,
          font: m ? 14 : 12,
          r: m ? 12 : 8,
        ),
        const SizedBox(width: 8),
        _btn(
          ok,
          () => Navigator.pop(c, 'ok'),
          h: m ? 44 : 32,
          font: m ? 14 : 12,
          r: m ? 12 : 8,
        ),
      ],
    ),
  ], m ? 12 : 10);

  // ---------- sheets ----------

  Future<void> addSheet() {
    if (locked) return Future.value();
    final url = TextEditingController(), name = TextEditingController();
    return _sheet((c) {
      void add() {
        if (url.text.trim().isEmpty) return;
        Navigator.pop(c);
        _addSub(url.text, name.text);
      }

      void imp(String a) {
        Navigator.pop(c);
        _addMenu(a);
      }

      final tiles = _grid(
        [
          for (final (a, i, l, lm) in [
            (
              'clip',
              Icons.content_paste_rounded,
              'From clipboard',
              'From clipboard',
            ),
            (
              'screen',
              Icons.qr_code_scanner_rounded,
              'Scan QR on screen',
              'Scan QR code',
            ),
            ('qrfile', Icons.image_rounded, 'QR image…', 'QR from photo'),
            ('file', Icons.file_open_rounded, 'Config file…', 'Config file'),
          ])
            _tap(
              color: _card2,
              radius: m ? 16 : 12,
              hover: const Color(0xFF223154),
              side: const BorderSide(color: _line),
              onTap: () => imp(a),
              child: Padding(
                padding: m
                    ? const EdgeInsets.fromLTRB(14, 16, 14, 16)
                    : const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(i, size: m ? 24 : 20, color: _blueLight),
                    SizedBox(height: m ? 10 : 8),
                    Text(m ? lm : l, style: _t(m ? 14 : 12, _w5)),
                  ],
                ),
              ),
            ),
        ],
        2,
        m ? 10 : 8,
      );
      final subBlock = Container(
        padding: EdgeInsets.all(m ? 14 : 10),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(m ? 16 : 12),
          border: Border.all(color: _line),
        ),
        child: _gap([
          Row(
            children: [
              Icon(Icons.rss_feed_rounded, size: m ? 18 : 16, color: _blue),
              const SizedBox(width: 8),
              Text('Subscription URL', style: _t(m ? 14 : 12, _w6)),
            ],
          ),
          _field(
            url,
            'https://…',
            autofocus: !m,
            mono: true,
            vpad: m ? 14 : 10,
            onSubmit: (_) => add(),
          ),
          if (m)
            _btn('Add subscription', add, h: 46, font: 15, r: 12)
          else
            Row(
              children: [
                Expanded(
                  child: _field(
                    name,
                    'Name (optional)',
                    vpad: 9,
                    onSubmit: (_) => add(),
                  ),
                ),
                const SizedBox(width: 8),
                _btn('Add', add),
              ],
            ),
        ], m ? 10 : 8),
      );
      final manual = _tap(
        radius: 8,
        hover: _w(.04),
        onTap: () => imp('manual'),
        child: Padding(
          padding: m
              ? const EdgeInsets.fromLTRB(2, 4, 2, 4)
              : const EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Row(
            children: [
              Icon(Icons.edit_note_rounded, size: m ? 20 : 18, color: _muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  m
                      ? 'Paste links or JSON manually'
                      : 'Paste vmess:// vless:// trojan:// ss:// hy2:// links manually',
                  style: _t(m ? 14 : 12, FontWeight.w400, _muted),
                ),
              ),
            ],
          ),
        ),
      );
      return _gap([
        _title('Add servers'),
        if (m) ...[tiles, subBlock] else ...[subBlock, tiles],
        manual,
      ], m ? 14 : 12);
    });
  }

  Future<void> subSheet() => _sheet((c) {
    if (subs.isEmpty) return const SizedBox();
    final i = cur, s = subs[i], u = _Usage(s.usage);
    final n = s.servers.length;
    final countries = {for (final x in s.servers) ?_cc(x.name)}.length;
    void act(String a) {
      Navigator.pop(c);
      a == 'add' ? addSheet() : _subAction(i, a);
    }

    final header = Row(
      children: [
        Container(
          width: m ? 44 : 34,
          height: m ? 44 : 34,
          decoration: BoxDecoration(
            color: _chipBg,
            borderRadius: BorderRadius.circular(m ? 14 : 10),
          ),
          child: Icon(
            s.local ? Icons.folder_rounded : Icons.rss_feed_rounded,
            size: m ? 22 : 18,
            color: _blueLight,
          ),
        ),
        SizedBox(width: m ? 12 : 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _t(m ? 20 : 16, _w7),
              ),
              Text(
                s.local ? '$n imported servers' : _maskUrl(s.src),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: s.local
                    ? _t(m ? 12 : 11, FontWeight.w400, _muted)
                    : _tm(m ? 12 : 11, _muted),
              ),
            ],
          ),
        ),
        if (!m) _iconBtn(Icons.edit_rounded, () => act('edit'), tip: 'Edit'),
      ],
    );

    Widget legend(Color c, String t) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dot(c, m ? 8 : 7),
        SizedBox(width: m ? 6 : 5),
        Text(t, style: _t(m ? 13 : 11, FontWeight.w400, _muted)),
      ],
    );
    Widget kv(String k, String v) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: _t(m ? 12 : 11, FontWeight.w400, _muted)),
          const SizedBox(height: 2),
          Text(v, style: _t(m ? 14 : 12, _w6)),
        ],
      ),
    );
    final days = u.days;
    final usage = Container(
      padding: EdgeInsets.all(m ? 16 : 12),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(m ? 16 : 12),
        border: Border.all(color: _line),
      ),
      child: _gap([
        if (u.total > 0) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _b(u.used),
                style: _t(m ? 30 : 24, _w7, null, m ? -.6 : -.5),
              ),
              const SizedBox(width: 6),
              Text(
                m ? 'of ${_b(u.total)}' : 'of ${_b(u.total)} used',
                style: _t(m ? 14 : 12, FontWeight.w400, _muted),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (_, k) => Container(
              height: m ? 8 : 6,
              decoration: BoxDecoration(
                color: _line,
                borderRadius: BorderRadius.circular(4),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  Container(
                    width: k.maxWidth * (u.down / u.total).clamp(0, 1),
                    color: _blue,
                  ),
                  Container(
                    width:
                        k.maxWidth *
                        (u.up / u.total).clamp(
                          0,
                          1 - (u.down / u.total).clamp(0, 1),
                        ),
                    color: _green,
                  ),
                ],
              ),
            ),
          ),
          Wrap(
            spacing: m ? 16 : 14,
            children: [
              legend(_blue, '${m ? 'Down' : 'Download'} ${_b(u.down)}'),
              legend(_green, '${m ? 'Up' : 'Upload'} ${_b(u.up)}'),
            ],
          ),
        ],
        Container(
          padding: EdgeInsets.only(top: u.total > 0 ? (m ? 12 : 10) : 0),
          decoration: BoxDecoration(
            border: u.total > 0
                ? const Border(top: BorderSide(color: _line))
                : null,
          ),
          child: Row(
            children: [
              kv(
                'Expires',
                days == null
                    ? 'Never'
                    : days < 0
                    ? 'Expired'
                    : '${u.date} · $days days',
              ),
              kv(
                'Servers',
                countries == 0
                    ? '$n servers'
                    : '$n in $countries ${countries == 1 ? 'country' : 'countries'}',
              ),
            ],
          ),
        ),
      ], m ? 12 : 10),
    );

    final chips = !m && subs.length > 1
        ? _gap([
            _label('Switch subscription'),
            _grid(
              [
                for (var j = 0; j < subs.length; j++)
                  Opacity(
                    opacity: locked && j != i ? .45 : 1,
                    child: _tap(
                      color: j == i ? _chipBg : _card2,
                      radius: 9,
                      hover: _w(.05),
                      side: BorderSide(color: j == i ? _blue : _line),
                      onTap: locked ? null : () => selectSub(j),
                      onMenu: null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              subs[j].local
                                  ? Icons.folder_rounded
                                  : Icons.rss_feed_rounded,
                              size: 14,
                              color: j == i ? _blue : _muted,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                subs[j].local
                                    ? '${subs[j].name} · ${subs[j].servers.length}'
                                    : subs[j].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _t(12, j == i ? _w6 : FontWeight.w400),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
              2,
              6,
            ),
          ], 6)
        : null;

    final acts = [
      ('update', Icons.refresh_rounded, 'Update', !s.local && !busy, _textSoft),
      ('qrurl', Icons.qr_code_rounded, 'Show QR', !s.local, _textSoft),
      ('copyall', Icons.copy_all_rounded, 'Copy links', n > 0, _textSoft),
      (
        'file',
        m ? Icons.ios_share_rounded : Icons.save_alt_rounded,
        'Export',
        n > 0,
        _textSoft,
      ),
      ('copyurl', Icons.link_rounded, 'Copy URL', !s.local, _textSoft),
      (
        'edit',
        Icons.edit_rounded,
        s.local ? 'Rename' : 'Edit',
        true,
        _textSoft,
      ),
      ('add', Icons.add_rounded, 'Add new', !locked, _blueLight),
      ('delete', Icons.delete_rounded, 'Delete', !locked, _red),
    ];
    final grid = _grid(
      [
        for (final (a, ic, l, on, col) in acts)
          Opacity(
            opacity: on ? 1 : .35,
            child: _tap(
              color: _card2,
              radius: m ? 14 : 10,
              hover: const Color(0xFF223154),
              onTap: on ? () => act(a) : null,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: m ? 12 : 10,
                ),
                child: Column(
                  children: [
                    Icon(ic, size: m ? 22 : 18, color: col),
                    const SizedBox(height: 6),
                    Text(
                      l,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: _t(m ? 11 : 10, FontWeight.w400, col),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
      4,
      m ? 8 : 6,
    );
    return _gap([header, usage, ?chips, grid], m ? 16 : 14);
  });

  Future<void> serverSheet(int i) => _sheet((c) {
    if (i >= servers.length) return const SizedBox();
    final s = servers[i], cc = _cc(s.name), fav = isFav(i);
    final ms = pings[i], pending = !pings.containsKey(i);
    final lat = pending
        ? 'Testing…'
        : ms == null
        ? 'Timeout'
        : '$ms ms';
    final proto = _protoLong(s.outbound), host = '${s.host}:${s.port}';
    final data = _serverExport(s);
    void act(String a) {
      Navigator.pop(c);
      _serverAction(i, a);
    }

    final star = _iconBtn(
      fav ? Icons.star_rounded : Icons.star_border_rounded,
      () => toggleFav(i),
      size: m ? 26 : 20,
      color: fav ? _amber : _faint,
      pad: 2,
      tip: fav ? 'Remove from favorites' : 'Add to favorites',
    );
    final head = Row(
      children: [
        _flag(cc, m ? 42 : 32),
        SizedBox(width: m ? 12 : 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _clean(s.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _t(m ? 20 : 16, _w7),
              ),
              Text(
                m ? '${countryName(cc)} · $proto' : countryName(cc),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _t(m ? 13 : 11, FontWeight.w400, _muted),
              ),
            ],
          ),
        ),
        star,
      ],
    );
    final copyLabel = s.link != null ? 'Copy link' : 'Copy JSON';
    if (m) {
      Widget sq(IconData ic, Color col, VoidCallback f) => _tap(
        color: _card2,
        radius: 14,
        onTap: f,
        child: SizedBox.square(
          dimension: 48,
          child: Icon(ic, size: 20, color: col),
        ),
      );
      return _gap([
        head,
        Center(child: _qr(data, 200, 18)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _tm(13, _muted),
              ),
            ),
            const SizedBox(width: 16),
            Text(lat, style: _tm(13, _pingColor(ms))),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _btn(
                copyLabel,
                () => act('copy'),
                icon: Icons.content_copy_rounded,
                h: 48,
                font: 14,
                r: 14,
              ),
            ),
            const SizedBox(width: 10),
            sq(Icons.ios_share_rounded, Colors.white, () => act('file')),
            if (!locked) ...[
              const SizedBox(width: 10),
              sq(Icons.delete_rounded, _red, () => act('delete')),
            ],
          ],
        ),
      ], 16);
    }
    Widget kv(String k, String v, TextStyle st) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: _t(10, FontWeight.w400, _muted)),
        const SizedBox(height: 2),
        Text(v, maxLines: 2, overflow: TextOverflow.ellipsis, style: st),
      ],
    );
    return _gap([
      head,
      Row(
        children: [
          _qr(data, 120, 12),
          const SizedBox(width: 14),
          Expanded(
            child: _gap([
              kv('PROTOCOL', proto, _t(12, _w6)),
              kv('HOST', host, _tm(12, Colors.white)),
              kv('LATENCY', lat, _t(12, _w6, _pingColor(ms))),
            ], 8),
          ),
        ],
      ),
      _box([
        _row(Icons.content_copy_rounded, copyLabel, onTap: () => act('copy')),
        _row(
          Icons.save_alt_rounded,
          'Export to file',
          onTap: () => act('file'),
        ),
        if (!locked)
          _row(
            Icons.delete_rounded,
            'Delete server',
            color: _red,
            onTap: () => act('delete'),
          ),
      ], color: _bg),
    ], 14);
  });

  Future<void> statsSheet() => _sheet((c) {
    final st = stats, a = activeIndex;
    final srv = a == null ? null : pool[a];
    final peak = [...down, ...up, 0.0].reduce(math.max);
    final cc = ip?['country'] is String ? ip!['country'] as String : null;
    final loc = [
      ip?['city'],
      if (cc != null) m ? cc : countryName(cc),
    ].whereType<String>().join(', ');
    final rows = [
      ('EXIT IP', ip?['ip']?.toString() ?? '—'),
      ('LOCATION', loc.isEmpty ? '—' : loc),
      ('SERVER', srv?.host ?? (selected < 0 ? 'Auto' : '—')),
      ('PROTOCOL', srv == null ? '—' : _protoLong(srv.outbound)),
      ('CONNECTIONS', '${st?.conns ?? 0} active'),
      ('UPTIME', since == null ? '—' : _dur(DateTime.now().difference(since!))),
    ];
    final grid = _grid(
      [
        for (final (k, v) in rows)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(k, style: _t(m ? 11 : 10, FontWeight.w400, _muted, .5)),
              SizedBox(height: m ? 3 : 2),
              Text(
                v,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _t(m ? 15 : 12, _w5),
              ),
            ],
          ),
      ],
      2,
      12,
      m ? 14 : 10,
    );
    Widget rate(bool dl) {
      final col = dl ? _muted : _green;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!m)
                Icon(
                  dl ? Icons.south_rounded : Icons.north_rounded,
                  size: 14,
                  color: col,
                ),
              if (!m) const SizedBox(width: 4),
              Text(
                m
                    ? (dl ? '↓ Download' : '↑ Upload')
                    : (dl ? 'Download' : 'Upload'),
                style: _t(m ? 12 : 11, FontWeight.w400, col),
              ),
            ],
          ),
          SizedBox(height: m ? 2 : 4),
          Text(
            _rate(dl ? st?.downRate ?? 0 : st?.upRate ?? 0),
            style: _t(m ? 24 : 20, _w7),
          ),
          SizedBox(height: m ? 0 : 2),
          Text(
            '${_b(dl ? st?.down ?? 0 : st?.up ?? 0)} total',
            style: _t(m ? 12 : 11, FontWeight.w400, _muted),
          ),
        ],
      );
    }

    BoxDecoration box() => BoxDecoration(
      color: _bg,
      borderRadius: BorderRadius.circular(m ? 16 : 12),
      border: Border.all(color: _line),
    );
    final chart = SizedBox(
      height: m ? 80 : 70,
      width: double.infinity,
      child: CustomPaint(painter: _Spark(down, up, stroke: 1.2)),
    );
    if (m) {
      return _gap([
        _title('Connection'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: box(),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: rate(true)),
                  const SizedBox(width: 10),
                  Expanded(child: rate(false)),
                ],
              ),
              const SizedBox(height: 12),
              chart,
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: grid,
        ),
      ], 14);
    }
    return _gap([
      _title('Connection'),
      Row(
        children: [
          for (final dl in [true, false]) ...[
            if (!dl) const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: box(),
                child: rate(dl),
              ),
            ),
          ],
        ],
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        decoration: box(),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'LAST 60 SECONDS',
                    style: _t(10, FontWeight.w400, _muted, .5),
                  ),
                ),
                Text(
                  'peak ${_rate(peak.round())}',
                  style: _t(10, FontWeight.w400, _muted, .5),
                ),
              ],
            ),
            const SizedBox(height: 6),
            chart,
          ],
        ),
      ),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: grid),
    ], 12);
  });

  Future<void> _logSheet() => _sheet((c) {
    final lines = logText.isEmpty ? ['No log yet.'] : logText.split('\n');
    final a = activeIndex, host = a == null ? null : pool[a].host;
    Color col(String l) => l.contains('ERROR') || l.contains('FATAL')
        ? _red
        : l.contains('WARN')
        ? _amber
        : host != null && l.contains(host)
        ? _green
        : _muted;
    return _gap([
      _title(
        'Core log',
        trailing: m
            ? _link(
                'Copy',
                Icons.content_copy_rounded,
                () => _copy(logText, 'Log'),
              )
            : _link(
                'Show file',
                Icons.folder_open_rounded,
                () => reveal(core.log),
              ),
      ),
      Container(
        height: m ? 400 : 300,
        padding: EdgeInsets.all(m ? 12 : 10),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(m ? 14 : 10),
          border: Border.all(color: _line),
        ),
        child: SelectionArea(
          child: LayoutBuilder(
            // reverse: opens scrolled to the newest line; minHeight keeps a
            // short log at the top
            builder: (_, k) => SingleChildScrollView(
              reverse: true,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: k.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final l in lines)
                      Padding(
                        padding: EdgeInsets.only(bottom: m ? 4 : 3),
                        child: Text(
                          l,
                          style: _tm(
                            m ? 11 : 10.5,
                            col(l),
                          ).copyWith(height: 1.45),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ], m ? 12 : 10);
  });

  Future<void> _showQr(String title, String data) => _sheet(
    (c) => _gap([
      _title(title),
      Center(child: _qr(data, m ? 260 : 220, 16)),
      Center(
        child: _link(
          'Copy text',
          Icons.content_copy_rounded,
          () => _copy(data, 'Text'),
        ),
      ),
    ], 14),
  );

  Future<String?> _textSheet(String title, String hint, {int lines = 1}) {
    final t = TextEditingController();
    return _sheet<String>(
      (c) => _gap([
        _title(title),
        _field(t, hint, autofocus: true, mono: true, lines: lines),
        Row(
          children: [
            _link('Paste', Icons.content_paste_rounded, () async {
              final d = await Clipboard.getData('text/plain');
              t.text = d?.text ?? '';
            }),
            const Spacer(),
            _btn(
              'Cancel',
              () => Navigator.pop(c),
              primary: false,
              h: m ? 44 : 32,
              font: m ? 14 : 12,
              r: m ? 12 : 8,
            ),
            const SizedBox(width: 8),
            _btn(
              'Import',
              () => Navigator.pop(c, t.text),
              h: m ? 44 : 32,
              font: m ? 14 : 12,
              r: m ? 12 : 8,
            ),
          ],
        ),
      ], 12),
    );
  }

  // ---------- settings (desktop Preferences panel / mobile Settings tab) ----------

  List<Widget> _settingsSections() {
    final rows = [
      (
        'Connect on launch',
        'Start the tunnel when mimray opens',
        opt.autoConnect,
        (bool x) => opt.autoConnect = x,
      ),
      (
        'Smart Gemini routing',
        'Send Gemini via a supported country when needed',
        opt.smartAi,
        (bool x) => opt.smartAi = x,
      ),
      (
        'Block QUIC',
        'Forces TCP — more reliable through proxies',
        opt.blockQuic,
        (bool x) => opt.blockQuic = x,
      ),
      (
        'Bypass LAN',
        m
            ? 'Local network stays direct'
            : 'Local network (printers, NAS, router) stays direct',
        opt.bypassLan,
        (bool x) => opt.bypassLan = x,
      ),
    ];
    Widget section(String l, Widget body) =>
        _gap([_label(l, m: m), body], m ? 8 : 6);
    final installed = helper != null;
    return [
      if (locked)
        Container(
          padding: m
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _amber.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(m ? 12 : 8),
          ),
          child: Text(
            'Changes apply on next connect.',
            style: _t(m ? 13 : 12, FontWeight.w400, _amber),
          ),
        ),
      if (m)
        section(
          'Subscriptions',
          _box([
            for (var j = 0; j < subs.length; j++)
              _row(
                subs[j].local ? Icons.folder_rounded : Icons.rss_feed_rounded,
                subs[j].name,
                iconColor: subs[j].local ? _muted : _blue,
                sub: _subLine(subs[j]),
                onTap: j == cur
                    ? subSheet
                    : (locked ? null : () => selectSub(j)),
                trailing: j == cur
                    ? const Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: _blue,
                      )
                    : null,
              ),
            _row(
              Icons.refresh_rounded,
              'Update all subscriptions',
              onTap: busy ? null : _updateAll,
            ),
          ]),
        ),
      section(
        'Connection',
        _box([
          for (final (t, s, v, f) in rows)
            _switchRow(t, s, v, () => setOpt(() => f(!v))),
        ]),
      ),
      section(
        'Free servers',
        _box([
          _switchRow(
            'Free servers (community)',
            'Public servers run by strangers — read the warning first',
            freeOn,
            () => setFree(!freeOn),
          ),
          if (freeOn)
            _switchRow(
              'Auto-update',
              'Re-test every 6 hours while disconnected',
              freeAuto,
              () => setOpt(() => freeAuto = !freeAuto),
            ),
        ]),
      ),
      section(
        m ? 'Secure DNS' : 'Secure DNS · DoH through the tunnel',
        _seg<String>(
          items: [for (final e in dnsChoices.entries) (e.key, e.value, null)],
          value: opt.dns,
          onTap: (v) => setOpt(() => opt.dns = v),
          height: m ? 38 : 30,
          radius: m ? 12 : 10,
          inner: m ? 3 : 2,
          font: m ? 14 : 12,
          active: _blue,
        ),
      ),
      if (helperAvailable)
        section(
          'Password prompt',
          _box([
            _row(
              installed ? Icons.verified_user_rounded : Icons.key_rounded,
              installed
                  ? 'Background helper installed'
                  : 'Asked for password on every connect',
              iconColor: installed ? _green : _amber,
              sub: installed
                  ? 'Connects without a password'
                  : 'Install the helper once to stop the prompts',
              trailing: installed
                  ? Opacity(
                      opacity: locked ? .4 : 1,
                      child: _tap(
                        radius: 6,
                        hover: _w(.06),
                        onTap: locked ? null : () => _helperAction(true),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text(
                            'Remove',
                            style: _t(m ? 14 : 12, _w6, _blueLight),
                          ),
                        ),
                      ),
                    )
                  : _btn(
                      'Install',
                      () => _helperAction(false),
                      h: m ? 34 : 28,
                      pad: 12,
                    ),
            ),
          ]),
        ),
      if (!m)
        section(
          'Tools',
          _box([
            _row(
              Icons.refresh_rounded,
              'Update all subscriptions',
              onTap: busy ? null : _updateAll,
              pad: 11,
            ),
            _row(
              Icons.receipt_long_rounded,
              'Core log',
              onTap: _openLog,
              pad: 11,
              trailing: const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: _muted,
              ),
            ),
          ]),
        ),
      if (m)
        _box([
          _row(
            Icons.receipt_long_rounded,
            'Core log',
            onTap: _openLog,
            trailing: const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: _muted,
            ),
          ),
          _about(),
        ])
      else
        _about(),
    ];
  }

  Widget _switchRow(String t, String s, bool v, VoidCallback onTap) => _tap(
    radius: 0,
    hover: _card2,
    onTap: onTap,
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: m ? 14 : 12,
        vertical: m ? 12 : 10,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t, style: _t(m ? 15 : 13, _w5)),
                const SizedBox(height: 2),
                Text(s, style: _t(m ? 12 : 11, FontWeight.w400, _muted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _Toggle(v, mobile: m),
        ],
      ),
    ),
  );

  Widget _about() => Padding(
    padding: EdgeInsets.symmetric(horizontal: m ? 14 : 2, vertical: m ? 13 : 2),
    child: Row(
      children: [
        _Logo(size: m ? 20 : 20),
        SizedBox(width: m ? 12 : 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'mimray $appVersion',
                style: _t(m ? 15 : 12, m ? FontWeight.w400 : _w6),
              ),
              SizedBox(height: m ? 2 : 0),
              Text(
                'sing-box core · github.com/mimzeslami/mimray',
                style: _t(m ? 12 : 11, FontWeight.w400, _muted),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: demo ? null : () => _checkUpdate(manual: true),
          child: Text(
            'Check for updates',
            style: _t(m ? 13 : 11, _w6, _blueLight),
          ),
        ),
      ],
    ),
  );

  /// "13 servers · 12.4 / 50 GB" / "3 imported servers".
  String _subLine(Sub s) {
    final u = _Usage(s.usage), n = s.servers.length;
    if (s.local) return '$n imported servers';
    return u.total > 0
        ? '$n servers · ${_pair(u.used, u.total)}'
        : '$n servers';
  }
}
