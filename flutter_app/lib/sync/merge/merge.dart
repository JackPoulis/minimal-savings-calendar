/// `planSync`: decides, without touching a network or a file, what this sync
/// should adopt, what it should push, and what the user has to resolve.
///
/// OFFLINE_FIRST_SYNC_PLAYBOOK.md §7. There are deliberately no clocks in
/// here: change detection is the hub's revision counter versus the local dirty
/// set, never a timestamp comparison.
library;

import 'merge_models.dart';

String _key(RecordKind kind, String id) => '${kind.wire}/$id';

/// [locals] is every record on this device, tombstones included. [remotes] is
/// what the hub reported as changed since [since] (its `R0`).
SyncPlan planSync({
  required List<LocalRecord> locals,
  required List<RemoteRecord> remotes,
  required int since,
}) {
  final byKey = {for (final l in locals) _key(l.kind, l.id): l};
  final plans = <RecordPlan>[];
  final reported = <String>{};

  for (final remote in remotes) {
    final key = _key(remote.kind, remote.id);
    reported.add(key);
    final local = byKey[key];
    if (local == null) {
      // Never seen here — insert it. Also covers a record the hub deleted
      // before this phone ever heard of it.
      plans.add(
        RecordPlan(
          kind: remote.kind,
          id: remote.id,
          isNew: true,
          remote: remote,
          adopt: {for (final f in remote.kind.fields) f: remote.value(f)},
          clearsDirty: true,
        ),
      );
      continue;
    }
    plans.add(_mergeRecord(local, remote, since));
  }

  for (final local in locals) {
    if (reported.contains(_key(local.kind, local.id))) continue;
    if (local.dirty.isEmpty) continue;
    // Not reported by the hub and edited here: send what we changed. A record
    // created on this device has every field dirty, so it goes out in full.
    plans.add(
      RecordPlan(
        kind: local.kind,
        id: local.id,
        push: {...local.dirty},
        clearsDirty: true,
      ),
    );
  }

  return SyncPlan([
    for (final p in plans)
      if (!p.isEmpty) p,
  ]);
}

RecordPlan _mergeRecord(LocalRecord local, RemoteRecord remote, int since) {
  final kind = local.kind;
  bool remoteChanged(String f) => remote.rev(f) > since;
  bool localChanged(String f) => local.dirty.contains(f);
  final clearsDirty = local.dirty.isNotEmpty;

  // Gone on both sides: nothing to decide, just converge on the hub's copy.
  if (kind.deletable && local.deleted && remote.deleted) {
    return RecordPlan(
      kind: kind,
      id: local.id,
      remote: remote,
      adopt: {
        for (final f in kind.fields)
          if (remoteChanged(f) && remote.value(f) != local.value(f))
            f: remote.value(f),
      },
      clearsDirty: clearsDirty,
    );
  }

  if (kind.deletable) {
    // "Just" deleted, i.e. in this window — an old tombstone must not keep
    // raising a conflict.
    final remoteJustDeleted =
        remote.deleted && remoteChanged(deletedField) && !local.deleted;
    final localJustDeleted =
        local.deleted && localChanged(deletedField) && !remote.deleted;
    final localEdited = kind.contentFields.any(localChanged);
    final remoteEdited = kind.contentFields.any(remoteChanged);

    if ((remoteJustDeleted && localEdited) ||
        (localJustDeleted && remoteEdited)) {
      return RecordPlan(
        kind: kind,
        id: local.id,
        remote: remote,
        conflicts: [
          DeleteEditConflict(
            kind: kind,
            id: local.id,
            deletedOnPhone: localJustDeleted,
            local: local,
            remote: remote,
          ),
        ],
        clearsDirty: clearsDirty,
      );
    }
  }

  final adopt = <String, Object?>{};
  final push = <String>{};
  final conflicts = <Conflict>[];

  for (final f in kind.fields) {
    final here = localChanged(f);
    final there = remoteChanged(f);
    if (here && there) {
      // Both landed on the same value: not a conflict. This is what makes a
      // lost push response, and two people making the same edit, harmless.
      if (remote.value(f) == local.value(f)) continue;
      conflicts.add(
        FieldConflict(
          kind: kind,
          id: local.id,
          field: f,
          local: local.fields[f] ?? FieldState(local.value(f), 0),
          remote: remote.fields[f]!,
        ),
      );
    } else if (there) {
      if (remote.value(f) != local.value(f)) adopt[f] = remote.value(f);
    } else if (here) {
      push.add(f);
    }
  }

  return RecordPlan(
    kind: kind,
    id: local.id,
    remote: remote,
    adopt: adopt,
    push: push,
    conflicts: conflicts,
    clearsDirty: clearsDirty,
  );
}
