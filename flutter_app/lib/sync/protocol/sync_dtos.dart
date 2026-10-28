/// Pull/push payloads. These check shape only; the per-field type checks live
/// in `codec.dart`, which knows what each field holds.
///
/// OFFLINE_FIRST_SYNC_PLAYBOOK.md §4.
library;

class WireField {
  const WireField({required this.value, required this.at, this.rev});

  factory WireField.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('A field must be an object');
    if (!raw.containsKey('value')) {
      throw const FormatException('A field needs a "value"');
    }
    final at = raw['at'];
    final rev = raw['rev'];
    if (at != null && at is! num) {
      throw const FormatException('A field\'s "at" must be a number');
    }
    if (rev != null && rev is! num) {
      throw const FormatException('A field\'s "rev" must be a number');
    }
    return WireField(
      value: raw['value'],
      at: (at as num?)?.toInt() ?? 0,
      rev: (rev as num?)?.toInt(),
    );
  }

  final Object? value;

  /// UTC ms of the last edit. Display only.
  final int at;

  /// The hub revision at which the field changed. Present in pulls, absent in
  /// pushes.
  final int? rev;

  Map<String, dynamic> toJson() => {
    'value': value,
    'at': at,
    if (rev != null) 'rev': rev,
  };
}

class WireRecord {
  const WireRecord({
    required this.type,
    required this.id,
    required this.createdAt,
    required this.fields,
  });

  factory WireRecord.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('A record must be an object');
    final type = raw['type'];
    final id = raw['id'];
    final createdAt = raw['createdAt'];
    if (type is! String || type.isEmpty) {
      throw const FormatException('A record needs a "type"');
    }
    if (id is! String || id.isEmpty) {
      throw const FormatException('A record needs an "id"');
    }
    if (createdAt != null && createdAt is! num) {
      throw const FormatException('A record\'s "createdAt" must be a number');
    }
    final fields = raw['fields'];
    if (fields is! Map) {
      throw const FormatException('A record needs a "fields" object');
    }
    return WireRecord(
      type: type,
      id: id,
      createdAt: (createdAt as num?)?.toInt() ?? 0,
      fields: {
        for (final e in fields.entries) '${e.key}': WireField.fromJson(e.value),
      },
    );
  }

  final String type;
  final String id;
  final int createdAt;
  final Map<String, WireField> fields;

  Map<String, dynamic> toJson() => {
    'type': type,
    'id': id,
    'createdAt': createdAt,
    'fields': {for (final e in fields.entries) e.key: e.value.toJson()},
  };
}

class PullRequest {
  const PullRequest(this.since);

  factory PullRequest.fromJson(Map<String, dynamic> j) {
    final since = j['since'];
    if (since is! num) throw const FormatException('"since" must be a number');
    return PullRequest(since.toInt());
  }

  final int since;

  Map<String, dynamic> toJson() => {'since': since};
}

class PullResponse {
  const PullResponse({required this.revision, required this.records});

  factory PullResponse.fromJson(Map<String, dynamic> j) {
    final revision = j['revision'];
    final records = j['records'];
    if (revision is! num) {
      throw const FormatException('"revision" must be a number');
    }
    if (records is! List) {
      throw const FormatException('"records" must be a list');
    }
    return PullResponse(
      revision: revision.toInt(),
      records: records.map(WireRecord.fromJson).toList(),
    );
  }

  final int revision;
  final List<WireRecord> records;

  Map<String, dynamic> toJson() => {
    'revision': revision,
    'records': records.map((r) => r.toJson()).toList(),
  };
}

class PushRequest {
  const PushRequest({required this.baseRevision, required this.changes});

  factory PushRequest.fromJson(Map<String, dynamic> j) {
    final base = j['baseRevision'];
    final changes = j['changes'];
    if (base is! num) {
      throw const FormatException('"baseRevision" must be a number');
    }
    if (changes is! List) {
      throw const FormatException('"changes" must be a list');
    }
    return PushRequest(
      baseRevision: base.toInt(),
      changes: changes.map(WireRecord.fromJson).toList(),
    );
  }

  final int baseRevision;
  final List<WireRecord> changes;

  Map<String, dynamic> toJson() => {
    'baseRevision': baseRevision,
    'changes': changes.map((r) => r.toJson()).toList(),
  };
}

class PushResponse {
  const PushResponse(this.revision);

  factory PushResponse.fromJson(Map<String, dynamic> j) {
    final revision = j['revision'];
    if (revision is! num) {
      throw const FormatException('"revision" must be a number');
    }
    return PushResponse(revision.toInt());
  }

  final int revision;

  Map<String, dynamic> toJson() => {'revision': revision};
}
