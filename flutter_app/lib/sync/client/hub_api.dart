import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../protocol/protocol.dart';
import '../protocol/sync_dtos.dart';

/// Everything that can go wrong, with a message already written for the
/// person holding the phone. OFFLINE_FIRST_SYNC_PLAYBOOK.md §4.
sealed class SyncException implements Exception {
  const SyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Timeouts, refused connections, wrong network, firewall — one error, because
/// the phone cannot tell them apart and the fix is the same list of checks.
class HubUnreachable extends SyncException {
  const HubUnreachable([
    super.message =
        'Could not reach the PC. Check that its sync window is '
        'open, that both devices are on the same Wi-Fi, and that Windows '
        'Firewall is allowing the app on private networks.',
  ]);
}

class Unauthorized extends SyncException {
  const Unauthorized([
    super.message =
        'This phone is no longer paired with that PC. Scan the QR code again.',
  ]);
}

/// The hub changed between our pull and our push; pull again and retry.
class StaleRevision extends SyncException {
  const StaleRevision(this.revision) : super('The PC changed while syncing.');

  final int revision;
}

/// The hub refused the request and said why.
class Rejected extends SyncException {
  const Rejected(super.message);
}

/// The other side sent something this version cannot read.
class BadData extends SyncException {
  const BadData([
    super.message =
        'The PC sent data this app cannot read. Both devices '
        'probably need the same version of the app.',
  ]);
}

class NotPaired extends SyncException {
  const NotPaired([super.message = 'Scan the QR code on the PC to sync.']);
}

class DifferentHub extends SyncException {
  const DifferentHub([
    super.message =
        'That PC has a different identity than the QR code said. '
        'Show a new QR code and scan it again.',
  ]);
}

class SyncCancelled extends SyncException {
  const SyncCancelled([super.message = 'Sync cancelled. Nothing changed.']);
}

/// Conflicts were found but nobody was there to resolve them.
class ConflictsPending extends SyncException {
  const ConflictsPending(this.count)
    : super('Conflicts found. Nothing changed.');

  final int count;
}

/// The data was edited on this phone while the sync was running.
class SyncInterrupted extends SyncException {
  const SyncInterrupted([
    super.message =
        'The data changed while syncing. Nothing was lost — '
        'scan again to finish.',
  ]);
}

class RetriesExhausted extends SyncException {
  const RetriesExhausted([
    super.message = 'The PC kept changing while syncing. Try again.',
  ]);
}

/// The HTTP side of the client. Knows nothing about merging.
class HubApi {
  HubApi({
    required this.baseUrl,
    this.secret,
    http.Client? client,
    this.timeout = const Duration(seconds: 6),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String? secret;
  final Duration timeout;
  final http.Client _client;

  HubApi withSecret(String secret) => HubApi(
    baseUrl: baseUrl,
    secret: secret,
    client: _client,
    timeout: timeout,
  );

  void close() => _client.close();

  Future<ServerInfo> info() async =>
      _parse(await _get(Paths.info), ServerInfo.fromJson);

  Future<PairResponse> pair(PairRequest request) async =>
      _parse(await _post(Paths.pair, request.toJson()), PairResponse.fromJson);

  Future<PingResponse> ping() async =>
      _parse(await _get(Paths.ping), PingResponse.fromJson);

  Future<PullResponse> pull(int since) async => _parse(
    await _post(Paths.pull, PullRequest(since).toJson()),
    PullResponse.fromJson,
  );

  Future<PushResponse> push(PushRequest request) async =>
      _parse(await _post(Paths.push, request.toJson()), PushResponse.fromJson);

  // -------------------------------------------------------------------- plumbing

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    if (secret != null) 'authorization': 'Bearer $secret',
  };

  Future<http.Response> _get(String path) =>
      _send(() => _client.get(Uri.parse('$baseUrl$path'), headers: _headers));

  Future<http.Response> _post(String path, Map<String, dynamic> body) => _send(
    () => _client.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    ),
  );

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw const HubUnreachable();
    } on SocketException {
      throw const HubUnreachable();
    } on http.ClientException {
      throw const HubUnreachable();
    } on HandshakeException {
      throw const HubUnreachable();
    }
  }

  T _parse<T>(http.Response response, T Function(Map<String, dynamic>) build) {
    final body = _decode(response);
    if (response.statusCode == 401) throw const Unauthorized();
    if (response.statusCode == 409 &&
        body['error'] == ErrorCodes.staleRevision) {
      final revision = body['revision'];
      throw StaleRevision(revision is num ? revision.toInt() : 0);
    }
    if (response.statusCode >= 400) {
      final message = body['message'];
      throw Rejected(
        message is String && message.isNotEmpty
            ? message
            : 'The PC refused the request (${response.statusCode}).',
      );
    }
    try {
      return build(body);
    } on FormatException {
      throw const BadData();
    } on TypeError {
      throw const BadData();
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {
      // Falls through to the empty map: handled as bad data below.
    }
    if (response.statusCode >= 400) return const {};
    throw const BadData();
  }
}
