import 'package:flutter_test/flutter_test.dart';
import 'package:savings/model.dart';
import 'package:savings/sync/client/hub_api.dart';
import 'package:savings/sync/merge/merge_models.dart';

import 'helpers.dart';

/// The phone and the PC talking to each other for real, each with its own
/// in-memory data file, over a loopback socket. Playbook §10.7.

Future<Map<String, ConflictChoice>?> _keepPhone(List<Conflict> c) async =>
    {for (final x in c) x.key: x.phoneSide};

Future<Map<String, ConflictChoice>?> _keepPc(List<Conflict> c) async =>
    {for (final x in c) x.key: x.pcSide};

Future<Map<String, ConflictChoice>?> _cancel(List<Conflict> c) async => null;

void main() {
  late TestHub hub;
  late TestPhone phone;

  Future<void> start({
    List<String> hubEntries = const ['h1'],
    List<String> phoneEntries = const ['p1'],
  }) async {
    hub = await TestHub.create(
      data: sampleData(
        entries: [
          for (final id in hubEntries)
            sampleEntry(id: id, title: 'Hub $id', amount: 1000),
        ],
      ),
    );
    phone = await TestPhone.create(
      data: sampleData(
        entries: [
          for (final id in phoneEntries)
            sampleEntry(id: id, title: 'Phone $id', amount: 2000),
        ],
      ),
    );
  }

  tearDown(() async {
    phone.dispose();
    await hub.dispose();
  });

  test('the first sync leaves both sides with the union', () async {
    await start();
    await phone.pairing.pair(hub.code());
    final summary = await phone.client().run();

    expect(entriesByValue(hub.data).keys, {'h1', 'p1'});
    expect(entriesByValue(phone.data), entriesByValue(hub.data));
    expect(settingsByValue(phone.data), settingsByValue(hub.data));
    expect(summary.pulled, 1);
    expect(summary.pushed, 1);
    expect(summary.nothingChanged, isFalse);
  });

  test('syncing again changes nothing and does not bump the revision',
      () async {
    await start();
    await phone.pairing.pair(hub.code());
    await phone.client().run();
    final revision = hub.data.sync.revision;

    final again = await phone.client().run();
    expect(again.nothingChanged, isTrue);
    expect(hub.data.sync.revision, revision);
    expect(entriesByValue(phone.data), entriesByValue(hub.data));
  });

  test('edits to different fields of one record auto-merge', () async {
    await start();
    await phone.pairing.pair(hub.code());
    await phone.client().run();

    await editEntry(hub.repo, 'h1', amount: 1234);
    await editEntry(phone.repo, 'h1', title: 'Renamed on the phone');

    final summary = await phone.client().run();
    expect(summary.autoMerged, 1);
    expect(phone.data.entries.firstWhere((e) => e.id == 'h1').amount, 1234);
    expect(
      hub.data.entries.firstWhere((e) => e.id == 'h1').title,
      'Renamed on the phone',
    );
    expect(entriesByValue(phone.data), entriesByValue(hub.data));
  });

  test('the same field edited on both sides converges on the phone answer',
      () async {
    await start();
    await phone.pairing.pair(hub.code());
    await phone.client().run();

    await editEntry(hub.repo, 'h1', amount: 1111);
    await editEntry(phone.repo, 'h1', amount: 2222);

    final summary = await phone.client().run(resolver: _keepPhone);
    expect(summary.resolved, 1);
    expect(entriesByValue(phone.data), entriesByValue(hub.data));
    expect(phone.data.entries.firstWhere((e) => e.id == 'h1').amount, 2222);
  });

  test('the same field edited on both sides converges on the PC answer',
      () async {
    await start();
    await phone.pairing.pair(hub.code());
    await phone.client().run();

    await editEntry(hub.repo, 'h1', amount: 1111);
    await editEntry(phone.repo, 'h1', amount: 2222);

    await phone.client().run(resolver: _keepPc);
    expect(entriesByValue(phone.data), entriesByValue(hub.data));
    expect(phone.data.entries.firstWhere((e) => e.id == 'h1').amount, 1111);
  });

  test('a deletion on the phone reaches the PC', () async {
    await start();
    await phone.pairing.pair(hub.code());
    await phone.client().run();

    await phone.repo.deleteEntry('h1');
    await phone.client().run();

    expect(hub.data.entries.firstWhere((e) => e.id == 'h1').deleted, isTrue);
    expect(hub.data.liveEntries.map((e) => e.id), ['p1']);
    expect(entriesByValue(phone.data), entriesByValue(hub.data));
  });

  test('delete on the phone versus edit on the PC, keeping the record',
      () async {
    await start();
    await phone.pairing.pair(hub.code());
    await phone.client().run();

    await editEntry(hub.repo, 'h1', title: 'Still needed');
    await phone.repo.deleteEntry('h1');

    final summary = await phone.client().run(resolver: _keepPc);
    expect(summary.resolved, 1);
    expect(phone.data.entries.firstWhere((e) => e.id == 'h1').deleted, isFalse);
    expect(
      phone.data.entries.firstWhere((e) => e.id == 'h1').title,
      'Still needed',
    );
    expect(entriesByValue(phone.data), entriesByValue(hub.data));
  });

  test('cancelling in the conflict screen changes nothing anywhere', () async {
    await start();
    await phone.pairing.pair(hub.code());
    await phone.client().run();

    await editEntry(hub.repo, 'h1', amount: 1111);
    await editEntry(phone.repo, 'h1', amount: 2222);
    final hubBefore = hub.store.text;
    final phoneBefore = phone.store.text;

    await expectLater(
      phone.client().run(resolver: _cancel),
      throwsA(isA<SyncCancelled>()),
    );
    expect(hub.store.text, hubBefore);
    expect(phone.store.text, phoneBefore);

    // The same conflict is still waiting next time.
    final summary = await phone.client().run(resolver: _keepPhone);
    expect(summary.resolved, 1);
  });

  test('conflicts with no resolver stop the sync without changing anything',
      () async {
    await start();
    await phone.pairing.pair(hub.code());
    await phone.client().run();

    await editEntry(hub.repo, 'h1', amount: 1111);
    await editEntry(phone.repo, 'h1', amount: 2222);
    final phoneBefore = phone.store.text;

    await expectLater(
      phone.client().run(),
      throwsA(isA<ConflictsPending>()),
    );
    expect(phone.store.text, phoneBefore);
  });

  test('a PC edit between the merge and the push is retried and converges',
      () async {
    await start();
    await phone.pairing.pair(hub.code());
    await phone.client().run();

    await editEntry(phone.repo, 'p1', title: 'Phone wins');
    var interfered = false;
    final client = phone.client(beforePush: () async {
      if (interfered) return;
      interfered = true;
      await editEntry(hub.repo, 'h1', title: 'Snuck in');
    });

    final summary = await client.run();
    expect(interfered, isTrue);
    expect(
      phone.data.entries.firstWhere((e) => e.id == 'h1').title,
      'Snuck in',
    );
    expect(hub.data.entries.firstWhere((e) => e.id == 'p1').title, 'Phone wins');
    expect(entriesByValue(phone.data), entriesByValue(hub.data));
    expect(summary.pulled, greaterThan(0));
  });

  test('a PC that keeps changing fails cleanly after three attempts', () async {
    await start();
    await phone.pairing.pair(hub.code());
    await phone.client().run();

    var attempts = 0;
    final client = phone.client(beforePush: () async {
      attempts++;
      await editEntry(hub.repo, 'h1', amount: 1000 + attempts.toDouble());
    });

    await expectLater(client.run(), throwsA(isA<RetriesExhausted>()));
    expect(attempts, 3);
  });

  test('an edit on the phone during the sync is noticed, and nothing is lost',
      () async {
    await start();
    await phone.pairing.pair(hub.code());
    await phone.client().run();

    await editEntry(hub.repo, 'h1', title: 'From the PC');
    final client = phone.client(beforePush: () async {
      await editEntry(phone.repo, 'h1', title: 'Typed mid-sync');
    });

    await expectLater(client.run(), throwsA(isA<SyncInterrupted>()));
    expect(
      phone.data.entries.firstWhere((e) => e.id == 'h1').title,
      'Typed mid-sync',
    );

    // Finishing the job afterwards loses nothing from either side.
    await phone.client().run(resolver: _keepPhone);
    expect(entriesByValue(phone.data), entriesByValue(hub.data));
    expect(
      hub.data.entries.firstWhere((e) => e.id == 'h1').title,
      'Typed mid-sync',
    );
  });

  test('settings edited on both sides conflict per field', () async {
    await start();
    await phone.pairing.pair(hub.code());
    await phone.client().run();

    await hub.repo.updateSettings(hub.data.copyWith(goal: 15000, apr: 3.5));
    await phone.repo.updateSettings(
      phone.data.copyWith(goal: 16000, loanYears: 7),
    );

    final summary = await phone.client().run(resolver: _keepPhone);
    expect(summary.resolved, 1); // goal only; apr and years auto-merge
    expect(phone.data.goal, 16000);
    expect(phone.data.apr, 3.5);
    expect(hub.data.loanYears, 7);
    expect(settingsByValue(phone.data), settingsByValue(hub.data));
  });

  test('a phone that has never seen this PC pushes everything it has',
      () async {
    await start();
    await phone.pairing.pair(hub.code());
    await phone.client().run();

    // A different PC: new identity, empty of our data.
    final other = await TestHub.create(serverId: 'hub-0002');
    addTearDown(other.dispose);

    await phone.pairing.pair(other.code());
    expect(phone.data.sync.pairing!.lastSyncedRevision, 0);

    await phone.client().run(resolver: _keepPhone);
    expect(entriesByValue(other.data).keys, containsAll({'h1', 'p1'}));
    expect(entriesByValue(phone.data), entriesByValue(other.data));
  });

  test('re-pairing with the same PC keeps what it has already seen', () async {
    await start();
    await phone.pairing.pair(hub.code());
    await phone.client().run();
    final seen = phone.data.sync.pairing!.lastSyncedRevision;
    expect(seen, greaterThan(0));

    await phone.pairing.pair(hub.code());
    expect(phone.data.sync.pairing!.lastSyncedRevision, seen);

    final summary = await phone.client().run();
    expect(summary.nothingChanged, isTrue);
  });

  test('a revoked phone is told to scan again', () async {
    await start();
    await phone.pairing.pair(hub.code());
    await phone.client().run();

    await hub.registry.revoke('phone-0001');
    await expectLater(phone.client().run(), throwsA(isA<Unauthorized>()));
  });

  test('an unreachable PC fails with one clear message', () async {
    await start();
    await phone.pairing.pair(hub.code());
    await hub.server.stop();

    await expectLater(phone.client().run(), throwsA(isA<HubUnreachable>()));
  });

  test('monthly forecasts sync both ways, including a delete', () async {
    await start();
    await hub.repo.saveForecast(
        const Forecast(id: 'hf', type: 'out', title: 'Rent', amount: 800));
    await phone.repo.saveForecast(
        const Forecast(id: 'pf', type: 'in', title: 'Salary', amount: 2000));
    await phone.pairing.pair(hub.code());
    await phone.client().run();

    for (final d in [hub.data, phone.data]) {
      expect(d.liveForecasts.map((f) => f.id).toSet(), {'hf', 'pf'});
    }

    await phone.repo.deleteForecast('hf');
    await phone.client().run();
    expect(hub.data.liveForecasts.map((f) => f.id), ['pf']);
    expect(hub.data.forecasts.length, 2); // tombstone kept
  });

  test('syncing without pairing asks for a scan', () async {
    await start();
    await expectLater(phone.client().run(), throwsA(isA<NotPaired>()));
  });
}
