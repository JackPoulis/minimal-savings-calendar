/// The wire contract, shared by the hub and the client so there is one source
/// of truth for it. OFFLINE_FIRST_SYNC_PLAYBOOK.md §4.
library;

const protocolVersion = 1;

/// The hub listens here, falling back to any free port if it is taken — the
/// QR code carries the real one.
const defaultPort = 8765;

const apiPrefix = '/api/v1';

class Paths {
  const Paths._();

  static const info = '$apiPrefix/info';
  static const pair = '$apiPrefix/pair';
  static const ping = '$apiPrefix/ping';
  static const pull = '$apiPrefix/sync/pull';
  static const push = '$apiPrefix/sync/push';
}

/// Machine-readable error codes. Every error body is
/// `{"error": "<code>", "message": "<human text>"}`.
class ErrorCodes {
  const ErrorCodes._();

  static const badRequest = 'bad_request';
  static const invalidPairingToken = 'invalid_pairing_token';
  static const unauthorized = 'unauthorized';
  static const staleRevision = 'stale_revision';
}

class ServerInfo {
  const ServerInfo({
    required this.serverId,
    required this.serverName,
    this.version = protocolVersion,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> j) => ServerInfo(
    serverId: _str(j, 'serverId'),
    serverName: _str(j, 'serverName'),
    version: _int(j, 'protocolVersion'),
  );

  final String serverId;
  final String serverName;
  final int version;

  Map<String, dynamic> toJson() => {
    'serverId': serverId,
    'serverName': serverName,
    'protocolVersion': version,
  };
}

class PairRequest {
  const PairRequest({
    required this.pairingToken,
    required this.deviceId,
    required this.deviceName,
  });

  factory PairRequest.fromJson(Map<String, dynamic> j) => PairRequest(
    pairingToken: _str(j, 'pairingToken'),
    deviceId: _str(j, 'deviceId'),
    deviceName: _str(j, 'deviceName'),
  );

  final String pairingToken;
  final String deviceId;
  final String deviceName;

  Map<String, dynamic> toJson() => {
    'pairingToken': pairingToken,
    'deviceId': deviceId,
    'deviceName': deviceName,
  };
}

class PairResponse {
  const PairResponse({required this.deviceSecret, required this.server});

  factory PairResponse.fromJson(Map<String, dynamic> j) => PairResponse(
    deviceSecret: _str(j, 'deviceSecret'),
    server: ServerInfo.fromJson(_map(j, 'server')),
  );

  final String deviceSecret;
  final ServerInfo server;

  Map<String, dynamic> toJson() => {
    'deviceSecret': deviceSecret,
    'server': server.toJson(),
  };
}

class PingResponse {
  const PingResponse({required this.server, required this.revision});

  factory PingResponse.fromJson(Map<String, dynamic> j) => PingResponse(
    server: ServerInfo.fromJson(_map(j, 'server')),
    revision: _int(j, 'revision'),
  );

  final ServerInfo server;
  final int revision;

  Map<String, dynamic> toJson() => {
    'server': server.toJson(),
    'revision': revision,
  };
}

String _str(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v is! String || v.isEmpty) {
    throw FormatException('Missing or invalid "$key"');
  }
  return v;
}

int _int(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v is! num) throw FormatException('Missing or invalid "$key"');
  return v.toInt();
}

Map<String, dynamic> _map(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v is! Map<String, dynamic>) {
    throw FormatException('Missing or invalid "$key"');
  }
  return v;
}
