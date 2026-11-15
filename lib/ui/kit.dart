part of '../main.dart';

// ---------- tokens ----------
const _bg = Color(0xFF0B1220);
const _card = Color(0xFF151F35);
const _card2 = Color(0xFF1B2742);
const _line = Color(0xFF22304D);
const _muted = Color(0xFF8A97B4);
const _blue = Color(0xFF2F7BFF);
const _blueLight = Color(0xFF5A97FF);
const _green = Color(0xFF3DDC97);
const _amber = Color(0xFFFFB547);
const _red = Color(0xFFFF5D6C);
const _bottomBar = Color(0xFF0E1628);
const _divider2 = Color(0xFF1A2540);
const _faint = Color(0xFF56627E);
const _starOff = Color(0xFF3A4866);
const _textSoft = Color(0xFFD5DCEB);
const _chart = Color(0xFFC9D2E6);
const _handle = Color(0xFF2A3A5C);
const _bolt = Color(0xFFFFD66B);
const _selBg = Color(0x242F7BFF); // blue .14
const _chipBg = Color(0x292F7BFF); // blue .16
const _navPill = Color(0x2E2F7BFF); // blue .18
const _scrim = Color(0x9E040812); // rgba(4,8,18,.62)
const _mono = 'GeistMono';

Color _w(double a) => Colors.white.withValues(alpha: a);

final appTheme = ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  fontFamily: 'Geist',
  scaffoldBackgroundColor: _bg,
  visualDensity: VisualDensity.compact,
  colorScheme: const ColorScheme.dark(
    primary: _blue,
    surface: _card,
    error: _red,
  ),
  textSelectionTheme: const TextSelectionThemeData(cursorColor: _blue),
  snackBarTheme: const SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: _card2,
    contentTextStyle: TextStyle(
      color: Colors.white,
      fontFamily: 'Geist',
      fontSize: 13,
    ),
  ),
  tooltipTheme: const TooltipThemeData(
    waitDuration: Duration(milliseconds: 600),
  ),
  dividerColor: _line,
);

TextStyle _t(
  double size, [
  FontWeight w = FontWeight.w400,
  Color? c,
  double? ls,
]) => TextStyle(
  fontSize: size,
  fontWeight: w,
  color: c,
  letterSpacing: ls,
  height: 1.25,
);

TextStyle _tm(double size, [Color? c, FontWeight w = FontWeight.w400]) =>
    TextStyle(
      fontFamily: _mono,
      fontSize: size,
      color: c,
      fontWeight: w,
      height: 1.25,
    );

const _w5 = FontWeight.w500, _w6 = FontWeight.w600, _w7 = FontWeight.w700;

/// Ping colour: <150 green, <350 amber, else red; timeout muted.
Color _pingColor(int? ms) => ms == null
    ? _muted
    : ms < 150
    ? _green
    : ms < 350
    ? _amber
    : _red;

String _pingText(int? ms, bool pending) => pending
    ? ''
    : ms == null
    ? '—'
    : '$ms ms';

/// "50.0 GB" -> "50 GB".
String _b(num n) => fmtBytes(n).replaceFirst('.0 ', ' ');

/// Rate per second: "4.2 MB/s", "380 KB/s".
String _rate(int n) {
  final p = fmtBytes(n).split(' '), v = double.parse(p[0]);
  return '${v >= 100 ? v.round() : p[0].replaceFirst(RegExp(r'\.0$'), '')} ${p[1]}/s';
}

/// "12.4 / 50 GB" (unit once when both match).
String _pair(int used, int total) {
  final u = _b(used), t = _b(total);
  final us = u.split(' '), ts = t.split(' ');
  return us.last == ts.last ? '${us.first} / $t' : '$u / $t';
}

/// Subscription usage from the `subscription-userinfo` header.
class _Usage {
  final int up, down, total, expire;
  _Usage(Map<String, int> u)
    : up = u['upload'] ?? 0,
      down = u['download'] ?? 0,
      total = u['total'] ?? 0,
      expire = u['expire'] ?? 0;
  int get used => up + down;
  double get frac => total > 0 ? (used / total).clamp(0, 1).toDouble() : 0;
  DateTime? get exp =>
      expire > 0 ? DateTime.fromMillisecondsSinceEpoch(expire * 1000) : null;
  int? get days => exp?.difference(DateTime.now()).inDays;
  String get date {
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final e = exp;
    return e == null ? '' : '${m[e.month - 1]} ${e.day}';
  }
}

/// Mask a subscription URL: keep scheme://host/first-segment, last 4 chars.
String _maskUrl(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.host.isEmpty || url.length < 24) return url;
  final seg = u.pathSegments.isEmpty ? '' : '/${u.pathSegments.first}';
  return '${u.scheme}://${u.host}$seg/••••••${url.substring(url.length - 4)}';
}

// ---------- widgets ----------

/// Tappable surface with the design's hover tint.
Widget _tap({
  required Widget child,
  VoidCallback? onTap,
  VoidCallback? onMenu,
  Color color = Colors.transparent,
  double radius = 10,
  Color hover = _card,
  BorderSide side = BorderSide.none,
}) => Material(
  color: color,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
    side: side,
  ),
  clipBehavior: Clip.antiAlias,
  child: InkWell(
    onTap: onTap,
    onLongPress: onMenu,
    onSecondaryTap: onMenu,
    hoverColor: hover,
    splashColor: _w(.04),
    highlightColor: _w(.03),
    child: child,
  ),
);

/// Small icon button (design: icon + padding, 6-7 px radius hover).
Widget _iconBtn(
  IconData i,
  VoidCallback? onTap, {
  double size = 18,
  Color color = _muted,
  double pad = 3,
  String? tip,
}) => Tooltip(
  message: tip ?? '',
  child: _tap(
    radius: 7,
    hover: _w(.1),
    onTap: onTap,
    child: Padding(
      padding: EdgeInsets.all(pad),
      child: Icon(i, size: size, color: color),
    ),
  ),
);

Widget _label(String t, {bool m = false}) => Padding(
  padding: EdgeInsets.symmetric(horizontal: m ? 4 : 0),
  child: Text(t.toUpperCase(), style: _t(m ? 12 : 10, _w6, _muted, 1)),
);

Widget _dot(Color c, double s) => Container(
  width: s,
  height: s,
  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
);

/// Circular flag; unflagged servers get a globe.
Widget _flag(String? cc, double size) {
  if (cc == null || cc.isEmpty) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: _card2, shape: BoxShape.circle),
      child: Icon(Icons.public_rounded, size: size * .62, color: _muted),
    );
  }
  return SizedBox.square(
    dimension: size,
    child: ClipOval(
      child: CountryFlag.fromCountryCode(
        cc,
        theme: ImageTheme(shape: const Circle(), width: size, height: size),
      ),
    ),
  );
}

/// Auto (bolt) badge.
Widget _boltBadge(double size, double icon) => Container(
  width: size,
  height: size,
  decoration: const BoxDecoration(color: _chipBg, shape: BoxShape.circle),
  child: Icon(Icons.bolt_rounded, size: icon, color: _blueLight),
);

/// Segmented control (tabs, DNS).
Widget _seg<T>({
  required List<(T, String, IconData?)> items,
  required T value,
  required void Function(T) onTap,
  double height = 26,
  double radius = 9,
  double inner = 2,
  double font = 12,
  double icon = 14,
  Color active = _line,
  bool compact = false, // label on the active segment only (4 tabs in 360 px)
}) => Container(
  padding: EdgeInsets.all(inner),
  decoration: BoxDecoration(
    color: _card,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: _line),
  ),
  child: Row(
    children: [
      for (final (v, l, i) in items)
        Expanded(
          flex: compact && v == value ? 5 : 3,
          child: GestureDetector(
            onTap: () => onTap(v),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Tooltip(
                message: compact && v != value ? l : '',
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: height,
                  decoration: BoxDecoration(
                    color: v == value ? active : Colors.transparent,
                    borderRadius: BorderRadius.circular(radius - inner),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (i != null)
                        Icon(
                          v == value ? i : _outline(i),
                          size: icon,
                          color: v == value ? Colors.white : _muted,
                        ),
                      if (!compact || v == value) ...[
                        if (i != null) SizedBox(width: font > 13 ? 5 : 4),
                        Flexible(
                          child: Text(
                            l,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: _t(
                              font,
                              _w6,
                              v == value ? Colors.white : _muted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  ),
);

IconData _outline(IconData i) =>
    i == Icons.star_rounded ? Icons.star_border_rounded : i;

/// Pill switch (desktop 34x20, mobile 50x30).
class _Toggle extends StatelessWidget {
  final bool value;
  final bool mobile;
  const _Toggle(this.value, {this.mobile = false});
  @override
  Widget build(BuildContext context) {
    final w = mobile ? 50.0 : 34.0, h = mobile ? 30.0 : 20.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: w,
      height: h,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value ? _blue : _line,
        borderRadius: BorderRadius.circular(h / 2),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: h - 4,
          height: h - 4,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// Header colours per phase (top, bottom, status colour, label).
(Color, Color, Color, String) _phaseLook(Phase p) => switch (p) {
  Phase.off => (
    const Color(0xFF1B2540),
    const Color(0xFF111A2E),
    _muted,
    'DISCONNECTED',
  ),
  Phase.connecting => (
    const Color(0xFF5A4519),
    const Color(0xFF1E1C1C),
    _amber,
    'CONNECTING',
  ),
  Phase.on => (
    const Color(0xFF1C5BFF),
    const Color(0xFF0F2E86),
    _green,
    'CONNECTED',
  ),
};

/// The round power button: off / connecting (rotating amber arc) / on (white
/// fill + pulse ring).
class _PowerButton extends StatefulWidget {
  final Phase phase;
  final double size;
  final bool mobile;
  final VoidCallback? onTap;
  const _PowerButton({
    required this.phase,
    required this.size,
    this.mobile = false,
    this.onTap,
  });
  @override
  State<_PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<_PowerButton>
    with TickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  void _sync() {
    widget.phase == Phase.connecting ? _spin.repeat() : _spin.stop();
    widget.phase == Phase.on ? _pulse.repeat() : _pulse.stop();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_PowerButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.phase, m = widget.mobile, s = widget.size;
    final on = p == Phase.on, con = p == Phase.connecting;
    final fill = on
        ? Colors.white
        : con
        ? _amber.withValues(alpha: .12)
        : _w(.06);
    final border = on
        ? Colors.white
        : con
        ? _amber.withValues(alpha: .5)
        : _w(.16);
    final icon = on
        ? const Color(0xFF1C5BFF)
        : con
        ? _amber
        : widget.onTap == null
        ? _w(.3)
        : _w(m ? .9 : .85);
    final shadow = on
        ? [
            BoxShadow(color: _w(m ? .1 : .12), spreadRadius: m ? 12 : 6),
            BoxShadow(
              color: const Color(0xFF00145A).withValues(alpha: m ? .55 : .5),
              offset: Offset(0, m ? 14 : 8),
              blurRadius: m ? 40 : 24,
            ),
          ]
        : m
        ? [BoxShadow(color: _w(.03), spreadRadius: 12)]
        : const <BoxShadow>[];
    final inset = m ? 6.0 : 4.0;
    return SizedBox.square(
      dimension: s,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (on)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, _) {
                  final t = Curves.easeOut.transform(_pulse.value);
                  return Transform.scale(
                    scale: 1 + (m ? .45 : .55) * t,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _w((m ? .3 * .5 : .35 * .55) * (1 - t)),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (con)
            Positioned(
              left: -inset,
              top: -inset,
              right: -inset,
              bottom: -inset,
              child: RotationTransition(
                turns: _spin,
                child: CustomPaint(painter: _Arc(m ? 3 : 2)),
              ),
            ),
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onTap,
              child: MouseRegion(
                cursor: widget.onTap == null
                    ? MouseCursor.defer
                    : SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: fill,
                    border: Border.all(color: border, width: m ? 2 : 1.5),
                    boxShadow: shadow,
                  ),
                  child: Icon(
                    Icons.power_settings_new_rounded,
                    size: m ? 60 : 30,
                    color: icon,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Top + right quarter borders of a circle (CSS border-top/right trick).
class _Arc extends CustomPainter {
  final double w;
  _Arc(this.w);
  @override
  void paint(Canvas canvas, Size size) => canvas.drawArc(
    (Offset.zero & size).deflate(w / 2),
    -math.pi * 3 / 4,
    math.pi,
    false,
    Paint()
      ..color = _amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = w,
  );
  @override
  bool shouldRepaint(_Arc old) => false;
}

/// "Tunnel m" mark. Small variant (thicker, taller legs) at <= 32 px.
class _Logo extends StatelessWidget {
  final double size;
  final Color right;
  const _Logo({this.size = 18, this.right = _blue});
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _LogoPainter(Colors.white, right, size <= 32),
  );
}

class _LogoPainter extends CustomPainter {
  final Color left, right;
  final bool small;
  _LogoPainter(this.left, this.right, this.small);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64);
    final (x0, r, y1, sw) = small
        ? (9.0, 11.5, 56.0, 12.0)
        : (10.0, 11.0, 50.0, 7.0);
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(x0, y1)
        ..lineTo(x0, 30)
        ..arcToPoint(const Offset(32, 30), radius: Radius.circular(r))
        ..lineTo(32, y1),
      p(left),
    );
    canvas.drawPath(
      Path()
        ..moveTo(32, 30)
        ..arcToPoint(Offset(32 + 2 * r, 30), radius: Radius.circular(r))
        ..lineTo(32 + 2 * r, y1),
      p(right),
    );
  }

  @override
  bool shouldRepaint(_LogoPainter o) => o.left != left || o.right != right;
}

/// Mark + "mimray" wordmark (Geist Bold, −0.04em, gap ≈ 0.28 × font size).
Widget _wordmark(double font, {Color right = _blue}) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    _Logo(size: font * 1.3, right: right),
    SizedBox(width: font * .28),
    Text('mimray', style: _t(font, _w7, Colors.white, -.04 * font)),
  ],
);

/// Live down/up speed graph (last 60 samples).
class _Spark extends CustomPainter {
  final List<double> a, b;
  final Color ca;
  final double stroke;
  _Spark(this.a, this.b, {this.ca = _chart, this.stroke = 1.4});

  @override
  void paint(Canvas canvas, Size size) {
    final top = [...a, ...b, 1024.0].reduce(math.max);
    for (final (l, c) in [(a, ca), (b, _green)]) {
      if (l.length < 2) continue;
      final p = Path();
      for (var i = 0; i < l.length; i++) {
        final x = size.width * (i + 60 - l.length) / 59;
        final y = size.height - 1 - (size.height - 2) * l[i] / top;
        i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
      }
      canvas.drawPath(
        p,
        Paint()
          ..color = c
          ..strokeWidth = stroke
          ..strokeJoin = StrokeJoin.round
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

/// White QR tile, or a note when the text doesn't fit a QR code.
Widget _qr(String data, double size, double radius) {
  List<List<bool>>? m;
  try {
    m = qrMatrix(data);
  } catch (_) {}
  return Container(
    width: size,
    height: size,
    padding: EdgeInsets.all(size * .06),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: m == null
        ? Center(
            child: Text(
              'Too long for a QR code',
              textAlign: TextAlign.center,
              style: _tm(10, _faint),
            ),
          )
        : CustomPaint(painter: _QrPainter(m)),
  );
}
