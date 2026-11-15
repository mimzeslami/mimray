part of '../main.dart';

/// The "Free" location tab: opt-in, working public servers, community-shared
/// servers, and "Share your server".
extension _FreeTab on _HomeState {
  Widget _freeTab() {
    final pad = m
        ? const EdgeInsets.fromLTRB(10, 10, 10, 12)
        : const EdgeInsets.fromLTRB(8, 0, 8, 8);
    if (!freeOn) {
      return SingleChildScrollView(padding: pad, child: _freeIntro());
    }
    final rows = <Widget>[
      _freeHeader(),
      if (freePool.isNotEmpty) _freeAutoRow(),
      _freeSection(
        'Free servers',
        '${free.length} ${reachOnly ? 'reachable' : 'working'}',
      ),
      for (var k = 0; k < free.length; k++) _freeRow(k),
      if (free.isEmpty) _freeHint(_emptyText()),
      _freeSection('Shared by the community', '${shared.length}'),
      for (var k = 0; k < shared.length; k++) _freeRow(free.length + k),
      if (shared.isEmpty)
        _freeHint(
          freeUpdated == null
              ? 'Volunteers share servers here after review.'
              : 'None working right now.',
        ),
      if (reachOnly && freePool.isNotEmpty)
        _freeHint(
          'On Android a server is checked for reachability only. Auto picks '
          'one that really works when you connect.',
        ),
      Padding(
        padding: EdgeInsets.fromLTRB(m ? 4 : 2, m ? 12 : 10, m ? 4 : 2, 0),
        child: _shareButton(),
      ),
    ];
    return ListView.separated(
      padding: pad,
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (_, k) => rows[k],
    );
  }

  String _emptyText() => freeBusy
      ? 'Testing servers from your device…'
      : freeUpdated == null
      ? 'Not tested yet. Tap Update.'
      : 'None of the tested servers work from here right now. Try Update later.';

  /// Off: what it is + "Turn on free servers".
  Widget _freeIntro() => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: m ? 14 : 12,
      vertical: m ? 24 : 16,
    ),
    child: Column(
      children: [
        Container(
          width: m ? 64 : 52,
          height: m ? 64 : 52,
          decoration: BoxDecoration(
            color: _card,
            shape: BoxShape.circle,
            border: Border.all(color: _line),
          ),
          child: Icon(
            Icons.redeem_rounded,
            size: m ? 30 : 24,
            color: _blueLight,
          ),
        ),
        SizedBox(height: m ? 14 : 12),
        Text('Free servers', style: _t(m ? 19 : 15, _w7)),
        SizedBox(height: m ? 10 : 8),
        Text(
          'Public servers anyone can use, plus servers shared by the mimray '
          'community. mimray tests them from your device and lists only the '
          'ones that work.',
          textAlign: TextAlign.center,
          style: _t(m ? 14 : 12, FontWeight.w400, _muted).copyWith(height: 1.5),
        ),
        SizedBox(height: m ? 10 : 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: m ? 16 : 14, color: _amber),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Run by strangers — not for logins, banking or anything private.',
                style: _t(m ? 13 : 11, FontWeight.w400, _amber),
              ),
            ),
          ],
        ),
        SizedBox(height: m ? 18 : 14),
        _btn(
          'Turn on free servers',
          () => setFree(true),
          icon: Icons.redeem_rounded,
          h: m ? 52 : 38,
          font: m ? 15 : 13,
          r: m ? 14 : 10,
        ),
        SizedBox(height: m ? 10 : 8),
        _shareButton(),
      ],
    ),
  );

  /// Last updated · Update (progress while testing).
  Widget _freeHeader() {
    final u = freeUpdated;
    final line1 = freeBusy
        ? freeStatus ?? 'Updating…'
        : locked
        ? 'Disconnect to re-test'
        : u == null
        ? 'Not tested yet'
        : 'Updated ${_ago(u)}';
    final line2 = freeAuto ? 'Auto-update every 6 h' : 'Auto-update off';
    return Container(
      margin: EdgeInsets.only(bottom: m ? 6 : 4),
      padding: EdgeInsets.fromLTRB(
        m ? 14 : 12,
        m ? 10 : 8,
        m ? 8 : 6,
        m ? 10 : 8,
      ),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(m ? 14 : 10),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _t(
                        m ? 14 : 12,
                        _w6,
                        locked && !freeBusy ? _amber : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      line2,
                      style: _t(m ? 12 : 11, FontWeight.w400, _muted),
                    ),
                  ],
                ),
              ),
              _btn(
                'Update',
                freeBusy || locked ? null : updateFree,
                icon: Icons.refresh_rounded,
                primary: false,
                h: m ? 36 : 28,
                font: m ? 13 : 12,
                r: m ? 10 : 8,
                pad: m ? 12 : 10,
                fg: Colors.white,
              ),
            ],
          ),
          if (freeBusy) ...[
            SizedBox(height: m ? 10 : 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: freeProgress,
                minHeight: 3,
                color: _blue,
                backgroundColor: _line,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _freeSection(String label, String count) => Padding(
    padding: EdgeInsets.fromLTRB(m ? 6 : 4, m ? 14 : 10, m ? 6 : 4, m ? 6 : 4),
    child: Row(
      children: [
        Expanded(child: _label(label, m: false)),
        Text(count, style: _t(m ? 12 : 10, _w6, _muted, 1)),
      ],
    ),
  );

  Widget _freeHint(String t) => Padding(
    padding: EdgeInsets.symmetric(horizontal: m ? 12 : 10, vertical: m ? 8 : 6),
    child: Text(
      t,
      style: _t(m ? 13 : 11, FontWeight.w400, _faint).copyWith(height: 1.4),
    ),
  );

  bool _freeLive(int i) =>
      onFree && phase == Phase.on && selected < 0 && stats?.active == i;

  Widget _freeAutoRow() {
    final sel = onFree && selected < 0;
    return Opacity(
      opacity: locked && !sel ? .45 : 1,
      child: _tap(
        color: sel ? _selBg : Colors.transparent,
        radius: m ? 14 : 10,
        onTap: locked ? null : () => pickFree(-1),
        child: Padding(
          padding: EdgeInsets.all(m ? 10 : 8),
          child: Row(
            children: [
              _boltBadge(m ? 34 : 26, m ? 20 : 16),
              SizedBox(width: m ? 12 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Auto', style: _t(m ? 16 : 13, _w6)),
                        const SizedBox(width: 6),
                        _freeBadge(),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Fastest working free server',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _t(m ? 13 : 11, FontWeight.w400, _muted),
                    ),
                  ],
                ),
              ),
              Opacity(
                opacity: sel ? 1 : 0,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: m ? 22 : 18,
                  color: _blue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A free (i < free.length) or community server row; i indexes [freePool].
  Widget _freeRow(int i) {
    final f = freePool[i], s = f.server, cc = _cc(s.name);
    final sel = onFree && i == selected;
    final sub = f.community ? 'by ${f.donor}' : countryName(cc);
    return Opacity(
      opacity: locked && !sel && !_freeLive(i) ? .45 : 1,
      child: _tap(
        color: sel ? _selBg : Colors.transparent,
        radius: m ? 14 : 10,
        onTap: locked ? null : () => pickFree(i),
        child: SizedBox(
          height: m ? 58 : 42,
          child: Padding(
            padding: EdgeInsets.only(left: m ? 10 : 8, right: m ? 10 : 8),
            child: Row(
              children: [
                f.community
                    ? Container(
                        width: m ? 34 : 26,
                        height: m ? 34 : 26,
                        decoration: const BoxDecoration(
                          color: _chipBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.volunteer_activism_rounded,
                          size: m ? 18 : 14,
                          color: _blueLight,
                        ),
                      )
                    : _flag(cc, m ? 34 : 26),
                SizedBox(width: m ? 12 : 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _clean(s.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _t(m ? 16 : 13, sel ? _w6 : FontWeight.w400),
                      ),
                      Text(
                        '$sub · ${_proto(s.outbound['type'])}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _t(m ? 13 : 11, FontWeight.w400, _muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_freeLive(i)) ...[
                  _dot(_green, 6),
                  const SizedBox(width: 6),
                ],
                Text(
                  f.delay == null ? '—' : '${f.delay} ms',
                  style: _tm(m ? 13 : 11, _delayColor(f.delay)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _shareButton() => _btn(
    'Share your server',
    _shareSheet,
    icon: Icons.volunteer_activism_rounded,
    primary: false,
    h: m ? 46 : 34,
    font: m ? 14 : 12,
    r: m ? 12 : 9,
    fg: Colors.white,
  );

  /// First-run link to the Free tab.
  Widget _tryFree() => Center(
    child: _link('Or try free servers', Icons.redeem_rounded, () {
      rebuild(() {
        tab = 'free';
        if (mobile) nav = 1;
      });
    }),
  );

  /// Opt-in warning. True = the user accepted.
  Future<bool?> _freeWarning() => _sheet<bool>(
    (c) => _gap([
      Row(
        children: [
          Container(
            width: m ? 40 : 32,
            height: m ? 40 : 32,
            decoration: BoxDecoration(
              color: _amber.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(m ? 12 : 9),
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              size: m ? 22 : 18,
              color: _amber,
            ),
          ),
          SizedBox(width: m ? 12 : 10),
          Expanded(
            child: Text('Before you turn this on', style: _t(m ? 20 : 16, _w7)),
          ),
        ],
      ),
      Text(
        'Free servers are run by people you don\'t know.',
        style: _t(m ? 15 : 13, _w6),
      ),
      for (final t in [
        'They can see and log any traffic that isn\'t encrypted — and some free '
            'servers exist precisely to watch the people who use them.',
        'Don\'t use them for logins, banking or anything sensitive.',
        'Servers shared by the community come from volunteers. They are '
            'reviewed before they appear, but nobody can guarantee them.',
      ])
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: m ? 7 : 6, right: 10, left: 2),
              child: _dot(_amber, 5),
            ),
            Expanded(
              child: Text(
                t,
                style: _t(
                  m ? 14 : 12,
                  FontWeight.w400,
                  _textSoft,
                ).copyWith(height: 1.45),
              ),
            ),
          ],
        ),
      Text(
        'If you can, use your own server or a subscription you trust.',
        style: _t(m ? 14 : 12, FontWeight.w400, _muted).copyWith(height: 1.45),
      ),
      Row(
        children: [
          Expanded(
            child: _btn(
              'Cancel',
              () => Navigator.pop(c, false),
              primary: false,
              h: m ? 46 : 34,
              font: m ? 14 : 12,
              r: m ? 12 : 9,
            ),
          ),
          SizedBox(width: m ? 10 : 8),
          Expanded(
            flex: 2,
            child: _btn(
              'I understand, turn on',
              () => Navigator.pop(c, true),
              h: m ? 46 : 34,
              font: m ? 14 : 12,
              r: m ? 12 : 9,
            ),
          ),
        ],
      ),
    ], m ? 14 : 12),
  );

  /// Warns that the link becomes public, then opens the GitHub issue form
  /// (prefilled with the picked server's link).
  Future<void> _shareSheet() async {
    final mine = [
      for (final s in servers)
        if (s.link != null) s,
    ];
    var pickIdx = -1;
    final ok = await _sheet<bool>(
      (c) => StatefulBuilder(
        builder: (c, set) => _gap([
          _title('Share your server'),
          Container(
            padding: EdgeInsets.all(m ? 14 : 10),
            decoration: BoxDecoration(
              color: _amber.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(m ? 12 : 9),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.public_rounded, size: m ? 20 : 16, color: _amber),
                SizedBox(width: m ? 10 : 8),
                Expanded(
                  child: Text(
                    'The link becomes PUBLIC. Anyone can see it and use your '
                    'server and its bandwidth. Only share a server you are '
                    'happy to give away.',
                    style: _t(
                      m ? 14 : 12,
                      FontWeight.w400,
                      _amber,
                    ).copyWith(height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          Text(
            'It is reviewed on GitHub before it appears in the app.',
            style: _t(m ? 13 : 11, FontWeight.w400, _muted),
          ),
          if (mine.isNotEmpty) ...[
            _label('Prefill with one of your servers (optional)', m: m),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: m ? 220 : 150),
              child: SingleChildScrollView(
                child: _box([
                  for (var k = 0; k < mine.length; k++)
                    _row(
                      pickIdx == k
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      _clean(mine[k].name),
                      iconColor: pickIdx == k ? _blue : _muted,
                      pad: m ? 11 : 8,
                      onTap: () => set(() => pickIdx = pickIdx == k ? -1 : k),
                    ),
                ], color: _bg),
              ),
            ),
          ],
          Row(
            children: [
              Expanded(
                child: _btn(
                  'Cancel',
                  () => Navigator.pop(c, false),
                  primary: false,
                  h: m ? 46 : 34,
                  font: m ? 14 : 12,
                  r: m ? 12 : 9,
                ),
              ),
              SizedBox(width: m ? 10 : 8),
              Expanded(
                flex: 2,
                child: _btn(
                  'Continue on GitHub',
                  () => Navigator.pop(c, true),
                  icon: Icons.open_in_new_rounded,
                  h: m ? 46 : 34,
                  font: m ? 14 : 12,
                  r: m ? 12 : 9,
                ),
              ),
            ],
          ),
        ], m ? 12 : 10),
      ),
    );
    if (ok != true) return;
    final link = pickIdx >= 0 ? mine[pickIdx].link : null;
    try {
      await openUrl(
        link == null
            ? shareUrl
            : '$shareUrl&link=${Uri.encodeQueryComponent(link)}',
      );
    } catch (e) {
      _toast('$e');
    }
  }

  /// Core-tested delay is a full HTTPS fetch through the server (slower than
  /// a TCP ping), so it gets wider bands; Android's TCP check uses ping bands.
  Color _delayColor(int? ms) => reachOnly || ms == null
      ? _pingColor(ms)
      : ms < 600
      ? _green
      : ms < 1200
      ? _amber
      : _red;
}

Widget _freeBadge() => Container(
  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
  decoration: BoxDecoration(
    color: _green.withValues(alpha: .14),
    borderRadius: BorderRadius.circular(4),
    border: Border.all(color: _green.withValues(alpha: .5)),
  ),
  child: Text('FREE', style: _t(9, _w7, _green, .6)),
);

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  return d.inMinutes < 1
      ? 'just now'
      : d.inMinutes < 60
      ? '${d.inMinutes} min ago'
      : d.inHours < 24
      ? '${d.inHours} h ago'
      : '${d.inDays} d ago';
}
