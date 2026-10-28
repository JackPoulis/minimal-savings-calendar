import 'dart:io';

/// Which half of the sync this install plays. The PC is the hub (the only
/// server); phones are clients. OFFLINE_FIRST_SYNC_PLAYBOOK.md §1.
enum SyncRole {
  hub,
  client;

  bool get isHub => this == SyncRole.hub;
}

/// Android and iOS scan; everything else shows the QR code.
SyncRole platformRole() =>
    Platform.isAndroid || Platform.isIOS ? SyncRole.client : SyncRole.hub;
