import 'calc.dart';
import 'sync/doc.dart';

/// Whole numbers are written back as ints so the saved file keeps the shape it
/// had (1500, not 1500.0).
num _trim(double v) => v == v.roundToDouble() ? v.toInt() : v;

double _num(Object? v) => v is num ? v.toDouble() : 0;

class Entry {
  const Entry({
    required this.id,
    required this.type,
    required this.title,
    required this.amount,
    required this.date,
    this.deleted = false,
    this.meta = const RecordMeta.unset(),
  });

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
    id: j['id'] as String,
    type: j['type'] == 'out' ? 'out' : 'in',
    title: (j['title'] as String?) ?? '',
    amount: _num(j['amount']),
    date: j['date'] as String,
    deleted: j['deleted'] == true,
    meta: j['meta'] == null
        ? const RecordMeta.unset()
        : RecordMeta.fromJson(j['meta'] as Map<String, dynamic>),
  );

  final String id;
  final String type; // 'in' | 'out'
  final String title;
  final double amount;
  final String date; // yyyy-MM-dd

  /// Tombstone. A deleted entry stays in the file so the deletion can sync;
  /// it is hidden everywhere in the app (see [SavingsData.liveEntries]).
  final bool deleted;

  /// Sync bookkeeping. The UI builds entries without it and the sync
  /// repository stamps it.
  final RecordMeta meta;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'amount': _trim(amount),
    'date': date,
    if (deleted) 'deleted': true,
    if (!meta.isEmpty) 'meta': meta.toJson(),
  };

  Entry copyWith({
    String? type,
    String? title,
    double? amount,
    String? date,
    bool? deleted,
    RecordMeta? meta,
  }) => Entry(
    id: id,
    type: type ?? this.type,
    title: title ?? this.title,
    amount: amount ?? this.amount,
    date: date ?? this.date,
    deleted: deleted ?? this.deleted,
    meta: meta ?? this.meta,
  );
}

/// One line of the monthly forecast: an amount that comes in or goes out every
/// month. It has no date and does not touch the savings figures.
class Forecast {
  const Forecast({
    required this.id,
    required this.type,
    required this.title,
    required this.amount,
    this.deleted = false,
    this.meta = const RecordMeta.unset(),
  });

  factory Forecast.fromJson(Map<String, dynamic> j) => Forecast(
    id: j['id'] as String,
    type: j['type'] == 'out' ? 'out' : 'in',
    title: (j['title'] as String?) ?? '',
    amount: _num(j['amount']),
    deleted: j['deleted'] == true,
    meta: j['meta'] == null
        ? const RecordMeta.unset()
        : RecordMeta.fromJson(j['meta'] as Map<String, dynamic>),
  );

  final String id;
  final String type; // 'in' | 'out'
  final String title;
  final double amount;

  /// Tombstone, like [Entry.deleted].
  final bool deleted;

  /// Sync bookkeeping, stamped by the sync repository.
  final RecordMeta meta;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'amount': _trim(amount),
    if (deleted) 'deleted': true,
    if (!meta.isEmpty) 'meta': meta.toJson(),
  };

  Forecast copyWith({
    String? type,
    String? title,
    double? amount,
    bool? deleted,
    RecordMeta? meta,
  }) => Forecast(
    id: id,
    type: type ?? this.type,
    title: title ?? this.title,
    amount: amount ?? this.amount,
    deleted: deleted ?? this.deleted,
    meta: meta ?? this.meta,
  );
}

class SavingsData {
  const SavingsData({
    required this.startDate,
    required this.endDate,
    required this.goal,
    required this.loanAmount,
    required this.apr,
    required this.loanYears,
    required this.entries,
    this.forecasts = const [],
    this.settingsMeta = const RecordMeta.unset(),
    this.sync = const SyncState(),
  });

  /// The defaults used when data.json is missing.
  factory SavingsData.defaults() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month + 6, now.day);
    return SavingsData(
      startDate: iso(now),
      endDate: iso(end),
      goal: 0,
      loanAmount: 0,
      apr: 0,
      loanYears: 5,
      entries: const [],
    );
  }

  factory SavingsData.fromJson(Map<String, dynamic> j) {
    final fallback = SavingsData.defaults();
    return SavingsData(
      startDate: (j['startDate'] as String?) ?? fallback.startDate,
      endDate: (j['endDate'] as String?) ?? fallback.endDate,
      goal: _num(j['goal']),
      loanAmount: _num(j['loanAmount']),
      apr: _num(j['apr']),
      loanYears: (j['loanYears'] as num?)?.toInt() ?? 5,
      entries: ((j['entries'] as List?) ?? const [])
          .map((e) => Entry.fromJson(e as Map<String, dynamic>))
          .toList(),
      forecasts: ((j['forecasts'] as List?) ?? const [])
          .map((e) => Forecast.fromJson(e as Map<String, dynamic>))
          .toList(),
      settingsMeta: j['settingsMeta'] == null
          ? const RecordMeta.unset()
          : RecordMeta.fromJson(j['settingsMeta'] as Map<String, dynamic>),
      sync: j['sync'] == null
          ? const SyncState()
          : SyncState.fromJson(j['sync'] as Map<String, dynamic>),
    );
  }

  final String startDate;
  final String endDate;
  final double goal;
  final double loanAmount;
  final double apr;
  final int loanYears;

  /// Every entry, tombstones included. Read [liveEntries] for display.
  final List<Entry> entries;

  /// Every monthly forecast line, tombstones included. Read [liveForecasts].
  final List<Forecast> forecasts;

  /// Change tracking for the settings, which sync as one record.
  final RecordMeta settingsMeta;

  /// Pairing and revision bookkeeping.
  final SyncState sync;

  /// The entries the user still has — what the whole UI reads.
  List<Entry> get liveEntries => [
    for (final e in entries)
      if (!e.deleted) e,
  ];

  /// The forecast lines the user still has.
  List<Forecast> get liveForecasts => [
    for (final f in forecasts)
      if (!f.deleted) f,
  ];

  Map<String, dynamic> toJson() => {
    'startDate': startDate,
    'endDate': endDate,
    'goal': _trim(goal),
    'loanAmount': _trim(loanAmount),
    'apr': _trim(apr),
    'loanYears': loanYears,
    'entries': entries.map((e) => e.toJson()).toList(),
    if (forecasts.isNotEmpty)
      'forecasts': forecasts.map((f) => f.toJson()).toList(),
    if (!settingsMeta.isEmpty) 'settingsMeta': settingsMeta.toJson(),
    if (!sync.isEmpty) 'sync': sync.toJson(),
  };

  SavingsData copyWith({
    String? startDate,
    String? endDate,
    double? goal,
    double? loanAmount,
    double? apr,
    int? loanYears,
    List<Entry>? entries,
    List<Forecast>? forecasts,
    RecordMeta? settingsMeta,
    SyncState? sync,
  }) => SavingsData(
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    goal: goal ?? this.goal,
    loanAmount: loanAmount ?? this.loanAmount,
    apr: apr ?? this.apr,
    loanYears: loanYears ?? this.loanYears,
    entries: entries ?? this.entries,
    forecasts: forecasts ?? this.forecasts,
    settingsMeta: settingsMeta ?? this.settingsMeta,
    sync: sync ?? this.sync,
  );
}
