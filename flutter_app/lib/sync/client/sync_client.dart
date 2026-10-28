import 'package:http/http.dart' as http;

import '../codec.dart';
import '../merge/merge.dart';
import '../merge/merge_models.dart';
import '../merge/resolve.dart';
import '../protocol/sync_dtos.dart';
import '../repository.dart';
import 'hub_api.dart';
import 'sync_store.dart';

/// Asks the user what to do. Returning null cancels the whole sync.
typedef ConflictResolver = Future<Map<String, ConflictChoice>?> Function(
  List<Conflict> conflicts,
);

class SyncSummary {
  const SyncSummary({
    required this.pulled,
    required this.pushed,
    required this.autoMerged,
    required this.resolved,
    required this.hubName,
  });

  final int pulled;
  final int pushed;
  final int autoMerged;
  final int resolved;
  final String hubName;

  bool get nothingChanged => pulled == 0 && pushed == 0;

  /// The one line the phone shows when a sync finishes.
  String get text {
    if (nothingChanged) return 'Already in sync — nothing changed.';
    final parts = [
      if (pulled > 0) '$pulled received',
      if (pushed > 0) '$pushed sent',
      if (autoMerged > 0) '$autoMerged merged',
      if (resolved > 0) '$resolved resolved',
    ];
    return parts.join(', ');
  }
}

/// Drives one sync: pull, merge, resolve, push, then commit locally.
///
/// OFFLINE_FIRST_SYNC_PLAYBOOK.md §6.1. The push is always sent, even when
/// empty, so the hub checks our base revision either way; nothing is written
/// on this phone until that push came back accepted.
class SyncClient {
  SyncClient({
    required this.repo,
    this.client,
    int Function()? clock,
    this.beforePush,
  }) : _store = SyncStore(repo: repo, clock: clock);

  static const maxAttempts = 3;

  final SyncRepository repo;

  /// Injectable for tests, which talk to the hub's handler without a socket.
  final http.Client? client;

  /// Test hook: runs between the merge and the push, to simulate the PC being
  /// edited mid-sync.
  final Future<void> Function()? beforePush;

  final SyncStore _store;

  bool _running = false;
  bool get running => _running;

  Future<SyncSummary> run({ConflictResolver? resolver}) async {
    if (_running) throw const Rejected('A sync is already running.');
    _running = true;
    try {
      return await _run(resolver);
    } finally {
      _running = false;
    }
  }

  Future<SyncSummary> _run(ConflictResolver? resolver) async {
    final pairing = repo.data.sync.pairing;
    if (pairing == null) throw const NotPaired();

    final api = HubApi(
      baseUrl: pairing.baseUrl,
      secret: pairing.deviceSecret,
      client: client,
    );

    // Fail before reading or sending anything if the hub is not the one we
    // think it is.
    final ping = await api.ping();
    if (ping.server.serverId != pairing.serverId) throw const DifferentHub();

    final remembered = <String, ConflictChoice>{};
    final signatures = <String, String>{};

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final since = repo.data.sync.pairing?.lastSyncedRevision ?? 0;
      final pull = await api.pull(since);
      final List<RemoteRecord> remotes;
      try {
        remotes = remotesFromPull(pull);
      } on FormatException {
        throw const BadData();
      }

      final locals = _store.loadAll();
      var plan = planSync(locals: locals, remotes: remotes, since: since);

      if (plan.hasConflicts) {
        if (resolver == null) throw ConflictsPending(plan.conflicts.length);
        final choices = await _decide(
          plan.conflicts,
          remembered,
          signatures,
          resolver,
        );
        plan = resolveConflicts(plan: plan, choices: choices, since: since);
      }

      final changes = _store.changes(plan);
      if (beforePush != null) await beforePush!();

      final PushResponse push;
      try {
        push = await api.push(
          PushRequest(baseRevision: pull.revision, changes: changes),
        );
      } on StaleRevision {
        // The PC changed while we were deciding: start over from a fresh pull.
        continue;
      }

      await _store.commit(
        plan: plan,
        locals: locals,
        newRevision: push.revision,
      );

      return SyncSummary(
        pulled: plan.pulled,
        pushed: plan.pushed,
        autoMerged: plan.autoMerged,
        resolved: plan.resolved,
        hubName: ping.server.serverName,
      );
    }
    throw const RetriesExhausted();
  }

  /// Reuses an answer across a retry only while the values it was given for
  /// are unchanged; otherwise the user is asked again.
  Future<Map<String, ConflictChoice>> _decide(
    List<Conflict> conflicts,
    Map<String, ConflictChoice> remembered,
    Map<String, String> signatures,
    ConflictResolver resolver,
  ) async {
    final stale = conflicts.any(
      (c) => !remembered.containsKey(c.key) || signatures[c.key] != c.signature,
    );

    if (stale) {
      final answers = await resolver(conflicts);
      if (answers == null) throw const SyncCancelled();
      remembered
        ..removeWhere((key, _) => true)
        ..addAll(answers);
      signatures
        ..removeWhere((key, _) => true)
        ..addEntries(conflicts.map((c) => MapEntry(c.key, c.signature)));
    }

    for (final conflict in conflicts) {
      final choice = remembered[conflict.key];
      if (choice == null || !conflict.accepts(choice)) {
        throw const SyncCancelled();
      }
    }
    return remembered;
  }
}
