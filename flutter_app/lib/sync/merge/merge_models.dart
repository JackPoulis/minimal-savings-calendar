/// Pure data types for merging. No Flutter, no dart:io, no file access — so
/// the most bug-prone logic in the app can be unit tested on its own.
///
/// OFFLINE_FIRST_SYNC_PLAYBOOK.md §7.
library;

/// The tombstone field. It is a synced field like any other, which is what
/// makes a deletion merge like an ordinary edit.
const deletedField = 'deleted';

/// The single settings record's id.
const settingsId = 'settings';

/// A kind of synced record: its wire name and its field list.
class RecordKind {
  const RecordKind({
    required this.wire,
    required this.fields,
    required this.deletable,
  });

  final String wire;

  /// Every synced field, including [deletedField] when [deletable].
  final List<String> fields;

  /// Whether the record can be deleted. The settings record cannot.
  final bool deletable;

  /// Everything except the tombstone — "edited" means one of these changed.
  Iterable<String> get contentFields => fields.where((f) => f != deletedField);

  @override
  String toString() => wire;
}

const entryKind = RecordKind(
  wire: 'entry',
  fields: ['type', 'title', 'amount', 'date', deletedField],
  deletable: true,
);

const forecastKind = RecordKind(
  wire: 'forecast',
  fields: ['type', 'title', 'amount', deletedField],
  deletable: true,
);

const settingsKind = RecordKind(
  wire: 'settings',
  fields: ['startDate', 'endDate', 'goal', 'loanAmount', 'apr', 'loanYears'],
  deletable: false,
);

const allKinds = [entryKind, forecastKind, settingsKind];

RecordKind kindByWire(String wire) => allKinds.firstWhere(
  (k) => k.wire == wire,
  orElse: () => throw FormatException('Unknown record type "$wire"'),
);

/// One field of a local record: its value and when it was last edited here.
class FieldState {
  const FieldState(this.value, this.at);

  final Object? value;

  /// UTC ms. Display only — never compared to decide a winner.
  final int at;
}

/// One field as the hub reports it.
class RemoteField {
  const RemoteField(this.value, this.at, this.rev);

  final Object? value;
  final int at;

  /// The hub revision at which this field last changed.
  final int rev;
}

/// A record as it exists on this device.
class LocalRecord {
  const LocalRecord({
    required this.kind,
    required this.id,
    required this.createdAt,
    required this.version,
    required this.fields,
    required this.dirty,
  });

  final RecordKind kind;
  final String id;
  final int createdAt;

  /// The record's `updatedAt`, used to notice a local edit made during a sync.
  final int version;

  final Map<String, FieldState> fields;

  /// Fields edited here since the last successful sync.
  final Set<String> dirty;

  bool get deleted => fields[deletedField]?.value == true;

  Object? value(String field) => fields[field]?.value;
}

/// A record as the hub reports it.
class RemoteRecord {
  const RemoteRecord({
    required this.kind,
    required this.id,
    required this.createdAt,
    required this.fields,
  });

  final RecordKind kind;
  final String id;
  final int createdAt;
  final Map<String, RemoteField> fields;

  bool get deleted => fields[deletedField]?.value == true;

  Object? value(String field) => fields[field]?.value;

  int rev(String field) => fields[field]?.rev ?? 0;

  bool changedSince(int since) => fields.values.any((f) => f.rev > since);
}

/// What the user can pick for a conflict.
enum ConflictChoice { keepPhone, keepPc, keepRecord, deleteRecord }

/// Something both sides changed incompatibly. Resolved by the user.
sealed class Conflict {
  const Conflict();

  RecordKind get kind;
  String get id;

  /// Stable identifier used as the key of the choices map.
  String get key;

  /// What the phone did, and what the PC did.
  ConflictChoice get phoneSide;
  ConflictChoice get pcSide;

  bool accepts(ConflictChoice choice) =>
      choice == phoneSide || choice == pcSide;

  /// The values this conflict was raised on. An answer given before a retry is
  /// only reused while this is unchanged.
  String get signature;
}

/// The same field changed to different values on both sides.
class FieldConflict extends Conflict {
  const FieldConflict({
    required this.kind,
    required this.id,
    required this.field,
    required this.local,
    required this.remote,
  });

  @override
  final RecordKind kind;
  @override
  final String id;
  final String field;
  final FieldState local;
  final RemoteField remote;

  @override
  String get key => '$id/$field';

  @override
  ConflictChoice get phoneSide => ConflictChoice.keepPhone;

  @override
  ConflictChoice get pcSide => ConflictChoice.keepPc;

  @override
  String get signature =>
      '${kind.wire}/$id/$field'
      '|${local.value}|${remote.value}';
}

/// Deleted on one side while the other side edited it.
class DeleteEditConflict extends Conflict {
  const DeleteEditConflict({
    required this.kind,
    required this.id,
    required this.deletedOnPhone,
    required this.local,
    required this.remote,
  });

  @override
  final RecordKind kind;
  @override
  final String id;

  /// True when the phone deleted and the PC edited; false the other way round.
  final bool deletedOnPhone;

  final LocalRecord local;
  final RemoteRecord remote;

  @override
  String get key => '$id/record';

  @override
  ConflictChoice get phoneSide =>
      deletedOnPhone ? ConflictChoice.deleteRecord : ConflictChoice.keepRecord;

  @override
  ConflictChoice get pcSide =>
      deletedOnPhone ? ConflictChoice.keepRecord : ConflictChoice.deleteRecord;

  @override
  String get signature {
    final parts = [
      for (final f in kind.fields) '${local.value(f)}>${remote.value(f)}',
    ];
    return '${kind.wire}/$id/record|$deletedOnPhone|${parts.join(',')}';
  }
}

/// What to do with one record in this sync.
class RecordPlan {
  const RecordPlan({
    required this.kind,
    required this.id,
    this.isNew = false,
    this.remote,
    this.adopt = const {},
    this.push = const {},
    this.conflicts = const [],
    this.clearsDirty = false,
    this.resolvedConflicts = 0,
  });

  final RecordKind kind;
  final String id;

  /// The hub has a record this device has never seen; insert it.
  final bool isNew;

  /// The hub's copy, when the hub reported this record. The commit reads the
  /// adopted fields' edit times from it.
  final RemoteRecord? remote;

  /// Field -> value to take from the hub.
  final Map<String, Object?> adopt;

  /// Fields to send to the hub.
  final Set<String> push;

  final List<Conflict> conflicts;

  /// Whether committing this plan clears the record's dirty set.
  final bool clearsDirty;

  final int resolvedConflicts;

  bool get isEmpty =>
      !isNew &&
      adopt.isEmpty &&
      push.isEmpty &&
      conflicts.isEmpty &&
      !clearsDirty;

  /// Both sides changed something, but different things.
  bool get autoMerged => !isNew && adopt.isNotEmpty && push.isNotEmpty;

  RecordPlan copyWith({
    Map<String, Object?>? adopt,
    Set<String>? push,
    List<Conflict>? conflicts,
    bool? clearsDirty,
    int? resolvedConflicts,
  }) => RecordPlan(
    kind: kind,
    id: id,
    isNew: isNew,
    remote: remote,
    adopt: adopt ?? this.adopt,
    push: push ?? this.push,
    conflicts: conflicts ?? this.conflicts,
    clearsDirty: clearsDirty ?? this.clearsDirty,
    resolvedConflicts: resolvedConflicts ?? this.resolvedConflicts,
  );
}

/// The whole sync, decided but not yet applied anywhere.
class SyncPlan {
  const SyncPlan(this.records);

  final List<RecordPlan> records;

  List<Conflict> get conflicts => [for (final r in records) ...r.conflicts];

  bool get hasConflicts => records.any((r) => r.conflicts.isNotEmpty);

  int get pulled => records.where((r) => r.isNew || r.adopt.isNotEmpty).length;

  int get pushed => records.where((r) => r.push.isNotEmpty).length;

  int get autoMerged => records.where((r) => r.autoMerged).length;

  int get resolved => records.fold(0, (s, r) => s + r.resolvedConflicts);

  bool get isEmpty => records.every((r) => r.isEmpty);
}
