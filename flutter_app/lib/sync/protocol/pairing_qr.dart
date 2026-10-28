/// The QR code the PC shows and the phone scans.
/// OFFLINE_FIRST_SYNC_PLAYBOOK.md §5.1.
library;

import 'dart:convert';

import 'protocol.dart';

class PairingCode {
  const PairingCode({
    required this.host,
    required this.port,
    required this.serverId,
    required this.pairingToken,
    this.version = protocolVersion,
  });

  /// Throws a [FormatException] with user-ready text on anything that is not
  /// one of our codes.
  factory PairingCode.decode(String raw) {
    Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (_) {
      throw const FormatException('Not a pairing code');
    }
    if (parsed is! Map) throw const FormatException('Not a pairing code');

    final version = parsed['v'];
    final host = parsed['host'];
    final port = parsed['port'];
    final serverId = parsed['serverId'];
    final token = parsed['pairingToken'];

    if (version is! num ||
        host is! String ||
        port is! num ||
        serverId is! String ||
        token is! String) {
      throw const FormatException('Not a pairing code');
    }
    if (version.toInt() != protocolVersion) {
      throw const FormatException(
        'That code comes from a different version of this app',
      );
    }
    if (host.isEmpty || serverId.isEmpty || token.isEmpty) {
      throw const FormatException('Not a pairing code');
    }
    if (port < 1 || port > 65535) {
      throw const FormatException('Not a pairing code');
    }
    return PairingCode(
      host: host,
      port: port.toInt(),
      serverId: serverId,
      pairingToken: token,
      version: version.toInt(),
    );
  }

  final String host;
  final int port;
  final String serverId;
  final String pairingToken;
  final int version;

  String get baseUrl => 'http://$host:$port';

  String encode() => jsonEncode({
    'v': version,
    'host': host,
    'port': port,
    'serverId': serverId,
    'pairingToken': pairingToken,
  });
}
