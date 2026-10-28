import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../doc.dart';
import '../protocol/pairing_qr.dart';
import '../protocol/protocol.dart';
import '../repository.dart';
import 'hub_api.dart';

/// Pairs this phone with a PC from a scanned QR code.
/// OFFLINE_FIRST_SYNC_PLAYBOOK.md §5.2 and §5.3.
class PairingService {
  PairingService({
    required this.repo,
    this.client,
    String Function()? newId,
    int Function()? clock,
    Future<String> Function()? deviceName,
  }) : _newId = newId ?? (() => const Uuid().v4()),
       _clock = clock ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch),
       _deviceName = deviceName ?? defaultDeviceName;

  final SyncRepository repo;

  /// Injectable for tests, which talk to the hub's handler without a socket.
  final http.Client? client;
  final String Function() _newId;
  final int Function() _clock;
  final Future<String> Function() _deviceName;

  HubPairing? get current => repo.data.sync.pairing;

  /// Pairs, and leaves the document ready for the sync that follows. Meeting a
  /// hub we have never synced with resets the revision and marks everything
  /// dirty, so this phone's whole history is pushed to it.
  Future<HubPairing> pair(PairingCode code) async {
    final deviceId = await _deviceId();
    final api = HubApi(baseUrl: code.baseUrl, client: client);
    final response = await api.pair(
      PairRequest(
        pairingToken: code.pairingToken,
        deviceId: deviceId,
        deviceName: await _deviceName(),
      ),
    );
    final server = response.server;
    if (server.serverId != code.serverId) throw const DifferentHub();

    final now = _clock();
    final known = repo.data.sync.lastServerId;
    final sameHub = known != null && known == server.serverId;
    final existing = current;

    final pairing = HubPairing(
      serverId: server.serverId,
      serverName: server.serverName,
      host: code.host,
      port: code.port,
      deviceSecret: response.deviceSecret,
      pairedAt: now,
      // Same PC as last time (new address, or back after a revoke): keep what
      // we have already seen. A different PC starts from scratch.
      lastSyncedRevision: sameHub && existing?.serverId == server.serverId
          ? existing!.lastSyncedRevision
          : 0,
      lastSyncAt: sameHub ? existing?.lastSyncAt : null,
    );

    final base = sameHub ? repo.data : SyncRepository.allDirty(repo.data, now);
    await repo.write(
      base.copyWith(
        sync: base.sync.copyWith(
          deviceId: deviceId,
          lastServerId: server.serverId,
          pairing: pairing,
        ),
      ),
    );
    return pairing;
  }

  /// Forgets the PC. The data stays on the phone.
  Future<void> unpair() => repo.write(
    repo.data.copyWith(sync: repo.data.sync.copyWith(clearPairing: true)),
  );

  Future<String> _deviceId() async {
    final existing = repo.data.sync.deviceId;
    if (existing != null) return existing;
    final id = _newId();
    await repo.write(
      repo.data.copyWith(sync: repo.data.sync.copyWith(deviceId: id)),
    );
    return id;
  }
}

/// What the PC calls this phone in its paired list.
Future<String> defaultDeviceName() async {
  try {
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      final name = '${info.manufacturer} ${info.model}'.trim();
      return name.isEmpty ? 'Phone' : name;
    }
    if (Platform.isIOS) {
      final info = await DeviceInfoPlugin().iosInfo;
      return info.name.isEmpty ? 'iPhone' : info.name;
    }
    return Platform.localHostname;
  } catch (_) {
    return 'Phone';
  }
}
