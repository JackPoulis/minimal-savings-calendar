import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:savings/sync/protocol/protocol.dart';
import 'package:savings/sync/server/device_registry.dart';
import 'package:savings/sync/server/pairing_tokens.dart';
import 'package:shelf/shelf.dart';

import 'helpers.dart';

/// The routes driven straight through the shelf handler — no socket involved.
/// Playbook §10.5.

void main() {
  late TestHub hub;

  setUp(() async {
    hub = await TestHub.create(
      data: sampleData(entries: [sampleEntry(id: 'h1')]),
      listen: false,
    );
  });

  Future<Response> call(
    String method,
    String path, {
    Object? body,
    String? secret,
  }) =>
      Future.value(hub.server.handler(Request(
        method,
        Uri.parse('http://pc.local$path'),
        headers: {
          'content-type': 'application/json',
          if (secret != null) 'authorization': 'Bearer $secret',
        },
        body: body == null ? null : jsonEncode(body),
      )));

  Future<Map<String, dynamic>> bodyOf(Response response) async =>
      jsonDecode(await response.readAsString()) as Map<String, dynamic>;

  Future<String> pairedSecret() async {
    final response = await call('POST', Paths.pair, body: {
      'pairingToken': hub.tokens.issue(),
      'deviceId': 'phone-0001',
      'deviceName': 'Test Phone',
    });
    return (await bodyOf(response))['deviceSecret'] as String;
  }

  group('public routes', () {
    test('info needs no bearer', () async {
      final response = await call('GET', Paths.info);
      expect(response.statusCode, 200);
      final body = await bodyOf(response);
      expect(body['serverId'], 'hub-0001');
      expect(body['protocolVersion'], protocolVersion);
    });

    test('pairing hands out a secret and records the device', () async {
      final secret = await pairedSecret();
      expect(secret, isNotEmpty);
      final device = hub.data.sync.devices.single;
      expect(device.deviceId, 'phone-0001');
      expect(device.name, 'Test Phone');
      // Only the hash is stored.
      expect(hub.store.text, isNot(contains(secret)));
      expect(device.secretHash, DeviceRegistry.hash(secret));
    });

    test('a pairing token works once', () async {
      final token = hub.tokens.issue();
      final first = await call('POST', Paths.pair, body: {
        'pairingToken': token,
        'deviceId': 'phone-0001',
        'deviceName': 'Phone',
      });
      expect(first.statusCode, 200);

      final second = await call('POST', Paths.pair, body: {
        'pairingToken': token,
        'deviceId': 'phone-0002',
        'deviceName': 'Other',
      });
      expect(second.statusCode, 403);
      expect((await bodyOf(second))['error'], ErrorCodes.invalidPairingToken);
    });

    test('a malformed pair request does not burn the token', () async {
      final token = hub.tokens.issue();
      final bad = await call('POST', Paths.pair, body: {'deviceId': 'x'});
      expect(bad.statusCode, 400);
      expect(hub.tokens.current, token);

      final good = await call('POST', Paths.pair, body: {
        'pairingToken': token,
        'deviceId': 'phone-0001',
        'deviceName': 'Phone',
      });
      expect(good.statusCode, 200);
    });

    test('pairing the same phone again replaces its secret', () async {
      final first = await pairedSecret();
      final second = await pairedSecret();
      expect(second, isNot(first));
      expect(hub.data.sync.devices, hasLength(1));
      expect(hub.registry.authenticate(first), isNull);
      expect(hub.registry.authenticate(second), isNotNull);
    });
  });

  group('authentication', () {
    test('no bearer is unauthorized', () async {
      final response = await call('GET', Paths.ping);
      expect(response.statusCode, 401);
      expect((await bodyOf(response))['error'], ErrorCodes.unauthorized);
    });

    test('an unknown bearer is unauthorized', () async {
      final response = await call('GET', Paths.ping, secret: 'made-up');
      expect(response.statusCode, 401);
    });

    test('a revoked device is unauthorized', () async {
      final secret = await pairedSecret();
      expect((await call('GET', Paths.ping, secret: secret)).statusCode, 200);
      await hub.registry.revoke('phone-0001');
      expect((await call('GET', Paths.ping, secret: secret)).statusCode, 401);
    });

    test('ping reports the current revision', () async {
      final secret = await pairedSecret();
      final body = await bodyOf(await call('GET', Paths.ping, secret: secret));
      expect(body['revision'], hub.data.sync.revision);
      expect((body['server'] as Map)['serverId'], 'hub-0001');
    });
  });

  group('sync routes', () {
    test('pull returns the hub snapshot', () async {
      final secret = await pairedSecret();
      final body = await bodyOf(
        await call('POST', Paths.pull, body: {'since': 0}, secret: secret),
      );
      expect(body['revision'], isA<int>());
      expect((body['records'] as List), isNotEmpty);
    });

    test('a malformed pull is a bad request', () async {
      final secret = await pairedSecret();
      final response =
          await call('POST', Paths.pull, body: {'since': 'soon'}, secret: secret);
      expect(response.statusCode, 400);
      expect((await bodyOf(response))['error'], ErrorCodes.badRequest);
    });

    test('a stale push answers 409 with the hub revision', () async {
      final secret = await pairedSecret();
      final response = await call(
        'POST',
        Paths.push,
        body: {'baseRevision': 0, 'changes': []},
        secret: secret,
      );
      expect(response.statusCode, 409);
      final body = await bodyOf(response);
      expect(body['error'], ErrorCodes.staleRevision);
      expect(body['revision'], hub.data.sync.revision);
    });

    test('a malformed push is a bad request and applies nothing', () async {
      final secret = await pairedSecret();
      final before = hub.store.text;
      final response = await call(
        'POST',
        Paths.push,
        body: {
          'baseRevision': hub.data.sync.revision,
          'changes': [
            {
              'type': 'entry',
              'id': 'h1',
              'createdAt': 1,
              'fields': {
                'amount': {'value': 'lots', 'at': 1},
              },
            },
          ],
        },
        secret: secret,
      );
      expect(response.statusCode, 400);
      expect(hub.store.text, before);
    });

    test('a body that is not JSON is a bad request', () async {
      final secret = await pairedSecret();
      final actual = await hub.server.handler(Request(
        'POST',
        Uri.parse('http://pc.local${Paths.pull}'),
        headers: {'authorization': 'Bearer $secret'},
        body: 'not json at all',
      ));
      expect(actual.statusCode, 400);
    });
  });

  group('pairing tokens', () {
    test('a token expires', () {
      var now = 0;
      final tokens = PairingTokens(clock: () => now, random: Random(1));
      final token = tokens.issue();
      now += PairingTokens.lifetime.inMilliseconds - 1;
      expect(tokens.current, token);
      now += 2;
      expect(tokens.current, isNull);
      expect(tokens.consume(token), isFalse);
    });

    test('issuing a new token invalidates the old one', () {
      final tokens = PairingTokens(random: Random(2));
      final first = tokens.issue();
      final second = tokens.issue();
      expect(tokens.consume(first), isFalse);
      expect(tokens.consume(second), isTrue);
      expect(tokens.consume(second), isFalse);
    });
  });
}
