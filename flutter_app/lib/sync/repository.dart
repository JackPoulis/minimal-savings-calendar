import 'package:flutter/foundation.dart';

import '../model.dart';
import '../store.dart';
import 'codec.dart';
import 'doc.dart';
import 'merge/merge_models.dart';

/// Every write to the data goes through here, so change tracking can never be
/// forgotten. OFFLINE_FIRST_SYNC_PLAYBOOK.md §3.3.
///
/// On the hub a write bumps the global revision and stamps it on the fields
/// that changed; on a client it adds them to the record's dirty set. Neither
/// role ever compares clocks — the `at` stamps exist only for the conflict
/// screen to show.
class SyncRepository {
  SyncRepository({
    required this.store,
    required this.isHub,
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  final Store store;
  final bool isHub;
  final int Function() _clock;

  /// The loaded document, or null until [load] finishes. The UI listens to it
  /// so a sync's result shows up without reloading the app.
  final ValueNotifier<SavingsData?> changes = ValueNotifier(null);

  SavingsData get data {
    final d = changes.value;
    if (d == null) throw StateError('The data has not been loaded yet');
    return d;
  }

  int get revision => data.sync.revision;

  Future<SavingsData> load() async {
    final loaded = await store.load();
    changes.value = loaded;
    return loaded;
  }

  /// Replaces the whole document in one save, with no change tracking. Used by
  /// the sync commit, where adopted values must not count as local edits.
  Future<void> write(SavingsData next) async {
    changes.value = next;
    await store.save(next);
  }

  // ------------------------------------------------------------------ settings

  /// [base] is what the editor opened with: only fields the user changed
  /// relative to it are written, so a stale editor cannot clobber values that
  /// arrived from a sync in the meantime.
  Future<void> updateSettings(SavingsData edited, {SavingsData? base}) {
    final current = settingsValues(data);
    final from = settingsValues(base ?? data);
    final to = settingsValues(edited);
    final changed = <String, Object?>{
      for (final f in settingsKind.fields)
        if (to[f] != from[f] && to[f] != current[f]) f: to[f],
    };
    if (changed.isEmpty) return Future.value();

    final now = _clock();
    final rev = isHub ? data.sync.revision + 1 : null;
    var next = applySettingsValues(data, changed);
    next = next.copyWith(
      settingsMeta: _stamp(data.settingsMeta, changed.keys, now, rev),
      sync: rev == null ? data.sync : data.sync.copyWith(revision: rev),
    );
    return write(next);
  }

  // ------------------------------------------------------------------- entries

  Future<void> saveEntry(Entry edited, {Entry? base}) {
    final stored = _entry(edited.id);
    if (stored == null) return _createEntry(edited);

    final current = entryValues(stored);
    final from = entryValues(base ?? stored);
    final to = entryValues(edited);
    final changed = <String, Object?>{
      for (final f in entryKind.fields)
        if (to[f] != from[f] && to[f] != current[f]) f: to[f],
    };
    return _writeEntry(stored, changed);
  }

  /// A soft delete: the tombstone is an ordinary field change, so it syncs and
  /// merges like any other edit.
  Future<void> deleteEntry(String id) {
    final stored = _entry(id);
    if (stored == null || stored.deleted) return Future.value();
    return _writeEntry(stored, const {deletedField: true});
  }

  Future<void> _createEntry(Entry entry) {
    final now = _clock();
    final rev = isHub ? data.sync.revision + 1 : null;
    // A brand-new record is dirty in full, so it is pushed whole.
    final meta = _stamp(RecordMeta(createdAt: now), entryKind.fields, now, rev);
    return write(
      data.copyWith(
        entries: [
          ...data.entries,
          entry.copyWith(meta: meta),
        ],
        sync: rev == null ? data.sync : data.sync.copyWith(revision: rev),
      ),
    );
  }

  Future<void> _writeEntry(Entry stored, Map<String, Object?> changed) {
    if (changed.isEmpty) return Future.value();
    final now = _clock();
    final rev = isHub ? data.sync.revision + 1 : null;
    final updated = applyEntryValues(
      stored,
      changed,
    ).copyWith(meta: _stamp(stored.meta, changed.keys, now, rev));
    return write(
      data.copyWith(
        entries: [
          for (final e in data.entries)
            if (e.id == stored.id) updated else e,
        ],
        sync: rev == null ? data.sync : data.sync.copyWith(revision: rev),
      ),
    );
  }

  Entry? _entry(String id) {
    for (final e in data.entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  // ----------------------------------------------------------------- forecasts

  Future<void> saveForecast(Forecast edited, {Forecast? base}) {
    final stored = _forecast(edited.id);
    if (stored == null) return _createForecast(edited);

    final current = forecastValues(stored);
    final from = forecastValues(base ?? stored);
    final to = forecastValues(edited);
    final changed = <String, Object?>{
      for (final f in forecastKind.fields)
        if (to[f] != from[f] && to[f] != current[f]) f: to[f],
    };
    return _writeForecast(stored, changed);
  }

  Future<void> deleteForecast(String id) {
    final stored = _forecast(id);
    if (stored == null || stored.deleted) return Future.value();
    return _writeForecast(stored, const {deletedField: true});
  }

  Future<void> _createForecast(Forecast forecast) {
    final now = _clock();
    final rev = isHub ? data.sync.revision + 1 : null;
    final meta = _stamp(
      RecordMeta(createdAt: now),
      forecastKind.fields,
      now,
      rev,
    );
    return write(
      data.copyWith(
        forecasts: [
          ...data.forecasts,
          forecast.copyWith(meta: meta),
        ],
        sync: rev == null ? data.sync : data.sync.copyWith(revision: rev),
      ),
    );
  }

  Future<void> _writeForecast(Forecast stored, Map<String, Object?> changed) {
    if (changed.isEmpty) return Future.value();
    final now = _clock();
    final rev = isHub ? data.sync.revision + 1 : null;
    final updated = applyForecastValues(
      stored,
      changed,
    ).copyWith(meta: _stamp(stored.meta, changed.keys, now, rev));
    return write(
      data.copyWith(
        forecasts: [
          for (final f in data.forecasts)
            if (f.id == stored.id) updated else f,
        ],
        sync: rev == null ? data.sync : data.sync.copyWith(revision: rev),
      ),
    );
  }

  Forecast? _forecast(String id) {
    for (final f in data.forecasts) {
      if (f.id == id) return f;
    }
    return null;
  }

  // --------------------------------------------------------------- sync states

  /// Marks every field of every record dirty, so the next sync pushes the
  /// whole document. Used when the phone meets a different hub (§5.3).
  Future<void> markAllDirty() => write(allDirty(data, _clock()));

  /// The same transform without writing, so pairing can store it together
  /// with the new pairing row in a single save.
  static SavingsData allDirty(SavingsData doc, int now) => doc.copyWith(
    settingsMeta: doc.settingsMeta.copyWith(
      dirty: {...settingsKind.fields},
      createdAt: doc.settingsMeta.createdAt == 0
          ? now
          : doc.settingsMeta.createdAt,
      updatedAt: doc.settingsMeta.updatedAt == 0
          ? now
          : doc.settingsMeta.updatedAt,
    ),
    entries: [
      for (final e in doc.entries)
        e.copyWith(
          meta: e.meta.copyWith(
            dirty: {...entryKind.fields},
            createdAt: e.meta.createdAt == 0 ? now : e.meta.createdAt,
            updatedAt: e.meta.updatedAt == 0 ? now : e.meta.updatedAt,
          ),
        ),
    ],
    forecasts: [
      for (final f in doc.forecasts)
        f.copyWith(
          meta: f.meta.copyWith(
            dirty: {...forecastKind.fields},
            createdAt: f.meta.createdAt == 0 ? now : f.meta.createdAt,
            updatedAt: f.meta.updatedAt == 0 ? now : f.meta.updatedAt,
          ),
        ),
    ],
  );

  /// Stamps the fields that really changed. [rev] is the hub's new revision,
  /// or null on a client, where the fields are marked dirty instead.
  RecordMeta _stamp(
    RecordMeta meta,
    Iterable<String> changed,
    int now,
    int? rev,
  ) => meta.copyWith(
    createdAt: meta.createdAt == 0 ? now : meta.createdAt,
    updatedAt: now,
    at: {...meta.at, for (final f in changed) f: now},
    rev: rev == null
        ? meta.rev
        : {...meta.rev, for (final f in changed) f: rev},
    dirty: rev != null ? meta.dirty : {...meta.dirty, ...changed},
  );
}
