import 'package:flutter_test/flutter_test.dart';
import 'package:savings/sync/merge/merge.dart';
import 'package:savings/sync/merge/resolve.dart';
import 'package:savings/sync/merge/merge_models.dart';

import 'merge_test.dart' show local, remote, planFor;

/// Playbook §8. The point of every delete/edit answer is that both devices end
/// up holding exactly the same record, so each test checks that directly.

const _entry = {
  'type': 'in',
  'title': 'Salary',
  'amount': 1500.0,
  'date': '2026-01-05',
  deletedField: false,
};

/// Replays a resolved plan on both devices: the phone takes what it adopts,
/// the PC takes what it is pushed.
({Map<String, Object?> phone, Map<String, Object?> pc}) replay({
  required RecordPlan plan,
  required Map<String, Object?> localValues,
  required Map<String, Object?> remoteValues,
}) =>
    (
      phone: {...localValues, ...plan.adopt},
      pc: {
        ...remoteValues,
        for (final f in plan.push) f: localValues[f],
      },
    );

RecordPlan resolveOne({
  required Map<String, Object?> localValues,
  required Set<String> dirty,
  required Map<String, Object?> remoteValues,
  required Map<String, int> revs,
  required ConflictChoice choice,
  int since = 5,
}) {
  final plan = planSync(
    locals: [local(values: localValues, dirty: dirty)],
    remotes: [remote(values: remoteValues, revs: revs)],
    since: since,
  );
  final conflict = planFor(plan, 'e1')!.conflicts.single;
  final resolved = resolveConflicts(
    plan: plan,
    choices: {conflict.key: choice},
    since: since,
  );
  return planFor(resolved, 'e1')!;
}

void main() {
  group('field conflicts', () {
    test('keeping the phone value pushes it', () {
      final record = resolveOne(
        localValues: {..._entry, 'amount': 1700.0},
        dirty: {'amount'},
        remoteValues: {..._entry, 'amount': 1600.0},
        revs: {'amount': 6},
        choice: ConflictChoice.keepPhone,
      );
      expect(record.push, {'amount'});
      expect(record.adopt, isEmpty);
      expect(record.conflicts, isEmpty);
      expect(record.resolvedConflicts, 1);
      expect(record.clearsDirty, isTrue);

      final after = replay(
        plan: record,
        localValues: {..._entry, 'amount': 1700.0},
        remoteValues: {..._entry, 'amount': 1600.0},
      );
      expect(after.phone, after.pc);
      expect(after.phone['amount'], 1700.0);
    });

    test("keeping the PC value adopts it", () {
      final record = resolveOne(
        localValues: {..._entry, 'amount': 1700.0},
        dirty: {'amount'},
        remoteValues: {..._entry, 'amount': 1600.0},
        revs: {'amount': 6},
        choice: ConflictChoice.keepPc,
      );
      expect(record.adopt, {'amount': 1600.0});
      expect(record.push, isEmpty);

      final after = replay(
        plan: record,
        localValues: {..._entry, 'amount': 1700.0},
        remoteValues: {..._entry, 'amount': 1600.0},
      );
      expect(after.phone, after.pc);
      expect(after.phone['amount'], 1600.0);
    });
  });

  group('delete versus edit', () {
    // The phone deleted it; the PC changed its title and amount.
    final phoneDeleted = {..._entry, deletedField: true};
    final pcEdited = {..._entry, 'title': 'Pay', 'amount': 1600.0};

    test('phone deleted, PC edited, keep the record: the PC edit survives', () {
      final record = resolveOne(
        localValues: phoneDeleted,
        dirty: {deletedField},
        remoteValues: pcEdited,
        revs: {'title': 6, 'amount': 6},
        choice: ConflictChoice.keepRecord,
      );
      final after = replay(
        plan: record,
        localValues: phoneDeleted,
        remoteValues: pcEdited,
      );
      expect(after.phone, after.pc);
      expect(after.phone[deletedField], false);
      expect(after.phone['title'], 'Pay');
      expect(after.phone['amount'], 1600.0);
    });

    test('phone deleted, PC edited, delete it: the record goes everywhere', () {
      final record = resolveOne(
        localValues: phoneDeleted,
        dirty: {deletedField},
        remoteValues: pcEdited,
        revs: {'title': 6, 'amount': 6},
        choice: ConflictChoice.deleteRecord,
      );
      final after = replay(
        plan: record,
        localValues: phoneDeleted,
        remoteValues: pcEdited,
      );
      expect(after.phone, after.pc);
      expect(after.phone[deletedField], true);
    });

    test('PC deleted, phone edited, keep the record: the phone edit survives',
        () {
      final phoneEdited = {..._entry, 'title': 'Mine', 'amount': 1800.0};
      final pcDeleted = {..._entry, deletedField: true};
      final record = resolveOne(
        localValues: phoneEdited,
        dirty: {'title', 'amount'},
        remoteValues: pcDeleted,
        revs: {deletedField: 6},
        choice: ConflictChoice.keepRecord,
      );
      final after = replay(
        plan: record,
        localValues: phoneEdited,
        remoteValues: pcDeleted,
      );
      expect(after.phone, after.pc);
      expect(after.phone[deletedField], false);
      expect(after.phone['title'], 'Mine');
      expect(after.phone['amount'], 1800.0);
    });

    test('PC deleted, phone edited, delete it: the phone edit is discarded',
        () {
      final phoneEdited = {..._entry, 'title': 'Mine', 'amount': 1800.0};
      final pcDeleted = {..._entry, deletedField: true};
      final record = resolveOne(
        localValues: phoneEdited,
        dirty: {'title', 'amount'},
        remoteValues: pcDeleted,
        revs: {deletedField: 6},
        choice: ConflictChoice.deleteRecord,
      );
      final after = replay(
        plan: record,
        localValues: phoneEdited,
        remoteValues: pcDeleted,
      );
      expect(after.phone, after.pc);
      expect(after.phone[deletedField], true);
      expect(after.phone['title'], 'Salary');
    });

    test('both sides edited the same field: the side that kept it wins', () {
      // The phone deleted the record and had also changed the title; the PC
      // changed the same title. Keeping the record must take the PC's title,
      // because deleting expressed no opinion about field values.
      final record = resolveOne(
        localValues: {..._entry, 'title': 'Mine', deletedField: true},
        dirty: {deletedField, 'title'},
        remoteValues: {..._entry, 'title': 'Theirs'},
        revs: {'title': 6},
        choice: ConflictChoice.keepRecord,
      );
      final after = replay(
        plan: record,
        localValues: {..._entry, 'title': 'Mine', deletedField: true},
        remoteValues: {..._entry, 'title': 'Theirs'},
      );
      expect(after.phone, after.pc);
      expect(after.phone['title'], 'Theirs');
    });
  });

  group('bad answers', () {
    SyncPlan conflicted() => planSync(
          locals: [local(values: {..._entry, 'amount': 1700.0}, dirty: {'amount'})],
          remotes: [
            remote(values: {..._entry, 'amount': 1600.0}, revs: {'amount': 6}),
          ],
          since: 5,
        );

    test('a missing choice throws', () {
      expect(
        () => resolveConflicts(plan: conflicted(), choices: const {}, since: 5),
        throwsArgumentError,
      );
    });

    test('a choice that does not fit the conflict throws', () {
      expect(
        () => resolveConflicts(
          plan: conflicted(),
          choices: const {'e1/amount': ConflictChoice.deleteRecord},
          since: 5,
        ),
        throwsArgumentError,
      );
    });
  });
}
