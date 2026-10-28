import 'dart:io';

import 'package:uuid/uuid.dart';

import '../doc.dart';
import '../merge/merge_models.dart';
import '../protocol/protocol.dart';
import '../repository.dart';

/// Who this hub is. The id lives in the data file on purpose: wiping the file
/// gives a new identity, and phones then treat it as a different hub and push
/// everything again. OFFLINE_FIRST_SYNC_PLAYBOOK.md §3.2.
class HubIdentity {
  HubIdentity(this.repo, {String Function()? newId, int Function()? clock})
    : _newId = newId ?? (() => const Uuid().v4()),
      _clock = clock ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  final SyncRepository repo;
  final String Function() _newId;
  final int Function() _clock;

  /// Creates the identity on first use. Whatever data this PC already had is
  /// stamped at revision 1 in the same write, so a phone pulling from zero
  /// receives it instead of silently never seeing it.
  Future<ServerInfo> ensure() async {
    final existing = repo.data.sync.serverId;
    if (existing != null) return info(existing);

    final id = _newId();
    final now = _clock();
    final doc = repo.data;
    await repo.write(
      doc.copyWith(
        settingsMeta: _seed(doc.settingsMeta, settingsKind.fields, now),
        entries: [
          for (final e in doc.entries)
            e.copyWith(meta: _seed(e.meta, entryKind.fields, now)),
        ],
        forecasts: [
          for (final f in doc.forecasts)
            f.copyWith(meta: _seed(f.meta, forecastKind.fields, now)),
        ],
        sync: doc.sync.copyWith(serverId: id, revision: 1),
      ),
    );
    return info(id);
  }

  ServerInfo info(String serverId) =>
      ServerInfo(serverId: serverId, serverName: name);

  /// Shown on the phone, so a person recognises which PC they paired with.
  String get name {
    try {
      final host = Platform.localHostname;
      return host.isEmpty ? 'This PC' : host;
    } catch (_) {
      return 'This PC';
    }
  }

  RecordMeta _seed(RecordMeta meta, List<String> fields, int now) =>
      meta.copyWith(
        createdAt: meta.createdAt == 0 ? now : meta.createdAt,
        updatedAt: meta.updatedAt == 0 ? now : meta.updatedAt,
        at: {for (final f in fields) f: meta.at[f] ?? now},
        rev: {for (final f in fields) f: meta.rev[f] ?? 1},
        dirty: const {},
      );
}
