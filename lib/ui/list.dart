part of '../main.dart';

/// Location list (All / Favorites / Recent), shared by both shells.
extension _Locations on _HomeState {
  Widget _locations() {
    if (tab == 'free') return _freeTab();
    final rows = <Widget>[];
    Widget hint(String t) {
      final st = _t(m ? 13 : 11, FontWeight.w400, _faint);
      final (a, b) = t.contains('☆')
          ? (t.split('☆')[0], t.split('☆')[1])
          : (t, '');
      return Padding(
        padding: m
            ? const EdgeInsets.symmetric(horizontal: 24, vertical: 16)
            : const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: a),
              if (b.isNotEmpty) ...[
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(
                    Icons.star_border_rounded,
                    size: m ? 15 : 13,
                    color: _faint,
                  ),
                ),
                TextSpan(text: b),
              ],
            ],
          ),
          textAlign: TextAlign.center,
          style: st,
        ),
      );
    }

    if (tab == 'all') {
      final g = groups;
      if (query.isEmpty) rows.add(_autoRow());
      for (final (cc, idx) in g) {
        rows.add(_countryRow(cc, idx));
        if (expanded.contains(cc) || query.isNotEmpty) {
          rows.addAll(idx.map(_nodeRow));
        }
      }
      if (g.isEmpty) rows.add(hint('No matches'));
    } else {
      final f = flat;
      rows.addAll(f.map(_flatRow));
      rows.add(
        hint(
          query.isNotEmpty && f.isEmpty
              ? 'No matches'
              : tab == 'fav'
              ? 'Tap ☆ on any location to pin it here'
              : 'Your last connected locations',
        ),
      );
    }
    return ListView.separated(
      padding: m
          ? const EdgeInsets.fromLTRB(10, 10, 10, 12)
          : const EdgeInsets.fromLTRB(8, 0, 8, 8),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (_, k) => rows[k],
    );
  }

  bool _live(int i) => phase == Phase.on && subSel == -1 && stats?.active == i;
  double _dim(int i) => locked && i != subSel && !_live(i) ? .45 : 1;

  Widget _autoRow() => Opacity(
    opacity: locked && subSel != -1 ? .45 : 1,
    child: _tap(
      color: subSel == -1 ? _selBg : Colors.transparent,
      radius: m ? 14 : 10,
      onTap: locked ? null : () => pick(-1),
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
                  Text('Auto', style: _t(m ? 16 : 13, _w6)),
                  const SizedBox(height: 1),
                  Text(
                    m
                        ? 'Fastest working server'
                        : 'Fastest working server, switches by itself',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(m ? 13 : 11, FontWeight.w400, _muted),
                  ),
                ],
              ),
            ),
            Opacity(
              opacity: subSel == -1 ? 1 : 0,
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

  Widget _countryRow(String cc, List<int> idx) {
    final open = expanded.contains(cc) || query.isNotEmpty;
    final right = idx.length > 1
        ? '${idx.length} locations'
        : _pingText(pings[idx.first], !pings.containsKey(idx.first));
    return _tap(
      radius: m ? 14 : 10,
      onTap: () => toggleGroup(cc),
      child: Padding(
        padding: EdgeInsets.all(m ? 10 : 8),
        child: Row(
          children: [
            _flag(cc, m ? 34 : 26),
            SizedBox(width: m ? 12 : 10),
            Expanded(
              child: Text(
                countryName(cc),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _t(m ? 16 : 13, _w5),
              ),
            ),
            Text(right, style: _t(m ? 13 : 11, FontWeight.w400, _muted)),
            SizedBox(width: m ? 12 : 10),
            AnimatedRotation(
              turns: open ? .5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.expand_more_rounded,
                size: m ? 22 : 18,
                color: _muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _star(int i) {
    final f = isFav(i);
    return _iconBtn(
      f ? Icons.star_rounded : Icons.star_border_rounded,
      () => toggleFav(i),
      size: m ? 20 : 16,
      color: f ? _amber : _starOff,
      pad: m ? 6 : 3,
      tip: f ? 'Remove from favorites' : 'Add to favorites',
    );
  }

  Widget _ping(int i) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_live(i)) ...[_dot(_green, 6), const SizedBox(width: 6)],
      Text(
        _pingText(pings[i], !pings.containsKey(i)),
        style: _tm(m ? 13 : 11, _pingColor(pings[i])),
      ),
    ],
  );

  Widget _nodeRow(int i) {
    final sel = i == subSel;
    return Opacity(
      opacity: _dim(i),
      child: _tap(
        color: sel ? _selBg : Colors.transparent,
        radius: m ? 12 : 9,
        onTap: locked ? null : () => pick(i),
        onMenu: () => serverSheet(i),
        child: SizedBox(
          height: m ? 46 : 34,
          child: Padding(
            padding: EdgeInsets.only(left: m ? 56 : 44, right: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _clean(servers[i].name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(
                      m ? 15 : 13,
                      sel ? _w6 : FontWeight.w400,
                      sel ? Colors.white : _textSoft,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _ping(i),
                SizedBox(width: m ? 2 : 6),
                _star(i),
                _iconBtn(
                  Icons.more_horiz_rounded,
                  () => serverSheet(i),
                  size: m ? 20 : 16,
                  pad: m ? 6 : 3,
                  tip: 'Server details',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _flatRow(int i) {
    final sel = i == subSel, cc = _cc(servers[i].name);
    return Opacity(
      opacity: _dim(i),
      child: _tap(
        color: sel ? _selBg : Colors.transparent,
        radius: m ? 14 : 10,
        onTap: locked ? null : () => pick(i),
        onMenu: () => serverSheet(i),
        child: SizedBox(
          height: m ? 58 : 42,
          child: Padding(
            padding: EdgeInsets.only(left: m ? 10 : 8, right: 6),
            child: Row(
              children: [
                _flag(cc, m ? 34 : 26),
                SizedBox(width: m ? 12 : 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _clean(servers[i].name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _t(m ? 16 : 13, sel ? _w6 : FontWeight.w400),
                      ),
                      Text(
                        countryName(cc),
                        style: _t(m ? 13 : 11, FontWeight.w400, _muted),
                      ),
                    ],
                  ),
                ),
                _ping(i),
                SizedBox(width: m ? 2 : 6),
                _star(i),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// All / Favorites / Recent segmented tabs.
  Widget _tabs() => _seg<String>(
    items: const [
      ('all', 'All', Icons.public_rounded),
      ('fav', 'Favorites', Icons.star_rounded),
      ('recent', 'Recent', Icons.history_rounded),
      ('free', 'Free', Icons.redeem_rounded),
    ],
    compact: true,
    value: tab,
    onTap: (v) => rebuild(() => tab = v),
    height: m ? 34 : 26,
    radius: m ? 12 : 9,
    inner: m ? 3 : 2,
    font: m ? 14 : 12,
    icon: m ? 17 : 14,
  );
}
