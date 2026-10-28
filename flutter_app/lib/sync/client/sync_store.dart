import '../codec.dart';
import '../doc.dart';
import '../merge/merge_models.dart';
import '../protocol/sync_dtos.dart';
import '../repository.dart';
import 'hub_api.dart';

/// The phone's local side of a sync: read the records, build the push, and —
/// only once the hub has accepted that push — apply everything in one write.
///
/// OFFLINE_FIRST_SYNC_PLAYBOOK.md §6.4.
class SyncStore {
  SyncStore({required this.repo, int Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  final SyncRepository repo;
  final int Function() _clock;

  List<LocalRecord> loadAll() => localRecords(repo.data);

  List<WireRecord> changes(SyncPlan plan) => buildChanges(plan, repo.data);

  /// Applies the plan and moves the revision forward. Throws
  /// [SyncInterrupted] if anything was edited here since [locals] was read —
  /// the hub already holds the pushed values, so the next sync simply finds
  /// both sides equal and nothing is lost.
  Future<void> commit({
    required SyncPlan plan,
    required List<LocalRecord> locals,
    required int newRevision,
  }) async {
    final doc = repo.data;
    final versions = {
      for (final l in locals) '${l.kind.wire}/${l.id}': l.version,
    };
    final entries = {for (final e in doc.entries) e.id: e};
    final forecasts = {for (final f in doc.forecasts) f.id: f};

    for (final record in plan.records) {
      if (record.isNew) continue;
      final expected = versions['${record.kind.wire}/${record.id}'];
      final actual = record.kind == settingsKind
          ? doc.settingsMeta.updatedAt
          : record.kind == forecastKind
          ? forecasts[record.id]?.meta.updatedAt
          : entries[record.id]?.meta.updatedAt;
      if (expected == null || actual == null || actual != expected) {
        throw const SyncInterrupted();
      }
    }

    var next = doc;
    for (final record in plan.records) {
      if (record.kind == settingsKind) {
        next = applySettingsValues(
          next,
          record.adopt,
        ).copyWith(settingsMeta: _adopt(next.settingsMeta, record));
        continue;
      }
      if (record.kind == forecastKind) {
        if (record.isNew) {
          next = next.copyWith(
            forecasts: [
              ...next.forecasts,
              forecastFromValues(
                record.id,
                record.adopt,
                _adopt(
                  RecordMeta(
                    createdAt: record.remote?.createdAt ?? _clock(),
                    updatedAt: _clock(),
                  ),
                  record,
                ),
              ),
            ],
          );
          continue;
        }
        final stored = forecasts[record.id];
        if (stored == null) continue;
        final updated = applyForecastValues(
          stored,
          record.adopt,
        ).copyWith(meta: _adopt(stored.meta, record));
        next = next.copyWith(
          forecasts: [
            for (final f in next.forecasts)
              if (f.id == record.id) updated else f,
          ],
        );
        continue;
      }
      if (record.isNew) {
        next = next.copyWith(
          entries: [
            ...next.entries,
            entryFromValues(
              record.id,
              record.adopt,
              _adopt(
                RecordMeta(
                  createdAt: record.remote?.createdAt ?? _clock(),
                  updatedAt: _clock(),
                ),
                record,
              ),
            ),
          ],
        );
        continue;
      }
      final stored = entries[record.id];
      if (stored == null) continue;
      final updated = applyEntryValues(
        stored,
        record.adopt,
      ).copyWith(meta: _adopt(stored.meta, record));
      next = next.copyWith(
        entries: [
          for (final e in next.entries)
            if (e.id == record.id) updated else e,
        ],
      );
    }

    final pairing = next.sync.pairing;
    await repo.write(
      next.copyWith(
        sync: next.sync.copyWith(
          pairing: pairing?.copyWith(
            lastSyncedRevision: newRevision,
            lastSyncAt: _clock(),
          ),
        ),
      ),
    );
  }

  /// Adopting is not a local edit: it writes the value and the other side's
  /// edit time, never a dirty mark and never a revision.
  RecordMeta _adopt(RecordMeta meta, RecordPlan record) => meta.copyWith(
    at: {
      ...meta.at,
      for (final f in record.adopt.keys)
        f: record.remote?.fields[f]?.at ?? meta.at[f] ?? _clock(),
    },
    dirty: record.clearsDirty ? const {} : meta.dirty,
  );
}
