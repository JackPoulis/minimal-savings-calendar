import '../codec.dart';
import '../doc.dart';
import '../merge/merge_models.dart';
import '../protocol/sync_dtos.dart';
import '../repository.dart';
import 'device_registry.dart';

/// What a push did.
sealed class PushOutcome {
  const PushOutcome();
}

class PushApplied extends PushOutcome {
  const PushApplied({
    required this.revision,
    required this.changed,
    required this.records,
  });

  final int revision;
  final bool changed;
  final int records;
}

/// The hub moved on since the client pulled; it must pull again and retry.
class PushStale extends PushOutcome {
  const PushStale(this.revision);

  final int revision;
}

class PushInvalid extends PushOutcome {
  const PushInvalid(this.message);

  final String message;
}

/// The hub's half of the sync: hand out what changed, and take what the phone
/// decided. It stores values and stamps revisions — every merge decision was
/// already made on the phone.
///
/// OFFLINE_FIRST_SYNC_PLAYBOOK.md §6.2 and §6.3.
class HubSyncService {
  HubSyncService({
    required this.repo,
    required this.registry,
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  final SyncRepository repo;
  final DeviceRegistry registry;
  final int Function() _clock;

  Future<void> _lock = Future.value();

  /// Every record with any field newer than [since], all of its fields, and
  /// the revision they were read at — one consistent snapshot.
  PullResponse pull(int since) {
    final doc = repo.data;
    final records = <WireRecord>[];

    if (_changedSince(doc.settingsMeta, settingsKind, since)) {
      records.add(
        wireFromDocument(
          kind: settingsKind,
          id: settingsId,
          meta: doc.settingsMeta,
          values: settingsValues(doc),
        ),
      );
    }
    for (final entry in doc.entries) {
      if (!_changedSince(entry.meta, entryKind, since)) continue;
      records.add(
        wireFromDocument(
          kind: entryKind,
          id: entry.id,
          meta: entry.meta,
          values: entryValues(entry),
        ),
      );
    }
    for (final forecast in doc.forecasts) {
      if (!_changedSince(forecast.meta, forecastKind, since)) continue;
      records.add(
        wireFromDocument(
          kind: forecastKind,
          id: forecast.id,
          meta: forecast.meta,
          values: forecastValues(forecast),
        ),
      );
    }
    return PullResponse(revision: doc.sync.revision, records: records);
  }

  /// All or nothing: the document is written exactly once, at the end, with
  /// the revision bump and the device's last-sync time in the same save. A
  /// malformed change throws before anything is written.
  Future<PushOutcome> push(String deviceId, PushRequest request) {
    final result = _lock.then((_) => _push(deviceId, request));
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<PushOutcome> _push(String deviceId, PushRequest request) async {
    final current = repo.data.sync.revision;
    if (current != request.baseRevision) return PushStale(current);

    final next = current + 1;
    final now = _clock();
    var working = repo.data;
    var changed = false;

    try {
      for (final change in request.changes) {
        final kind = kindByWire(change.type);
        final values = <String, Object?>{
          for (final e in change.fields.entries)
            e.key: parseWireValue(kind, e.key, e.value.value),
        };
        final ats = <String, int>{
          for (final e in change.fields.entries)
            e.key: e.value.at == 0 ? now : e.value.at,
        };

        if (kind == settingsKind) {
          final stored = settingsValues(working);
          // Idempotency: a value equal to what we hold is not a change.
          final actual = {
            for (final e in values.entries)
              if (e.value != stored[e.key]) e.key: e.value,
          };
          if (actual.isEmpty) continue;
          working = applySettingsValues(working, actual).copyWith(
            settingsMeta: _stamp(
              working.settingsMeta,
              actual.keys,
              ats,
              next,
              now,
            ),
          );
          changed = true;
          continue;
        }

        if (kind == forecastKind) {
          final at = working.forecasts.indexWhere((f) => f.id == change.id);
          if (at < 0) {
            final meta = _stamp(
              RecordMeta(
                createdAt: change.createdAt == 0 ? now : change.createdAt,
              ),
              forecastKind.fields,
              ats,
              next,
              now,
            );
            final created = forecastFromValues(change.id, values, meta);
            working = working.copyWith(
              forecasts: [...working.forecasts, created],
            );
            changed = true;
            continue;
          }
          final stored = working.forecasts[at];
          final storedValues = forecastValues(stored);
          final actual = {
            for (final e in values.entries)
              if (e.value != storedValues[e.key]) e.key: e.value,
          };
          if (actual.isEmpty) continue;
          final updated = applyForecastValues(
            stored,
            actual,
          ).copyWith(meta: _stamp(stored.meta, actual.keys, ats, next, now));
          working = working.copyWith(
            forecasts: [
              for (final f in working.forecasts)
                if (f.id == stored.id) updated else f,
            ],
          );
          changed = true;
          continue;
        }

        final index = working.entries.indexWhere((e) => e.id == change.id);
        if (index < 0) {
          final meta = _stamp(
            RecordMeta(
              createdAt: change.createdAt == 0 ? now : change.createdAt,
            ),
            entryKind.fields,
            ats,
            next,
            now,
          );
          final created = entryFromValues(change.id, values, meta);
          working = working.copyWith(entries: [...working.entries, created]);
          changed = true;
          continue;
        }

        final stored = working.entries[index];
        final storedValues = entryValues(stored);
        final actual = {
          for (final e in values.entries)
            if (e.value != storedValues[e.key]) e.key: e.value,
        };
        if (actual.isEmpty) continue;
        final updated = applyEntryValues(
          stored,
          actual,
        ).copyWith(meta: _stamp(stored.meta, actual.keys, ats, next, now));
        working = working.copyWith(
          entries: [
            for (final e in working.entries)
              if (e.id == stored.id) updated else e,
          ],
        );
        changed = true;
      }
    } on FormatException catch (e) {
      return PushInvalid(e.message);
    }

    final revision = changed ? next : current;
    await repo.write(
      working.copyWith(
        sync: working.sync.copyWith(
          revision: revision,
          devices: registry.markedSynced(deviceId),
        ),
      ),
    );
    return PushApplied(
      revision: revision,
      changed: changed,
      records: request.changes.length,
    );
  }

  bool _changedSince(RecordMeta meta, RecordKind kind, int since) =>
      kind.fields.any((f) => (meta.rev[f] ?? 0) > since);

  RecordMeta _stamp(
    RecordMeta meta,
    Iterable<String> fields,
    Map<String, int> ats,
    int rev,
    int now,
  ) => meta.copyWith(
    createdAt: meta.createdAt == 0 ? now : meta.createdAt,
    updatedAt: now,
    at: {...meta.at, for (final f in fields) f: ats[f] ?? now},
    rev: {...meta.rev, for (final f in fields) f: rev},
  );
}
