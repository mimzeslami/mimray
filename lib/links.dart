// Share links (vmess/vless/trojan/ss/hy2/ssh) and subscriptions -> sing-box outbounds.
import 'dart:convert';

class Server {
  final String name;
  final Map<String, dynamic> outbound;
  String? link; // original share link, for "Copy link"
  Server(this.name, this.outbound, [this.link]);
  String get host => outbound['server'];
  int get port => outbound['server_port'];
  Map<String, dynamic> toJson() => {
    'name': name,
    'outbound': outbound,
    'link': link,
  };
  factory Server.fromJson(Map<String, dynamic> j) =>
      Server(j['name'], Map<String, dynamic>.from(j['outbound']), j['link']);
}

/// Anything the user pastes / scans: share links, base64 subscription body,
/// or a JSON config (xray/v2ray `outbounds`, or sing-box outbounds).
List<Server> parseImport(String text) {
  final t = text.trim();
  if (t.startsWith('{') || t.startsWith('[')) {
    try {
      return parseJsonConfig(t);
    } catch (_) {
      return [];
    }
  }
  return parseSubscription(t);
}

/// v2ray/xray JSON (protocol + settings + streamSettings) or sing-box outbounds.
List<Server> parseJsonConfig(String text) {
  final j = jsonDecode(text);
  final List outs = j is List ? j : (j['outbounds'] ?? [j]);
  return [
    for (final o in outs)
      if (o is Map) ?_jsonOutbound(Map<String, dynamic>.from(o)),
  ];
}

Server? _jsonOutbound(Map<String, dynamic> o) {
  try {
    // sing-box outbound already
    if (o['type'] is String && o['server'] is String) {
      final name = (o.remove('tag') ?? '').toString();
      return _mk(name, o);
    }
    final p = o['protocol'];
    if (p is! String) return null;
    final set = Map<String, dynamic>.from(o['settings'] ?? {});
    final st = Map<String, dynamic>.from(o['streamSettings'] ?? {});
    final sec = st['security'] as String?;
    final tlsS = Map<String, dynamic>.from(
      st[sec == 'reality' ? 'realitySettings' : 'tlsSettings'] ?? {},
    );
    final net = st['network'] as String?;
    final ns = Map<String, dynamic>.from(
      st['${net == 'h2' ? 'http' : net}Settings'] ?? {},
    );
    String? host = ns['host'] is List
        ? (ns['host'] as List).firstOrNull
        : ns['host'];
    host ??= (ns['headers'] ?? {})['Host'];
    Map<String, dynamic> base(String addr, int port) => {
      'server': addr,
      'server_port': port,
      'tls': _tls(sec, tlsS['serverName'], addr, {
        'fp': tlsS['fingerprint'],
        'alpn': (tlsS['alpn'] as List?)?.join(','),
        'allowInsecure': tlsS['allowInsecure'] == true ? '1' : null,
        'pbk': tlsS['publicKey'],
        'sid': tlsS['shortId'],
      }),
      'transport': _transport(net, host, ns['path'], ns['serviceName']),
    };
    final name = (o['tag'] ?? '').toString();
    switch (p) {
      case 'vless':
      case 'vmess':
        final v = set['vnext'][0];
        final u = v['users'][0];
        return _mk(name, {
          'type': p,
          ...base(v['address'], v['port']),
          'uuid': u['id'],
          if (p == 'vless') 'flow': u['flow'],
          if (p == 'vmess') 'security': u['security'] ?? 'auto',
          if (p == 'vmess') 'alter_id': u['alterId'] ?? 0,
        });
      case 'trojan':
      case 'shadowsocks':
        final v = set['servers'][0];
        if (p == 'shadowsocks') {
          return _mk(name, {
            'type': 'shadowsocks',
            'server': v['address'],
            'server_port': v['port'],
            'method': v['method'],
            'password': v['password'],
          });
        }
        return _mk(name, {
          'type': 'trojan',
          ...base(v['address'], v['port']),
          'password': v['password'],
        });
    }
  } catch (_) {}
  return null;
}

String b64(String s) {
  s = s.replaceAll(RegExp(r'\s'), '').replaceAll('-', '+').replaceAll('_', '/');
  return utf8.decode(base64.decode(base64.normalize(s)));
}

/// Subscription body: base64 of newline-separated links, or plain links.
List<Server> parseSubscription(String body) {
  body = body.trim();
  if (!body.contains('://')) {
    try {
      body = b64(body);
    } catch (_) {}
  }
  return body
      .split(RegExp(r'[\r\n]+'))
      .map(parseLink)
      .whereType<Server>()
      .toList();
}

Server? parseLink(String link) {
  link = link.trim();
  final i = link.indexOf('://');
  if (i < 0) return null;
  try {
    final s = switch (link.substring(0, i).toLowerCase()) {
      'vmess' => _vmess(link.substring(i + 3)),
      'vless' => _vlessTrojan(Uri.parse(link), vless: true),
      'trojan' => _vlessTrojan(Uri.parse(link), vless: false),
      'ss' => _ss(link.substring(i + 3)),
      'hy2' || 'hysteria2' => _hy2(Uri.parse(link)),
      'ssh' => _ssh(Uri.parse(link)),
      _ => null,
    };
    return s?..link = link;
  } catch (_) {} // malformed or unsupported link: skip it
  return null;
}

String _dec(String s) {
  try {
    return Uri.decodeComponent(s);
  } catch (_) {
    return s;
  }
}

Server _mk(String name, Map<String, dynamic> out) {
  out.removeWhere((_, v) => v == null || v == '');
  final insecure = out['tls']?['insecure'] == true;
  if (name.isEmpty) name = '${out['server']}:${out['server_port']}';
  return Server(insecure ? '⚠ $name' : name, out);
}

String? _nz(String? s) => (s == null || s.isEmpty) ? null : s;

Map<String, dynamic>? _tls(
  String? security,
  String? sni,
  String host,
  Map<String, String?> q,
) {
  if (security != 'tls' && security != 'reality') return null;
  final fp = _nz(q['fp']) ?? (security == 'reality' ? 'chrome' : null);
  return {
    'enabled': true,
    'server_name': _nz(sni) ?? host,
    if (q['allowInsecure'] == '1' || q['insecure'] == '1') 'insecure': true,
    if (_nz(q['alpn']) != null) 'alpn': q['alpn']!.split(','),
    if (fp != null) 'utls': {'enabled': true, 'fingerprint': fp},
    if (security == 'reality')
      'reality': {
        'enabled': true,
        'public_key': q['pbk'],
        'short_id': q['sid'] ?? '',
      },
  };
}

Map<String, dynamic>? _transport(
  String? type,
  String? host,
  String? path,
  String? service,
) {
  host = _nz(host);
  switch (_nz(type) ?? 'tcp') {
    case 'tcp':
      return null;
    case 'ws':
      final t = <String, dynamic>{
        'type': 'ws',
        if (host != null) 'headers': {'Host': host},
      };
      var p = _nz(path) ?? '/';
      final u = Uri.parse(p);
      final ed = u.queryParameters['ed']; // xray-style early data in path
      if (ed != null) {
        final qp = {...u.queryParameters}..remove('ed');
        p = qp.isEmpty ? u.path : '${u.path}?${Uri(queryParameters: qp).query}';
        t['max_early_data'] = int.parse(ed);
        t['early_data_header_name'] = 'Sec-WebSocket-Protocol';
      }
      return t..['path'] = p;
    case 'grpc':
      return {'type': 'grpc', 'service_name': service ?? ''};
    case 'h2':
    case 'http':
      return {
        'type': 'http',
        if (host != null) 'host': [host],
        'path': _nz(path) ?? '/',
      };
    case 'httpupgrade':
      return {'type': 'httpupgrade', 'host': host, 'path': _nz(path) ?? '/'};
  }
  throw UnsupportedError('transport $type'); // e.g. xhttp: not in sing-box
}

Server _vmess(String body) {
  final j = jsonDecode(b64(body)) as Map;
  String? g(String k) => _nz(j[k]?.toString());
  final host = g('add')!;
  return _mk(g('ps') ?? '', {
    'type': 'vmess',
    'server': host,
    'server_port': int.parse(g('port')!),
    'uuid': g('id')!,
    'security': g('scy') ?? 'auto',
    'alter_id': int.tryParse(g('aid') ?? '') ?? 0,
    'tls': _tls(g('tls'), g('sni') ?? g('host'), host, {
      'alpn': g('alpn'),
      'fp': g('fp'),
      'allowInsecure': g('allowInsecure'),
    }),
    'transport': _transport(g('net'), g('host'), g('path'), g('path')),
  });
}

Server _vlessTrojan(Uri u, {required bool vless}) {
  final q = u.queryParameters;
  final user = _dec(u.userInfo);
  return _mk(_dec(u.fragment), {
    'type': vless ? 'vless' : 'trojan',
    'server': u.host,
    'server_port': u.port,
    if (vless) 'uuid': user else 'password': user,
    if (vless) 'flow': q['flow'],
    'tls': _tls(
      q['security'] ?? (vless ? null : 'tls'),
      q['sni'] ?? q['peer'],
      u.host,
      q,
    ),
    'transport': _transport(q['type'], q['host'], q['path'], q['serviceName']),
  });
}

Server _ss(String body) {
  final h = body.indexOf('#');
  final name = h < 0 ? '' : _dec(body.substring(h + 1));
  if (h >= 0) body = body.substring(0, h);
  if (!body.contains('@')) body = b64(body); // legacy: whole thing base64
  final at = body.lastIndexOf('@');
  var user = _dec(body.substring(0, at));
  if (!user.contains(':')) user = b64(user); // SIP002: userinfo base64
  final c = user.indexOf(':');
  final u = Uri.parse(
    'ss://x@${body.substring(at + 1).split(RegExp(r'[/?]')).first}',
  );
  return _mk(name, {
    'type': 'shadowsocks',
    'server': u.host,
    'server_port': u.port,
    'method': user.substring(0, c),
    'password': user.substring(c + 1),
  });
}

Server _hy2(Uri u) {
  final q = u.queryParameters;
  return _mk(_dec(u.fragment), {
    'type': 'hysteria2',
    'server': u.host,
    'server_port': u.hasPort ? u.port : 443,
    'password': _dec(u.userInfo),
    'tls': _tls('tls', q['sni'], u.host, {
      ...q,
      'fp': null,
    }), // hy2 is QUIC: no utls
    if (_nz(q['obfs-password']) != null)
      'obfs': {
        'type': q['obfs'] ?? 'salamander',
        'password': q['obfs-password'],
      },
  });
}

/// ssh://user:password@host:22#name  (no standard link exists; optional
/// ?pk=URL-encoded PEM private key &hk=host key, for key auth / pinning)
Server _ssh(Uri u) {
  final q = u.queryParameters;
  final ui = u.userInfo, c = ui.indexOf(':');
  return _mk(_dec(u.fragment), {
    'type': 'ssh',
    'server': u.host,
    'server_port': u.hasPort ? u.port : 22,
    'user': _dec(c < 0 ? ui : ui.substring(0, c)),
    'password': c < 0 ? null : _dec(ui.substring(c + 1)),
    'private_key': q['pk'],
    if (_nz(q['hk']) != null) 'host_key': [q['hk']],
  });
}
