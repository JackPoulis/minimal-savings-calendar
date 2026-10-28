/// Converts between the stored document, the pure merge models and the wire
/// DTOs, and type-checks every value that arrives from the other device.
///
/// OFFLINE_FIRST_SYNC_PLAYBOOK.md §4 (validation) and §12.4.
library;

import '../model.dart';
import 'doc.dart';
import 'merge/merge_models.dart';
import 'protocol/sync_dtos.dart';

// ---------------------------------------------------------------- field access

Map<String, Object?> settingsValues(SavingsData d) => {
  'startDate': d.startDate,
  'endDate': d.endDate,
  'goal': d.goal,
  'loanAmount': d.loanAmount,
  'apr': d.apr,
  'loanYears': d.loanYears,
};

Map<String, Object?> entryValues(Entry e) => {
  'type': e.type,
  'title': e.title,
  'amount': e.amount,
  'date': e.date,
  deletedField: e.deleted,
};

Map<String, Object?> forecastValues(Forecast f) => {
  'type': f.type,
  'title': f.title,
  'amount': f.amount,
  deletedField: f.deleted,
};

/// Writes [values] (a subset of the settings fields) onto [d], leaving every
/// other field at its current stored value.
SavingsData applySettingsValues(SavingsData d, Map<String, Object?> values) {
  var next = d;
  for (final e in values.entries) {
    switch (e.key) {
      case 'startDate':
        next = next.copyWith(startDate: e.value as String);
      case 'endDate':
        next = next.copyWith(endDate: e.value as String);
      case 'goal':
        next = next.copyWith(goal: (e.value as num).toDouble());
      case 'loanAmount':
        next = next.copyWith(loanAmount: (e.value as num).toDouble());
      case 'apr':
        next = next.copyWith(apr: (e.value as num).toDouble());
      case 'loanYears':
        next = next.copyWith(loanYears: (e.value as num).toInt());
      default:
        throw FormatException('Unknown settings field "${e.key}"');
    }
  }
  return next;
}

/// Writes [values] (a subset of the entry fields) onto [e].
Entry applyEntryValues(Entry e, Map<String, Object?> values) {
  var next = e;
  for (final v in values.entries) {
    switch (v.key) {
      case 'type':
        next = next.copyWith(type: v.value as String);
      case 'title':
        next = next.copyWith(title: v.value as String);
      case 'amount':
        next = next.copyWith(amount: (v.value as num).toDouble());
      case 'date':
        next = next.copyWith(date: v.value as String);
      case deletedField:
        next = next.copyWith(deleted: v.value as bool);
      default:
        throw FormatException('Unknown entry field "${v.key}"');
    }
  }
  return next;
}

/// A record the hub sent that this device has never seen. [values] must cover
/// every entry field.
Entry entryFromValues(String id, Map<String, Object?> values, RecordMeta meta) {
  for (final f in entryKind.fields) {
    if (!values.containsKey(f)) {
      throw FormatException('A new entry is missing "$f"');
    }
  }
  return applyEntryValues(
    Entry(id: id, type: 'in', title: '', amount: 0, date: '', meta: meta),
    values,
  );
}

/// Writes [values] (a subset of the forecast fields) onto [f].
Forecast applyForecastValues(Forecast f, Map<String, Object?> values) {
  var next = f;
  for (final v in values.entries) {
    switch (v.key) {
      case 'type':
        next = next.copyWith(type: v.value as String);
      case 'title':
        next = next.copyWith(title: v.value as String);
      case 'amount':
        next = next.copyWith(amount: (v.value as num).toDouble());
      case deletedField:
        next = next.copyWith(deleted: v.value as bool);
      default:
        throw FormatException('Unknown forecast field "${v.key}"');
    }
  }
  return next;
}

/// A forecast the hub sent that this device has never seen. [values] must
/// cover every forecast field.
Forecast forecastFromValues(
  String id,
  Map<String, Object?> values,
  RecordMeta meta,
) {
  for (final f in forecastKind.fields) {
    if (!values.containsKey(f)) {
      throw FormatException('A new forecast is missing "$f"');
    }
  }
  return applyForecastValues(
    Forecast(id: id, type: 'in', title: '', amount: 0, meta: meta),
    values,
  );
}

// ------------------------------------------------------------------ validation

/// The one place a value from another device is checked. Enums travel by name.
Object? parseWireValue(RecordKind kind, String field, Object? raw) {
  if (!kind.fields.contains(field)) {
    throw FormatException('Unknown ${kind.wire} field "$field"');
  }
  switch (field) {
    case 'type':
      if (raw != 'in' && raw != 'out') {
        throw FormatException('"$field" must be "in" or "out"');
      }
      return raw;
    case 'title':
    case 'date':
    case 'startDate':
    case 'endDate':
      if (raw is! String) throw FormatException('"$field" must be text');
      return raw;
    case 'amount':
    case 'goal':
    case 'loanAmount':
    case 'apr':
      if (raw is! num) throw FormatException('"$field" must be a number');
      return raw.toDouble();
    case 'loanYears':
      if (raw is! num || raw != raw.roundToDouble()) {
        throw FormatException('"$field" must be a whole number');
      }
      return raw.toInt();
    case deletedField:
      if (raw is! bool) throw FormatException('"$field" must be true or false');
      return raw;
    default:
      throw FormatException('Unknown ${kind.wire} field "$field"');
  }
}

// -------------------------------------------------------- document -> models

LocalRecord settingsLocal(SavingsData d) {
  final meta = d.settingsMeta;
  final values = settingsValues(d);
  return LocalRecord(
    kind: settingsKind,
    id: settingsId,
    createdAt: meta.createdAt,
    version: meta.updatedAt,
    fields: {
      for (final f in settingsKind.fields)
        f: FieldState(values[f], meta.at[f] ?? 0),
    },
    dirty: {...meta.dirty},
  );
}

LocalRecord entryLocal(Entry e) {
  final values = entryValues(e);
  return LocalRecord(
    kind: entryKind,
    id: e.id,
    createdAt: e.meta.createdAt,
    version: e.meta.updatedAt,
    fields: {
      for (final f in entryKind.fields)
        f: FieldState(values[f], e.meta.at[f] ?? 0),
    },
    dirty: {...e.meta.dirty},
  );
}

LocalRecord forecastLocal(Forecast f) {
  final values = forecastValues(f);
  return LocalRecord(
    kind: forecastKind,
    id: f.id,
    createdAt: f.meta.createdAt,
    version: f.meta.updatedAt,
    fields: {
      for (final name in forecastKind.fields)
        name: FieldState(values[name], f.meta.at[name] ?? 0),
    },
    dirty: {...f.meta.dirty},
  );
}

/// Every record on this device, tombstones included.
List<LocalRecord> localRecords(SavingsData d) => [
  settingsLocal(d),
  for (final e in d.entries) entryLocal(e),
  for (final f in d.forecasts) forecastLocal(f),
];

// ------------------------------------------------------------ models <-> wire

/// Builds the pull payload for one record: all fields, each with its revision.
WireRecord wireFromDocument({
  required RecordKind kind,
  required String id,
  required RecordMeta meta,
  required Map<String, Object?> values,
}) => WireRecord(
  type: kind.wire,
  id: id,
  createdAt: meta.createdAt,
  fields: {
    for (final f in kind.fields)
      f: WireField(
        value: values[f],
        at: meta.at[f] ?? 0,
        rev: meta.rev[f] ?? 0,
      ),
  },
);

/// Parses a pulled record. A pull always carries every field, so a missing one
/// is a protocol error rather than something to guess at.
RemoteRecord remoteFromWire(WireRecord w) {
  final kind = kindByWire(w.type);
  for (final name in w.fields.keys) {
    if (!kind.fields.contains(name)) {
      throw FormatException('Unknown ${kind.wire} field "$name"');
    }
  }
  final fields = <String, RemoteField>{};
  for (final f in kind.fields) {
    final raw = w.fields[f];
    if (raw == null) {
      throw FormatException('The ${kind.wire} "${w.id}" is missing "$f"');
    }
    fields[f] = RemoteField(
      parseWireValue(kind, f, raw.value),
      raw.at,
      raw.rev ?? 0,
    );
  }
  return RemoteRecord(
    kind: kind,
    id: w.id,
    createdAt: w.createdAt,
    fields: fields,
  );
}

List<RemoteRecord> remotesFromPull(PullResponse pull) =>
    pull.records.map(remoteFromWire).toList();

/// The push payload: only the fields this device is sending, except for a
/// record the hub does not know yet, which carries all of them (a record
/// created here has every field dirty, so that falls out on its own).
List<WireRecord> buildChanges(SyncPlan plan, SavingsData doc) {
  final entriesById = {for (final e in doc.entries) e.id: e};
  final forecastsById = {for (final f in doc.forecasts) f.id: f};
  final changes = <WireRecord>[];
  for (final record in plan.records) {
    if (record.push.isEmpty) continue;
    final Map<String, Object?> values;
    final RecordMeta meta;
    if (record.kind == settingsKind) {
      values = settingsValues(doc);
      meta = doc.settingsMeta;
    } else if (record.kind == forecastKind) {
      final forecast = forecastsById[record.id];
      if (forecast == null) continue;
      values = forecastValues(forecast);
      meta = forecast.meta;
    } else {
      final entry = entriesById[record.id];
      if (entry == null) continue;
      values = entryValues(entry);
      meta = entry.meta;
    }
    changes.add(
      WireRecord(
        type: record.kind.wire,
        id: record.id,
        createdAt: meta.createdAt,
        fields: {
          for (final f in record.push)
            f: WireField(value: values[f], at: meta.at[f] ?? 0),
        },
      ),
    );
  }
  return changes;
}
