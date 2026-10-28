/// The bookkeeping half of the stored document: per-record change tracking and
/// the pairing state of whichever role this install plays.
///
/// See OFFLINE_FIRST_SYNC_PLAYBOOK.md §3. Nothing here is shown to the user
/// except the `at` timestamps, which the conflict screen displays and no code
/// ever compares to pick a winner.
library;

int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

Map<String, int> _intMap(Object? v) => v is Map
    ? {
        for (final e in v.entries)
          if (e.key is String) e.key as String: _int(e.value),
      }
    : const {};

Set<String> _strSet(Object? v) => v is List
    ? {
        for (final e in v)
          if (e is String) e,
      }
    : const {};

/// Change tracking for one record (an entry, or the settings as a whole).
class RecordMeta {
  const RecordMeta({
    this.createdAt = 0,
    this.updatedAt = 0,
    this.at = const {},
    this.rev = const {},
    this.dirty = const {},
  });

  /// A record that has never been tracked — what an older `data.json` yields.
  const RecordMeta.unset() : this();

  factory RecordMeta.fromJson(Map<String, dynamic> j) => RecordMeta(
    createdAt: _int(j['createdAt']),
    updatedAt: _int(j['updatedAt']),
    at: _intMap(j['at']),
    rev: _intMap(j['rev']),
    dirty: _strSet(j['dirty']),
  );

  /// Set once when the record is created, never changed.
  final int createdAt;

  /// UTC ms of the last local edit of any field; also the client's version
  /// stamp, used to notice edits made while a sync was running.
  final int updatedAt;

  /// UTC ms per field of its last edit. Display only.
  final Map<String, int> at;

  /// Hub only: the hub revision at which each field last changed.
  final Map<String, int> rev;

  /// Client only: fields edited since the last successful sync.
  final Set<String> dirty;

  bool get isEmpty =>
      createdAt == 0 &&
      updatedAt == 0 &&
      at.isEmpty &&
      rev.isEmpty &&
      dirty.isEmpty;

  /// Empty collections are left out so an unsynced file stays as small and
  /// readable as it was before sync existed.
  Map<String, dynamic> toJson() => {
    if (createdAt != 0) 'createdAt': createdAt,
    if (updatedAt != 0) 'updatedAt': updatedAt,
    if (at.isNotEmpty) 'at': at,
    if (rev.isNotEmpty) 'rev': rev,
    if (dirty.isNotEmpty) 'dirty': dirty.toList()..sort(),
  };

  RecordMeta copyWith({
    int? createdAt,
    int? updatedAt,
    Map<String, int>? at,
    Map<String, int>? rev,
    Set<String>? dirty,
  }) => RecordMeta(
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    at: at ?? this.at,
    rev: rev ?? this.rev,
    dirty: dirty ?? this.dirty,
  );
}

/// Hub side: a phone that has paired. The secret itself is never stored.
class PairedDevice {
  const PairedDevice({
    required this.deviceId,
    required this.name,
    required this.secretHash,
    required this.pairedAt,
    this.lastSyncAt,
    this.revoked = false,
  });

  factory PairedDevice.fromJson(Map<String, dynamic> j) => PairedDevice(
    deviceId: (j['deviceId'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
    secretHash: (j['secretHash'] as String?) ?? '',
    pairedAt: _int(j['pairedAt']),
    lastSyncAt: j['lastSyncAt'] == null ? null : _int(j['lastSyncAt']),
    revoked: j['revoked'] == true,
  );

  final String deviceId;
  final String name;
  final String secretHash; // SHA-256 hex of the device secret
  final int pairedAt;
  final int? lastSyncAt;
  final bool revoked;

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'name': name,
    'secretHash': secretHash,
    'pairedAt': pairedAt,
    if (lastSyncAt != null) 'lastSyncAt': lastSyncAt,
    if (revoked) 'revoked': true,
  };

  PairedDevice copyWith({int? lastSyncAt, bool? revoked}) => PairedDevice(
    deviceId: deviceId,
    name: name,
    secretHash: secretHash,
    pairedAt: pairedAt,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    revoked: revoked ?? this.revoked,
  );
}

/// Client side: the one hub this phone is paired with.
class HubPairing {
  const HubPairing({
    required this.serverId,
    required this.serverName,
    required this.host,
    required this.port,
    required this.deviceSecret,
    required this.pairedAt,
    this.lastSyncedRevision = 0,
    this.lastSyncAt,
  });

  factory HubPairing.fromJson(Map<String, dynamic> j) => HubPairing(
    serverId: (j['serverId'] as String?) ?? '',
    serverName: (j['serverName'] as String?) ?? '',
    host: (j['host'] as String?) ?? '',
    port: _int(j['port']),
    deviceSecret: (j['deviceSecret'] as String?) ?? '',
    pairedAt: _int(j['pairedAt']),
    lastSyncedRevision: _int(j['lastSyncedRevision']),
    lastSyncAt: j['lastSyncAt'] == null ? null : _int(j['lastSyncAt']),
  );

  final String serverId;
  final String serverName;
  final String host;
  final int port;
  final String deviceSecret;
  final int pairedAt;

  /// R0: the hub revision this phone has already seen.
  final int lastSyncedRevision;
  final int? lastSyncAt;

  String get baseUrl => 'http://$host:$port';

  Map<String, dynamic> toJson() => {
    'serverId': serverId,
    'serverName': serverName,
    'host': host,
    'port': port,
    'deviceSecret': deviceSecret,
    'pairedAt': pairedAt,
    'lastSyncedRevision': lastSyncedRevision,
    if (lastSyncAt != null) 'lastSyncAt': lastSyncAt,
  };

  HubPairing copyWith({
    String? serverName,
    String? host,
    int? port,
    String? deviceSecret,
    int? lastSyncedRevision,
    int? lastSyncAt,
  }) => HubPairing(
    serverId: serverId,
    serverName: serverName ?? this.serverName,
    host: host ?? this.host,
    port: port ?? this.port,
    deviceSecret: deviceSecret ?? this.deviceSecret,
    pairedAt: pairedAt,
    lastSyncedRevision: lastSyncedRevision ?? this.lastSyncedRevision,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
  );
}

/// Everything sync needs that is not user data. Keys for the other role simply
/// stay absent, so the same class serves the PC and the phone.
class SyncState {
  const SyncState({
    this.serverId,
    this.revision = 0,
    this.devices = const [],
    this.deviceId,
    this.lastServerId,
    this.pairing,
  });

  factory SyncState.fromJson(Map<String, dynamic> j) => SyncState(
    serverId: j['serverId'] as String?,
    revision: _int(j['revision']),
    devices: ((j['pairedDevices'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PairedDevice.fromJson)
        .toList(),
    deviceId: j['deviceId'] as String?,
    lastServerId: j['lastServerId'] as String?,
    pairing: j['pairing'] == null
        ? null
        : HubPairing.fromJson(j['pairing'] as Map<String, dynamic>),
  );

  /// Hub: this hub's identity. Lives in the data file on purpose — resetting
  /// the file gives a new identity, which phones detect as a different hub.
  final String? serverId;

  /// Hub: the global revision counter.
  final int revision;

  /// Hub: phones that have paired.
  final List<PairedDevice> devices;

  /// Client: this device's stable id.
  final String? deviceId;

  /// Client: the hub this phone last synced with, to detect a reset hub.
  final String? lastServerId;

  /// Client: the current pairing, if any.
  final HubPairing? pairing;

  bool get isEmpty =>
      serverId == null &&
      revision == 0 &&
      devices.isEmpty &&
      deviceId == null &&
      lastServerId == null &&
      pairing == null;

  Map<String, dynamic> toJson() => {
    if (serverId != null) 'serverId': serverId,
    if (revision != 0) 'revision': revision,
    if (devices.isNotEmpty)
      'pairedDevices': devices.map((d) => d.toJson()).toList(),
    if (deviceId != null) 'deviceId': deviceId,
    if (lastServerId != null) 'lastServerId': lastServerId,
    if (pairing != null) 'pairing': pairing!.toJson(),
  };

  SyncState copyWith({
    String? serverId,
    int? revision,
    List<PairedDevice>? devices,
    String? deviceId,
    String? lastServerId,
    HubPairing? pairing,
    bool clearPairing = false,
  }) => SyncState(
    serverId: serverId ?? this.serverId,
    revision: revision ?? this.revision,
    devices: devices ?? this.devices,
    deviceId: deviceId ?? this.deviceId,
    lastServerId: lastServerId ?? this.lastServerId,
    pairing: clearPairing ? null : (pairing ?? this.pairing),
  );
}
