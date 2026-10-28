import 'package:flutter_test/flutter_test.dart';
import 'package:savings/sync/merge/merge.dart';
import 'package:savings/sync/merge/merge_models.dart';

/// The playbook's merge table (§7), one test per row.

const _entry = {
  'type': 'in',
  'title': 'Salary',
  'amount': 1500.0,
  'date': '2026-01-05',
  deletedField: false,
};

LocalRecord local({
  String id = 'e1',
  Map<String, Object?> values = _entry,
  Set<String> dirty = const {},
  int version = 10,
  RecordKind kind = entryKind,
}) =>
    LocalRecord(
      kind: kind,
      id: id,
      createdAt: 1,
      version: version,
      fields: {
        for (final f in kind.fields) f: FieldState(values[f], 5),
      },
      dirty: dirty,
    );

RemoteRecord remote({
  String id = 'e1',
  Map<String, Object?> values = _entry,
  Map<String, int> revs = const {},
  RecordKind kind = entryKind,
}) =>
    RemoteRecord(
      kind: kind,
      id: id,
      createdAt: 1,
      fields: {
        for (final f in kind.fields)
          f: RemoteField(values[f], 7, revs[f] ?? 0),
      },
    );

RecordPlan? planFor(SyncPlan plan, String id) {
  for (final r in plan.records) {
    if (r.id == id) return r;
  }
  return null;
}

void main() {
  group('planSync', () {
    test('a record only the hub has is inserted whole', () {
      final plan = planSync(
        locals: const [],
        remotes: [remote(revs: {'title': 4})],
        since: 2,
      );
      final record = planFor(plan, 'e1')!;
      expect(record.isNew, isTrue);
      expect(record.adopt['title'], 'Salary');
      expect(record.adopt[deletedField], false);
      expect(record.push, isEmpty);
      expect(plan.pulled, 1);
    });

    test('a record only the phone has is pushed in full', () {
      final plan = planSync(
        locals: [local(dirty: {...entryKind.fields})],
        remotes: const [],
        since: 0,
      );
      final record = planFor(plan, 'e1')!;
      expect(record.push, entryKind.fields.toSet());
      expect(record.clearsDirty, isTrue);
      expect(plan.pushed, 1);
    });

    test('a record untouched on both sides produces no plan at all', () {
      final plan = planSync(
        locals: [local()],
        remotes: [remote()],
        since: 5,
      );
      expect(plan.records, isEmpty);
      expect(plan.isEmpty, isTrue);
    });

    test('a field changed only on the hub is adopted', () {
      final plan = planSync(
        locals: [local()],
        remotes: [
          remote(values: {..._entry, 'amount': 1600.0}, revs: {'amount': 6}),
        ],
        since: 5,
      );
      final record = planFor(plan, 'e1')!;
      expect(record.adopt, {'amount': 1600.0});
      expect(record.push, isEmpty);
    });

    test('a field changed only on the phone is pushed', () {
      final plan = planSync(
        locals: [local(dirty: {'title'})],
        remotes: [remote(revs: {'amount': 3})],
        since: 5,
      );
      final record = planFor(plan, 'e1')!;
      expect(record.push, {'title'});
      expect(record.adopt, isEmpty);
    });

    test('the same field changed to different values is a conflict', () {
      final plan = planSync(
        locals: [local(values: {..._entry, 'amount': 1700.0}, dirty: {'amount'})],
        remotes: [
          remote(values: {..._entry, 'amount': 1600.0}, revs: {'amount': 6}),
        ],
        since: 5,
      );
      final record = planFor(plan, 'e1')!;
      expect(record.conflicts, hasLength(1));
      final conflict = record.conflicts.single as FieldConflict;
      expect(conflict.field, 'amount');
      expect(conflict.key, 'e1/amount');
      expect(conflict.local.value, 1700.0);
      expect(conflict.remote.value, 1600.0);
      // Until it is resolved the field is neither adopted nor pushed.
      expect(record.adopt, isEmpty);
      expect(record.push, isEmpty);
    });

    test('the same field changed to the same value is not a conflict', () {
      final plan = planSync(
        locals: [local(values: {..._entry, 'amount': 1600.0}, dirty: {'amount'})],
        remotes: [
          remote(values: {..._entry, 'amount': 1600.0}, revs: {'amount': 6}),
        ],
        since: 5,
      );
      expect(plan.hasConflicts, isFalse);
      // Nothing to move either way, but the dirty mark still has to go.
      final record = planFor(plan, 'e1')!;
      expect(record.adopt, isEmpty);
      expect(record.push, isEmpty);
      expect(record.clearsDirty, isTrue);
    });

    test('different fields on each side auto-merge', () {
      final plan = planSync(
        locals: [local(values: {..._entry, 'title': 'Pay'}, dirty: {'title'})],
        remotes: [
          remote(values: {..._entry, 'amount': 1600.0}, revs: {'amount': 6}),
        ],
        since: 5,
      );
      final record = planFor(plan, 'e1')!;
      expect(record.adopt, {'amount': 1600.0});
      expect(record.push, {'title'});
      expect(record.autoMerged, isTrue);
      expect(plan.autoMerged, 1);
      expect(plan.hasConflicts, isFalse);
    });

    test('a deletion on the hub propagates when the phone did not touch it',
        () {
      final plan = planSync(
        locals: [local()],
        remotes: [
          remote(
            values: {..._entry, deletedField: true},
            revs: {deletedField: 6},
          ),
        ],
        since: 5,
      );
      final record = planFor(plan, 'e1')!;
      expect(record.adopt, {deletedField: true});
      expect(record.conflicts, isEmpty);
    });

    test('deleted on the hub while edited on the phone is a conflict', () {
      final plan = planSync(
        locals: [local(values: {..._entry, 'title': 'Pay'}, dirty: {'title'})],
        remotes: [
          remote(
            values: {..._entry, deletedField: true},
            revs: {deletedField: 6},
          ),
        ],
        since: 5,
      );
      final conflict =
          planFor(plan, 'e1')!.conflicts.single as DeleteEditConflict;
      expect(conflict.deletedOnPhone, isFalse);
      expect(conflict.key, 'e1/record');
      expect(conflict.phoneSide, ConflictChoice.keepRecord);
      expect(conflict.pcSide, ConflictChoice.deleteRecord);
    });

    test('deleted on the phone while edited on the hub is a conflict', () {
      final plan = planSync(
        locals: [
          local(
            values: {..._entry, deletedField: true},
            dirty: {deletedField},
          ),
        ],
        remotes: [
          remote(values: {..._entry, 'title': 'Pay'}, revs: {'title': 6}),
        ],
        since: 5,
      );
      final conflict =
          planFor(plan, 'e1')!.conflicts.single as DeleteEditConflict;
      expect(conflict.deletedOnPhone, isTrue);
      expect(conflict.phoneSide, ConflictChoice.deleteRecord);
    });

    test('an old tombstone on the hub raises no conflict', () {
      final plan = planSync(
        locals: [local(values: {..._entry, 'title': 'Pay'}, dirty: {'title'})],
        // Deleted long ago (rev 2), below our since — not "just" deleted.
        remotes: [
          remote(
            values: {..._entry, deletedField: true},
            revs: {deletedField: 2, 'amount': 6},
          ),
        ],
        since: 5,
      );
      final record = planFor(plan, 'e1')!;
      expect(record.conflicts, isEmpty);
      expect(record.push, {'title'});
    });

    test('deleted on both sides converges on the hub without a conflict', () {
      final plan = planSync(
        locals: [
          local(
            values: {..._entry, deletedField: true, 'title': 'Mine'},
            dirty: {deletedField, 'title'},
          ),
        ],
        remotes: [
          remote(
            values: {..._entry, deletedField: true, 'title': 'Theirs'},
            revs: {deletedField: 6, 'title': 6},
          ),
        ],
        since: 5,
      );
      final record = planFor(plan, 'e1')!;
      expect(record.conflicts, isEmpty);
      expect(record.adopt, {'title': 'Theirs'});
      expect(record.clearsDirty, isTrue);
    });

    test('a record the hub deleted before this phone ever saw it is inserted',
        () {
      final plan = planSync(
        locals: const [],
        remotes: [
          remote(
            values: {..._entry, deletedField: true},
            revs: {deletedField: 6},
          ),
        ],
        since: 5,
      );
      final record = planFor(plan, 'e1')!;
      expect(record.isNew, isTrue);
      expect(record.adopt[deletedField], true);
    });

    test('settings conflict per field and never delete-vs-edit', () {
      const settings = {
        'startDate': '2026-01-01',
        'endDate': '2026-06-01',
        'goal': 12000.0,
        'loanAmount': 0.0,
        'apr': 0.0,
        'loanYears': 5,
      };
      final plan = planSync(
        locals: [
          local(
            kind: settingsKind,
            id: settingsId,
            values: {...settings, 'goal': 13000.0, 'apr': 4.5},
            dirty: {'goal', 'apr'},
          ),
        ],
        remotes: [
          remote(
            kind: settingsKind,
            id: settingsId,
            values: {...settings, 'goal': 14000.0, 'loanYears': 7},
            revs: {'goal': 6, 'loanYears': 6},
          ),
        ],
        since: 5,
      );
      final record = planFor(plan, settingsId)!;
      expect(record.conflicts.single.key, '$settingsId/goal');
      expect(record.adopt, {'loanYears': 7});
      expect(record.push, {'apr'});
    });

    test('a dirty record the hub did not report is still pushed', () {
      final plan = planSync(
        locals: [local(dirty: {'amount'}), local(id: 'e2')],
        remotes: const [],
        since: 5,
      );
      expect(plan.records, hasLength(1));
      expect(plan.records.single.id, 'e1');
    });
  });
}
