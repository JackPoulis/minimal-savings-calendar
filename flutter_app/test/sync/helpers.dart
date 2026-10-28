import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:savings/model.dart';
import 'package:savings/store.dart';
import 'package:savings/sync/client/pairing_service.dart';
import 'package:savings/sync/client/sync_client.dart';
import 'package:savings/sync/protocol/pairing_qr.dart';
import 'package:savings/sync/protocol/protocol.dart';
import 'package:savings/sync/repository.dart';
import 'package:savings/sync/server/device_registry.dart';
import 'package:savings/sync/server/hub_identity.dart';
import 'package:savings/sync/server/hub_server.dart';
import 'package:savings/sync/server/hub_sync_service.dart';
import 'package:savings/sync/server/pairing_tokens.dart';

/// A store that keeps the file in memory as text, so every save goes through
/// the real JSON round trip the app relies on.
class MemoryStore extends Store {
  MemoryStore([SavingsData? initial])
      : _text = initial == null ? null : jsonEncode(initial.toJson());

  String? _text;
  int saves = 0;

  String? get text => _text;

  @override
  Future<SavingsData> load() async => _text == null
      ? SavingsData.defaults()
      : SavingsData.fromJson(jsonDecode(_text!) as Map<String, dynamic>);

  @override
  Future<void> save(SavingsData data) async {
    _text = jsonEncode(data.toJson());
    saves++;
  }
}

/// A clock that never repeats, so "edited during the sync" is always visible.
class Ticks {
  Ticks([this.now = 1700000000000]);

  int now;

  int call() => ++now;
}

Entry sampleEntry({
  required String id,
  String type = 'in',
  String title = 'Salary',
  double amount = 1500,
  String date = '2026-01-05',
}) =>
    Entry(id: id, type: type, title: title, amount: amount, date: date);

SavingsData sampleData({
  List<Entry> entries = const [],
  double goal = 12000,
  int loanYears = 5,
  String endDate = '2026-06-30',
}) =>
    SavingsData(
      startDate: '2026-01-01',
      endDate: endDate,
      goal: goal,
      loanAmount: 0,
      apr: 0,
      loanYears: loanYears,
      entries: entries,
    );

/// A hub with its own in-memory file. [listen] binds a real loopback socket;
/// route tests leave it off and call [server].handler directly.
class TestHub {
  TestHub._({
    required this.store,
    required this.repo,
    required this.identity,
    required this.registry,
    required this.tokens,
    required this.sync,
    required this.server,
    required this.info,
    required this.ticks,
  });

  static Future<TestHub> create({
    SavingsData? data,
    String serverId = 'hub-0001',
    bool listen = true,
    Ticks? ticks,
  }) async {
    final clock = ticks ?? Ticks();
    final store = MemoryStore(data ?? sampleData());
    final repo = SyncRepository(store: store, isHub: true, clock: clock.call);
    await repo.load();
    final identity = HubIdentity(
      repo,
      newId: () => serverId,
      clock: clock.call,
    );
    final info = await identity.ensure();
    final registry = DeviceRegistry(
      repo,
      clock: clock.call,
      random: Random(7),
    );
    final tokens = PairingTokens(random: Random(11));
    final sync = HubSyncService(
      repo: repo,
      registry: registry,
      clock: clock.call,
    );
    final events = <HubEvent>[];
    final server = HubServer(
      info: info,
      registry: registry,
      tokens: tokens,
      sync: sync,
      onEvent: events.add,
    );
    final hub = TestHub._(
      store: store,
      repo: repo,
      identity: identity,
      registry: registry,
      tokens: tokens,
      sync: sync,
      server: server,
      info: info,
      ticks: clock,
    );
    hub.events = events;
    if (listen) hub.port = await server.start(address: '127.0.0.1', port: 0);
    return hub;
  }

  final MemoryStore store;
  final SyncRepository repo;
  final HubIdentity identity;
  final DeviceRegistry registry;
  final PairingTokens tokens;
  final HubSyncService sync;
  final HubServer server;
  final ServerInfo info;
  final Ticks ticks;

  late List<HubEvent> events;
  int port = 0;

  SavingsData get data => repo.data;

  /// What the sync window would put in the QR code.
  PairingCode code() => PairingCode(
        host: '127.0.0.1',
        port: port,
        serverId: info.serverId,
        pairingToken: tokens.issue(),
      );

  Future<void> dispose() => server.stop();
}

/// A phone with its own in-memory file.
class TestPhone {
  TestPhone._({
    required this.store,
    required this.repo,
    required this.pairing,
    required this.ticks,
    required this.httpClient,
  });

  static Future<TestPhone> create({SavingsData? data, Ticks? ticks}) async {
    final clock = ticks ?? Ticks(1800000000000);
    final store = MemoryStore(data ?? sampleData());
    final repo = SyncRepository(store: store, isHub: false, clock: clock.call);
    await repo.load();
    final httpClient = http.Client();
    return TestPhone._(
      store: store,
      repo: repo,
      pairing: PairingService(
        repo: repo,
        client: httpClient,
        newId: () => 'phone-0001',
        clock: clock.call,
        deviceName: () async => 'Test Phone',
      ),
      ticks: clock,
      httpClient: httpClient,
    );
  }

  final MemoryStore store;
  final SyncRepository repo;
  final PairingService pairing;
  final Ticks ticks;
  final http.Client httpClient;

  SavingsData get data => repo.data;

  SyncClient client({Future<void> Function()? beforePush}) => SyncClient(
        repo: repo,
        client: httpClient,
        clock: ticks.call,
        beforePush: beforePush,
      );

  void dispose() => httpClient.close();
}

/// The live entries of a document, by id, as plain values — the shape both
/// devices must agree on after a sync.
Map<String, Map<String, Object?>> entriesByValue(SavingsData data) => {
      for (final e in data.entries)
        e.id: {
          'type': e.type,
          'title': e.title,
          'amount': e.amount,
          'date': e.date,
          'deleted': e.deleted,
        },
    };

Map<String, Object?> settingsByValue(SavingsData data) => {
      'startDate': data.startDate,
      'endDate': data.endDate,
      'goal': data.goal,
      'loanAmount': data.loanAmount,
      'apr': data.apr,
      'loanYears': data.loanYears,
    };

/// Edits an entry the way the UI does: through the repository, with the values
/// the editor opened with as the base.
Future<void> editEntry(
  SyncRepository repo,
  String id, {
  String? title,
  double? amount,
  String? date,
  String? type,
}) async {
  final stored = repo.data.entries.firstWhere((e) => e.id == id);
  await repo.saveEntry(
    stored.copyWith(title: title, amount: amount, date: date, type: type),
    base: stored,
  );
}
