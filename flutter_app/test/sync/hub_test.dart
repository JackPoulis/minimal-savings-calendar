import 'package:flutter_test/flutter_test.dart';
import 'package:savings/sync/codec.dart';
import 'package:savings/sync/merge/merge_models.dart';
import 'package:savings/sync/protocol/sync_dtos.dart';
import 'package:savings/sync/server/hub_sync_service.dart';

import 'helpers.dart';

/// The hub's pull and push, with no network in the way. Playbook §10.4.

WireRecord entryChange(
  String id,
  Map<String, Object?> fields, {
  int createdAt = 1,
}) =>
    WireRecord(
      type: entryKind.wire,
      id: id,
      createdAt: createdAt,
      fields: {
        for (final e in fields.entries)
          e.key: WireField(value: e.value, at: 5),
      },
    );

Map<String, Object?> wholeEntry({
  String title = 'Pushed',
  double amount = 500,
  String date = '2026-02-02',
  String type = 'in',
  bool deleted = false,
}) =>
    {
      'type': type,
      'title': title,
      'amount': amount,
      'date': date,
      deletedField: deleted,
    };

void main() {
  late TestHub hub;

  setUp(() async {
    hub = await TestHub.create(
      data: sampleData(entries: [sampleEntry(id: 'h1')]),
      listen: false,
    );
  });

  group('pull', () {
    test('returns everything on a first pull, with revisions', () {
      final response = hub.sync.pull(0);
      expect(response.revision, 1);
      expect(
        response.records.map((r) => r.id).toSet(),
        {settingsId, 'h1'},
      );
      final entry = response.records.firstWhere((r) => r.id == 'h1');
      // A pull carries every field of a changed record, each with its rev.
      expect(entry.fields.keys.toSet(), entryKind.fields.toSet());
      expect(entry.fields['title']!.rev, 1);
    });

    test('returns only what changed after that', () async {
      await editEntry(hub.repo, 'h1', title: 'Changed');
      final response = hub.sync.pull(1);
      expect(response.records.map((r) => r.id), ['h1']);
      expect(response.revision, 2);
    });

    test('returns nothing when the hub has not moved', () {
      expect(hub.sync.pull(1).records, isEmpty);
    });
  });

  group('push', () {
    test('a stale base revision applies nothing', () async {
      final before = hub.store.text;
      final outcome = await hub.sync.push(
        'phone-0001',
        PushRequest(
          baseRevision: 0,
          changes: [entryChange('h1', {'title': 'Should not land'})],
        ),
      );
      expect(outcome, isA<PushStale>());
      expect((outcome as PushStale).revision, 1);
      expect(hub.store.text, before);
    });

    test('one revision bump however many records a push carries', () async {
      final outcome = await hub.sync.push(
        'phone-0001',
        PushRequest(baseRevision: 1, changes: [
          entryChange('n1', wholeEntry(title: 'One')),
          entryChange('n2', wholeEntry(title: 'Two')),
          entryChange('h1', {'title': 'Renamed'}),
        ]),
      );
      expect((outcome as PushApplied).revision, 2);
      expect(hub.data.sync.revision, 2);
      for (final entry in hub.data.entries) {
        expect(entry.meta.rev['title'], entry.id == 'h1' ? 2 : 2);
      }
    });

    test('values equal to what the hub holds change nothing', () async {
      final stored = hub.data.entries.first;
      final outcome = await hub.sync.push(
        'phone-0001',
        PushRequest(baseRevision: 1, changes: [
          entryChange('h1', {'title': stored.title, 'amount': stored.amount}),
        ]),
      );
      expect((outcome as PushApplied).changed, isFalse);
      expect(outcome.revision, 1);
      expect(hub.data.sync.revision, 1);
    });

    test('an empty push still records when that phone last synced', () async {
      await hub.registry.addDevice(deviceId: 'phone-0001', name: 'Phone');
      final outcome = await hub.sync.push(
        'phone-0001',
        const PushRequest(baseRevision: 1, changes: []),
      );
      expect((outcome as PushApplied).changed, isFalse);
      expect(
        hub.data.sync.devices.single.lastSyncAt,
        isNotNull,
      );
    });

    test('a new record missing a field is rejected and nothing is applied',
        () async {
      final before = hub.store.text;
      final outcome = await hub.sync.push(
        'phone-0001',
        PushRequest(baseRevision: 1, changes: [
          entryChange('n1', {'title': 'Half a record'}),
          entryChange('h1', {'title': 'Would have landed'}),
        ]),
      );
      expect(outcome, isA<PushInvalid>());
      expect(hub.store.text, before);
    });

    test('a wrongly typed value is rejected and nothing is applied', () async {
      final before = hub.store.text;
      final outcome = await hub.sync.push(
        'phone-0001',
        PushRequest(baseRevision: 1, changes: [
          entryChange('h1', {'amount': 'not a number'}),
        ]),
      );
      expect(outcome, isA<PushInvalid>());
      expect(hub.store.text, before);
    });

    test('an unknown field name is rejected', () async {
      final outcome = await hub.sync.push(
        'phone-0001',
        PushRequest(baseRevision: 1, changes: [
          entryChange('h1', {'colour': 'blue'}),
        ]),
      );
      expect(outcome, isA<PushInvalid>());
    });

    test('an unknown record type is rejected', () async {
      final outcome = await hub.sync.push(
        'phone-0001',
        PushRequest(baseRevision: 1, changes: [
          const WireRecord(
            type: 'invoice',
            id: 'x',
            createdAt: 1,
            fields: {},
          ),
        ]),
      );
      expect(outcome, isA<PushInvalid>());
    });

    test('settings pushes merge field by field', () async {
      final outcome = await hub.sync.push(
        'phone-0001',
        PushRequest(baseRevision: 1, changes: [
          WireRecord(
            type: settingsKind.wire,
            id: settingsId,
            createdAt: 1,
            fields: {'goal': const WireField(value: 19000, at: 9)},
          ),
        ]),
      );
      expect((outcome as PushApplied).changed, isTrue);
      expect(hub.data.goal, 19000);
      expect(hub.data.endDate, sampleData().endDate); // untouched
      expect(hub.data.settingsMeta.rev['goal'], 2);
      expect(hub.data.settingsMeta.at['goal'], 9);
    });

    test('a tombstone arrives as an ordinary field change', () async {
      await hub.sync.push(
        'phone-0001',
        PushRequest(baseRevision: 1, changes: [
          entryChange('h1', const {deletedField: true}),
        ]),
      );
      expect(hub.data.entries.single.deleted, isTrue);
      expect(hub.data.liveEntries, isEmpty);
    });

    test('applying the same push twice is harmless', () async {
      final change = PushRequest(baseRevision: 1, changes: [
        entryChange('n1', wholeEntry(title: 'Once')),
      ]);
      final first = await hub.sync.push('phone-0001', change) as PushApplied;
      expect(first.revision, 2);

      final again = await hub.sync.push(
        'phone-0001',
        PushRequest(baseRevision: 2, changes: change.changes),
      ) as PushApplied;
      expect(again.changed, isFalse);
      expect(again.revision, 2);
      expect(hub.data.entries.where((e) => e.id == 'n1'), hasLength(1));
    });
  });

  test('values are validated the same way in both directions', () {
    expect(() => parseWireValue(entryKind, 'amount', '12'),
        throwsA(isA<FormatException>()));
    expect(() => parseWireValue(entryKind, 'type', 'sideways'),
        throwsA(isA<FormatException>()));
    expect(() => parseWireValue(settingsKind, 'loanYears', 5.5),
        throwsA(isA<FormatException>()));
    expect(parseWireValue(entryKind, 'amount', 12), 12.0);
    expect(parseWireValue(settingsKind, 'loanYears', 5), 5);
  });
}
