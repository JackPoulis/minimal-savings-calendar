import 'package:flutter_test/flutter_test.dart';
import 'package:savings/model.dart';
import 'package:savings/sync/merge/merge_models.dart';
import 'package:savings/sync/repository.dart';

import 'helpers.dart';

/// The single write choke point: what gets stamped, and what does not.
/// Playbook §3.3 and §10.8.

void main() {
  late MemoryStore store;
  late Ticks ticks;

  Future<SyncRepository> open({
    required bool isHub,
    SavingsData? data,
  }) async {
    ticks = Ticks();
    store = MemoryStore(data ?? sampleData(entries: [sampleEntry(id: 'e1')]));
    final repo = SyncRepository(
      store: store,
      isHub: isHub,
      clock: ticks.call,
    );
    await repo.load();
    return repo;
  }

  group('on a client', () {
    test('only the fields that changed are marked dirty', () async {
      final repo = await open(isHub: false);
      await editEntry(repo, 'e1', title: 'Renamed');
      final entry = repo.data.entries.single;
      expect(entry.meta.dirty, {'title'});
      expect(entry.meta.at.keys, {'title'});
      expect(entry.meta.rev, isEmpty); // revisions are the hub's business
      expect(repo.data.sync.revision, 0);
    });

    test('an edit that changes nothing does nothing at all', () async {
      final repo = await open(isHub: false);
      final saves = store.saves;
      final stored = repo.data.entries.single;
      await repo.saveEntry(stored, base: stored);
      expect(store.saves, saves);
      expect(repo.data.entries.single.meta.dirty, isEmpty);
    });

    test('a new entry is dirty in full', () async {
      final repo = await open(isHub: false);
      await repo.saveEntry(sampleEntry(id: 'new', title: 'Bonus'));
      final entry = repo.data.entries.firstWhere((e) => e.id == 'new');
      expect(entry.meta.dirty, entryKind.fields.toSet());
      expect(entry.meta.createdAt, greaterThan(0));
    });

    test('deleting keeps the row as a tombstone', () async {
      final repo = await open(isHub: false);
      await repo.deleteEntry('e1');
      expect(repo.data.entries, hasLength(1));
      expect(repo.data.entries.single.deleted, isTrue);
      expect(repo.data.liveEntries, isEmpty);
      expect(repo.data.entries.single.meta.dirty, {deletedField});
    });

    test('deleting twice is a no-op the second time', () async {
      final repo = await open(isHub: false);
      await repo.deleteEntry('e1');
      final saves = store.saves;
      await repo.deleteEntry('e1');
      expect(store.saves, saves);
    });

    test('markAllDirty marks every field of every record', () async {
      final repo = await open(isHub: false);
      await repo.markAllDirty();
      expect(repo.data.settingsMeta.dirty, settingsKind.fields.toSet());
      expect(repo.data.entries.single.meta.dirty, entryKind.fields.toSet());
    });
  });

  group('on the hub', () {
    test('each write bumps the revision once and stamps it', () async {
      final repo = await open(isHub: true);
      await editEntry(repo, 'e1', title: 'One', amount: 10);
      expect(repo.data.sync.revision, 1);
      final entry = repo.data.entries.single;
      expect(entry.meta.rev, {'title': 1, 'amount': 1});
      expect(entry.meta.dirty, isEmpty); // the hub has no dirty set

      await editEntry(repo, 'e1', title: 'Two');
      expect(repo.data.sync.revision, 2);
      expect(repo.data.entries.single.meta.rev['title'], 2);
      expect(repo.data.entries.single.meta.rev['amount'], 1);
    });
  });

  group('the editor-safety rule', () {
    test('a stale editor only writes the field the user touched', () async {
      final repo = await open(isHub: false);
      final opened = repo.data.entries.single;

      // A sync arrives while the editor is open and changes the amount.
      await repo.write(repo.data.copyWith(entries: [
        opened.copyWith(amount: 999),
      ]));

      // The user had only retyped the title.
      await repo.saveEntry(opened.copyWith(title: 'Renamed'), base: opened);

      final entry = repo.data.entries.single;
      expect(entry.title, 'Renamed');
      expect(entry.amount, 999, reason: 'the synced amount must survive');
      expect(entry.meta.dirty, {'title'});
    });

    test('settings behave the same way', () async {
      final repo = await open(isHub: false);
      final opened = repo.data;
      await repo.write(repo.data.copyWith(loanYears: 9));
      await repo.updateSettings(opened.copyWith(goal: 20000), base: opened);
      expect(repo.data.goal, 20000);
      expect(repo.data.loanYears, 9);
      expect(repo.data.settingsMeta.dirty, {'goal'});
    });
  });

  group('the stored file', () {
    test('an older data.json without any sync keys still loads', () async {
      final repo = await open(
        isHub: false,
        data: sampleData(entries: [sampleEntry(id: 'e1')]),
      );
      expect(store.text, isNot(contains('"meta"')));
      expect(store.text, isNot(contains('"sync"')));
      expect(repo.data.entries.single.meta.isEmpty, isTrue);
      expect(repo.data.liveEntries, hasLength(1));
    });

    test('whole amounts stay whole in the file', () async {
      final repo = await open(isHub: false);
      await editEntry(repo, 'e1', amount: 1750);
      expect(store.text, contains('"amount":1750'));
      expect(store.text, isNot(contains('1750.0')));
    });
  });
}
