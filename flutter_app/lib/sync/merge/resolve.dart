/// `resolveConflicts`: turns the user's answers into a conflict-free plan.
///
/// OFFLINE_FIRST_SYNC_PLAYBOOK.md §8. After either answer to a delete/edit
/// conflict both devices end up with identical records.
library;

import 'merge_models.dart';

/// Every conflict in [plan] must have a valid answer in [choices], keyed by
/// [Conflict.key], or this throws.
SyncPlan resolveConflicts({
  required SyncPlan plan,
  required Map<String, ConflictChoice> choices,
  required int since,
}) => SyncPlan([
  for (final record in plan.records)
    if (record.conflicts.isEmpty)
      record
    else
      _resolveRecord(record, choices, since),
]);

RecordPlan _resolveRecord(
  RecordPlan record,
  Map<String, ConflictChoice> choices,
  int since,
) {
  final adopt = {...record.adopt};
  final push = {...record.push};

  for (final conflict in record.conflicts) {
    final choice = choices[conflict.key];
    if (choice == null) {
      throw ArgumentError('No choice given for conflict ${conflict.key}');
    }
    if (!conflict.accepts(choice)) {
      throw ArgumentError('Choice $choice does not fit ${conflict.key}');
    }
    switch (conflict) {
      case FieldConflict():
        if (choice == ConflictChoice.keepPhone) {
          // The hub still holds the other value; pushing ours overwrites it.
          push.add(conflict.field);
        } else {
          adopt[conflict.field] = conflict.remote.value;
        }
      case DeleteEditConflict():
        _resolveDeleteEdit(conflict, choice, since, adopt, push);
    }
  }

  return record.copyWith(
    adopt: adopt,
    push: push,
    conflicts: const [],
    clearsDirty: true,
    resolvedConflicts: record.conflicts.length,
  );
}

void _resolveDeleteEdit(
  DeleteEditConflict conflict,
  ConflictChoice choice,
  int since,
  Map<String, Object?> adopt,
  Set<String> push,
) {
  final kind = conflict.kind;
  final local = conflict.local;
  final remote = conflict.remote;

  if (choice == ConflictChoice.deleteRecord) {
    // The edits are discarded, so both sides simply converge on the hub's
    // content and the record ends deleted everywhere.
    for (final f in kind.contentFields) {
      if (remote.value(f) != local.value(f)) adopt[f] = remote.value(f);
    }
    if (!remote.deleted) {
      push.add(deletedField);
    } else if (!local.deleted) {
      adopt[deletedField] = remote.value(deletedField);
    }
    return;
  }

  // keepRecord: restore it, letting the side that edited win any contested
  // field — the side that deleted expressed no opinion about field values.
  final editorIsPc = conflict.deletedOnPhone;
  for (final f in kind.contentFields) {
    final there = remote.rev(f) > since;
    final here = local.dirty.contains(f);
    final differs = remote.value(f) != local.value(f);
    if (!differs) continue;
    if (there && here) {
      if (editorIsPc) {
        adopt[f] = remote.value(f);
      } else {
        push.add(f);
      }
    } else if (there) {
      adopt[f] = remote.value(f);
    } else if (here) {
      push.add(f);
    }
  }
  if (local.deleted) {
    adopt[deletedField] = remote.value(deletedField);
  } else {
    push.add(deletedField);
  }
}
