import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../doc.dart';
import '../protocol/protocol.dart';
import '../protocol/sync_dtos.dart';
import 'device_registry.dart';
import 'hub_sync_service.dart';
import 'pairing_tokens.dart';

enum HubEventKind { paired, served, applied, rejected }

/// What the sync window shows the user while a phone is talking to us.
class HubEvent {
  const HubEvent(this.kind, {this.deviceName = '', this.records = 0});

  final HubEventKind kind;
  final String deviceName;
  final int records;
}

/// The hub's HTTP surface. [handler] is a plain shelf handler so the routes
/// can be tested without binding a socket; [start] only puts it on one.
///
/// OFFLINE_FIRST_SYNC_PLAYBOOK.md §4 and §5.1.
class HubServer {
  HubServer({
    required this.info,
    required this.registry,
    required this.tokens,
    required this.sync,
    this.onEvent,
  });

  final ServerInfo info;
  final DeviceRegistry registry;
  final PairingTokens tokens;
  final HubSyncService sync;
  final void Function(HubEvent)? onEvent;

  static const _deviceKey = 'sync.device';

  HttpServer? _socket;

  int? get port => _socket?.port;
  bool get running => _socket != null;

  /// Binds [port], falling back to any free port if it is taken. Returns the
  /// port actually in use — the QR code carries it.
  Future<int> start({
    String address = '0.0.0.0',
    int port = defaultPort,
  }) async {
    if (_socket != null) return _socket!.port;
    try {
      _socket = await shelf_io.serve(handler, address, port);
    } on SocketException {
      _socket = await shelf_io.serve(handler, address, 0);
    }
    return _socket!.port;
  }

  Future<void> stop() async {
    final socket = _socket;
    _socket = null;
    await socket?.close(force: true);
  }

  Handler get handler {
    final public = Router()
      ..get(Paths.info, _info)
      ..post(Paths.pair, _pair);

    final private = Router()
      ..get(Paths.ping, _ping)
      ..post(Paths.pull, _pull)
      ..post(Paths.push, _push);

    final authed = const Pipeline()
        .addMiddleware(_authenticate)
        .addHandler(private.call);

    return Cascade().add(public.call).add(authed).handler;
  }

  // -------------------------------------------------------------------- routes

  Response _info(Request request) => _json(info.toJson());

  Future<Response> _pair(Request request) async {
    final PairRequest pairing;
    try {
      pairing = PairRequest.fromJson(await _body(request));
    } on FormatException catch (e) {
      // A malformed request must not burn the token.
      return _error(400, ErrorCodes.badRequest, e.message);
    }
    if (!tokens.consume(pairing.pairingToken)) {
      return _error(
        403,
        ErrorCodes.invalidPairingToken,
        'That pairing code has expired. Show a new QR code on the PC.',
      );
    }
    final secret = await registry.addDevice(
      deviceId: pairing.deviceId,
      name: pairing.deviceName,
    );
    onEvent?.call(
      HubEvent(HubEventKind.paired, deviceName: pairing.deviceName),
    );
    return _json(PairResponse(deviceSecret: secret, server: info).toJson());
  }

  Response _ping(Request request) =>
      _json(PingResponse(server: info, revision: sync.repo.revision).toJson());

  Future<Response> _pull(Request request) async {
    final PullRequest pull;
    try {
      pull = PullRequest.fromJson(await _body(request));
    } on FormatException catch (e) {
      return _error(400, ErrorCodes.badRequest, e.message);
    }
    final response = sync.pull(pull.since);
    onEvent?.call(
      HubEvent(
        HubEventKind.served,
        deviceName: _device(request).name,
        records: response.records.length,
      ),
    );
    return _json(response.toJson());
  }

  Future<Response> _push(Request request) async {
    final PushRequest push;
    try {
      push = PushRequest.fromJson(await _body(request));
    } on FormatException catch (e) {
      return _error(400, ErrorCodes.badRequest, e.message);
    }
    final device = _device(request);
    final outcome = await sync.push(device.deviceId, push);
    switch (outcome) {
      case PushApplied():
        onEvent?.call(
          HubEvent(
            HubEventKind.applied,
            deviceName: device.name,
            records: outcome.records,
          ),
        );
        return _json(PushResponse(outcome.revision).toJson());
      case PushStale():
        return Response(
          409,
          body: jsonEncode({
            'error': ErrorCodes.staleRevision,
            'message': 'This PC changed while the phone was syncing.',
            'revision': outcome.revision,
          }),
          headers: _jsonHeaders,
        );
      case PushInvalid():
        onEvent?.call(HubEvent(HubEventKind.rejected, deviceName: device.name));
        return _error(400, ErrorCodes.badRequest, outcome.message);
    }
  }

  // ---------------------------------------------------------------- middleware

  Middleware get _authenticate =>
      (Handler inner) => (Request request) {
        final header = request.headers['authorization'] ?? '';
        final secret = header.toLowerCase().startsWith('bearer ')
            ? header.substring(7).trim()
            : '';
        final device = secret.isEmpty ? null : registry.authenticate(secret);
        if (device == null) {
          return Future.value(
            _error(
              401,
              ErrorCodes.unauthorized,
              'This phone is not paired with this PC any more. '
              'Scan the QR code again.',
            ),
          );
        }
        return inner(request.change(context: {_deviceKey: device}));
      };

  PairedDevice _device(Request request) =>
      request.context[_deviceKey] as PairedDevice;

  // -------------------------------------------------------------------- helpers

  static const _jsonHeaders = {'content-type': 'application/json'};

  Future<Map<String, dynamic>> _body(Request request) async {
    final text = await request.readAsString();
    final Object? parsed;
    try {
      parsed = jsonDecode(text);
    } catch (_) {
      throw const FormatException('The request body is not JSON');
    }
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException('The request body must be an object');
    }
    return parsed;
  }

  Response _json(Map<String, dynamic> body) =>
      Response.ok(jsonEncode(body), headers: _jsonHeaders);

  Response _error(int status, String code, String message) => Response(
    status,
    body: jsonEncode({'error': code, 'message': message}),
    headers: _jsonHeaders,
  );
}
