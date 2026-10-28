import 'package:flutter_test/flutter_test.dart';
import 'package:savings/sync/client/hub_api.dart';
import 'package:savings/sync/protocol/pairing_qr.dart';
import 'package:savings/sync/protocol/protocol.dart';

import 'helpers.dart';

void main() {
  group('the QR payload', () {
    test('survives a round trip', () {
      const code = PairingCode(
        host: '192.168.1.40',
        port: 8765,
        serverId: 'hub-0001',
        pairingToken: 'abc123',
      );
      final decoded = PairingCode.decode(code.encode());
      expect(decoded.host, code.host);
      expect(decoded.port, code.port);
      expect(decoded.serverId, code.serverId);
      expect(decoded.pairingToken, code.pairingToken);
      expect(decoded.baseUrl, 'http://192.168.1.40:8765');
    });

    test('rejects anything that is not one of our codes', () {
      for (final raw in [
        'https://example.com',
        '{}',
        '{"v":1,"host":"","port":8765,"serverId":"a","pairingToken":"b"}',
        '{"v":1,"host":"h","port":0,"serverId":"a","pairingToken":"b"}',
        '{"v":1,"host":"h","port":99999,"serverId":"a","pairingToken":"b"}',
        '{"v":1,"host":"h","port":"8765","serverId":"a","pairingToken":"b"}',
        '{"v":1,"host":"h","port":1,"serverId":"a"}',
      ]) {
        expect(
          () => PairingCode.decode(raw),
          throwsA(isA<FormatException>()),
          reason: raw,
        );
      }
    });

    test('rejects another protocol version', () {
      final raw =
          '{"v":${protocolVersion + 1},"host":"h","port":1,"serverId":"a",'
          '"pairingToken":"b"}';
      expect(() => PairingCode.decode(raw), throwsA(isA<FormatException>()));
    });
  });

  group('pairing', () {
    test('a hub whose identity does not match the code is refused', () async {
      final hub = await TestHub.create();
      addTearDown(hub.dispose);
      final phone = await TestPhone.create();
      addTearDown(phone.dispose);

      final real = hub.code();
      final lying = PairingCode(
        host: real.host,
        port: real.port,
        serverId: 'some-other-pc',
        pairingToken: real.pairingToken,
      );
      await expectLater(
        phone.pairing.pair(lying),
        throwsA(isA<DifferentHub>()),
      );
    });

    test('pairing stores the address, the secret and the device id', () async {
      final hub = await TestHub.create();
      addTearDown(hub.dispose);
      final phone = await TestPhone.create();
      addTearDown(phone.dispose);

      final pairing = await phone.pairing.pair(hub.code());
      expect(pairing.serverId, hub.info.serverId);
      expect(pairing.host, '127.0.0.1');
      expect(pairing.port, hub.port);
      expect(pairing.deviceSecret, isNotEmpty);
      expect(phone.data.sync.deviceId, 'phone-0001');
      expect(phone.data.sync.lastServerId, hub.info.serverId);
    });

    test('meeting a hub for the first time marks everything dirty', () async {
      final hub = await TestHub.create();
      addTearDown(hub.dispose);
      final phone = await TestPhone.create(
        data: sampleData(entries: [sampleEntry(id: 'p1')]),
      );
      addTearDown(phone.dispose);

      await phone.pairing.pair(hub.code());
      expect(phone.data.settingsMeta.dirty, isNotEmpty);
      expect(phone.data.entries.single.meta.dirty, isNotEmpty);
    });

    test('unpairing forgets the PC but keeps the data', () async {
      final hub = await TestHub.create();
      addTearDown(hub.dispose);
      final phone = await TestPhone.create(
        data: sampleData(entries: [sampleEntry(id: 'p1')]),
      );
      addTearDown(phone.dispose);

      await phone.pairing.pair(hub.code());
      await phone.pairing.unpair();
      expect(phone.pairing.current, isNull);
      expect(phone.data.entries, hasLength(1));
    });

    test('an expired code is refused with a readable message', () async {
      final hub = await TestHub.create();
      addTearDown(hub.dispose);
      final phone = await TestPhone.create();
      addTearDown(phone.dispose);

      final code = hub.code();
      hub.tokens.clear();
      await expectLater(
        phone.pairing.pair(code),
        throwsA(
          isA<Rejected>().having(
            (e) => e.message,
            'message',
            contains('new QR code'),
          ),
        ),
      );
    });
  });
}
