import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../doc.dart';
import '../repository.dart';

/// The phones this hub has paired with. Only a SHA-256 of each device secret
/// is kept, so the file never holds anything that grants access.
/// OFFLINE_FIRST_SYNC_PLAYBOOK.md §5.1.
class DeviceRegistry {
  DeviceRegistry(this.repo, {int Function()? clock, Random? random})
    : _clock = clock ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch),
      _random = random ?? Random.secure();

  static const _secretBytes = 32;

  final SyncRepository repo;
  final int Function() _clock;
  final Random _random;

  List<PairedDevice> get devices => repo.data.sync.devices;

  List<PairedDevice> get active => [
    for (final d in devices)
      if (!d.revoked) d,
  ];

  static String hash(String secret) =>
      sha256.convert(utf8.encode(secret)).toString();

  /// Pairs a device and returns its new secret. Pairing again with the same
  /// device id replaces the record, so a phone can always come back by
  /// scanning a fresh code.
  Future<String> addDevice({
    required String deviceId,
    required String name,
  }) async {
    final secret = base64Url
        .encode(List<int>.generate(_secretBytes, (_) => _random.nextInt(256)))
        .replaceAll('=', '');
    final device = PairedDevice(
      deviceId: deviceId,
      name: name,
      secretHash: hash(secret),
      pairedAt: _clock(),
    );
    await repo.write(
      repo.data.copyWith(
        sync: repo.data.sync.copyWith(
          devices: [
            for (final d in devices)
              if (d.deviceId != deviceId) d,
            device,
          ],
        ),
      ),
    );
    return secret;
  }

  PairedDevice? authenticate(String secret) {
    final digest = hash(secret);
    for (final d in devices) {
      if (d.secretHash == digest && !d.revoked) return d;
    }
    return null;
  }

  Future<void> revoke(String deviceId) {
    if (!devices.any((d) => d.deviceId == deviceId)) return Future.value();
    return repo.write(
      repo.data.copyWith(
        sync: repo.data.sync.copyWith(
          devices: [
            for (final d in devices)
              if (d.deviceId == deviceId) d.copyWith(revoked: true) else d,
          ],
        ),
      ),
    );
  }

  /// The device list with this device's last-sync time brought up to date.
  /// Returned rather than written, so the push that completes a sync can store
  /// it together with the data in a single save.
  List<PairedDevice> markedSynced(String deviceId) => [
    for (final d in devices)
      if (d.deviceId == deviceId) d.copyWith(lastSyncAt: _clock()) else d,
  ];
}
