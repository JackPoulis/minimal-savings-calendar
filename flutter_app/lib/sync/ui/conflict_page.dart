import 'package:flutter/material.dart';

import '../../calc.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../merge/merge_models.dart';

/// Side by side, phone against PC, one row per contested field. Nothing is
/// applied until every conflict has an answer and Apply is pressed; Cancel
/// aborts the whole sync and leaves both devices untouched.
///
/// OFFLINE_FIRST_SYNC_PLAYBOOK.md §8.
class ConflictPage extends StatefulWidget {
  const ConflictPage({super.key, required this.conflicts});

  final List<Conflict> conflicts;

  @override
  State<ConflictPage> createState() => _ConflictPageState();
}

class _ConflictPageState extends State<ConflictPage> {
  final _choices = <String, ConflictChoice>{};

  List<String> get _recordKeys {
    final keys = <String>[];
    for (final c in widget.conflicts) {
      final key = '${c.kind.wire}/${c.id}';
      if (!keys.contains(key)) keys.add(key);
    }
    return keys;
  }

  List<Conflict> _inRecord(String recordKey) => [
    for (final c in widget.conflicts)
      if ('${c.kind.wire}/${c.id}' == recordKey) c,
  ];

  bool get _complete =>
      widget.conflicts.every((c) => _choices.containsKey(c.key));

  void _pickAll(List<Conflict> conflicts, bool mine) => setState(() {
    for (final c in conflicts) {
      _choices[c.key] = mine ? c.phoneSide : c.pcSide;
    }
  });

  @override
  Widget build(BuildContext context) {
    final count = widget.conflicts.length;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count == 1 ? '1 conflict' : '$count conflicts',
                    style: h1,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Both devices changed the same thing. Pick which one to '
                    'keep.',
                    style: TextStyle(color: C.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  // Wrap, not Row: the two labels do not fit side by side on
                  // a narrow phone.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AppButton(
                        onPressed: () => _pickAll(widget.conflicts, true),
                        child: const Text('Keep all mine'),
                      ),
                      AppButton(
                        onPressed: () => _pickAll(widget.conflicts, false),
                        child: const Text("Keep all PC's"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                children: [
                  for (final key in _recordKeys) ...[
                    _record(key),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
                  AppButton(
                    danger: true,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel sync'),
                  ),
                  Opacity(
                    opacity: _complete ? 1 : 0.4,
                    child: AppButton(
                      primary: true,
                      onPressed: _complete
                          ? () => Navigator.of(context)
                                .pop(Map<String, ConflictChoice>.of(_choices))
                          : null,
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _record(String recordKey) {
    final conflicts = _inRecord(recordKey);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  recordTitle(conflicts.first),
                  style: h2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppButton(
                onPressed: () => _pickAll(conflicts, true),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: const Text('Mine', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 6),
              AppButton(
                onPressed: () => _pickAll(conflicts, false),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: const Text("PC's", style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final conflict in conflicts) ...[
            _conflict(conflict),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _conflict(Conflict conflict) {
    final chosen = _choices[conflict.key];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(conflictLabel(conflict), style: h3),
        const SizedBox(height: 6),
        // IntrinsicHeight so the two cards match in height inside a list,
        // where stretching alone has no height to stretch to.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _side(
                  label:
                      conflict is DeleteEditConflict && conflict.deletedOnPhone
                      ? 'Delete it'
                      : 'This phone',
                  value: phoneText(conflict),
                  at: phoneAt(conflict),
                  selected: chosen == conflict.phoneSide,
                  onTap: () => setState(
                    () => _choices[conflict.key] = conflict.phoneSide,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _side(
                  label:
                      conflict is DeleteEditConflict && !conflict.deletedOnPhone
                      ? 'Delete it'
                      : 'The PC',
                  value: pcText(conflict),
                  at: pcAt(conflict),
                  selected: chosen == conflict.pcSide,
                  onTap: () =>
                      setState(() => _choices[conflict.key] = conflict.pcSide),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _side({
    required String label,
    required String value,
    required int at,
    required bool selected,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: selected ? C.inBg : C.bg,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: selected ? C.accent : C.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelStyle),
          const SizedBox(height: 2),
          Text(value, style: mono),
          if (at > 0) ...[
            const SizedBox(height: 2),
            Text(
              'edited ${editedAt(at)}',
              style: const TextStyle(color: C.muted, fontSize: 11),
            ),
          ],
        ],
      ),
    ),
  );
}

// ------------------------------------------------------------------- labelling

const _fieldLabels = {
  'type': 'Direction',
  'title': 'Title',
  'amount': 'Amount',
  'date': 'Date',
  deletedField: 'Deleted',
  'startDate': 'Start date',
  'endDate': 'End date',
  'goal': 'Target',
  'loanAmount': 'Max loan',
  'apr': 'APR',
  'loanYears': 'Years',
};

String conflictLabel(Conflict conflict) => switch (conflict) {
  FieldConflict() => _fieldLabels[conflict.field] ?? conflict.field,
  DeleteEditConflict() =>
    conflict.deletedOnPhone
        ? 'Deleted here, changed on the PC'
        : 'Changed here, deleted on the PC',
};

String recordTitle(Conflict conflict) {
  if (conflict.kind == settingsKind) return 'Settings';
  if (conflict.kind == forecastKind) {
    final title = switch (conflict) {
      FieldConflict() => null,
      DeleteEditConflict() => conflict.local.value('title'),
    };
    return title is String && title.isNotEmpty
        ? 'Monthly · $title'
        : 'Monthly entry';
  }
  final values = switch (conflict) {
    FieldConflict() => null,
    DeleteEditConflict() => conflict.local,
  };
  final title = values?.value('title');
  final date = values?.value('date');
  if (title is String && date is String) {
    return '${shortDate(date)} · ${title.isEmpty ? 'Entry' : title}';
  }
  return 'Entry';
}

String fieldText(String field, Object? value) {
  if (value == null) return '—';
  return switch (field) {
    'amount' || 'goal' || 'loanAmount' => eur((value as num).toDouble()),
    'apr' => '$value%',
    'type' => value == 'in' ? 'Money in' : 'Money out',
    'date' || 'startDate' || 'endDate' => shortDate(value as String),
    deletedField => value == true ? 'Deleted' : 'Kept',
    _ => '$value',
  };
}

String phoneText(Conflict conflict) => switch (conflict) {
  FieldConflict() => fieldText(conflict.field, conflict.local.value),
  DeleteEditConflict() =>
    conflict.deletedOnPhone ? 'Delete it' : _summary(conflict, phone: true),
};

String pcText(Conflict conflict) => switch (conflict) {
  FieldConflict() => fieldText(conflict.field, conflict.remote.value),
  DeleteEditConflict() =>
    conflict.deletedOnPhone ? _summary(conflict, phone: false) : 'Delete it',
};

/// The edited version of a record that the other side deleted.
String _summary(DeleteEditConflict conflict, {required bool phone}) {
  Object? value(String field) =>
      phone ? conflict.local.value(field) : conflict.remote.value(field);
  final title = value('title');
  final amount = value('amount');
  return 'Keep "${title is String && title.isNotEmpty ? title : 'entry'}" '
          '${amount is num ? eur(amount.toDouble()) : ''}'
      .trim();
}

int phoneAt(Conflict conflict) => switch (conflict) {
  FieldConflict() => conflict.local.at,
  DeleteEditConflict() =>
    conflict.local.fields.values
        .map((f) => f.at)
        .fold(0, (a, b) => a > b ? a : b),
};

int pcAt(Conflict conflict) => switch (conflict) {
  FieldConflict() => conflict.remote.at,
  DeleteEditConflict() =>
    conflict.remote.fields.values
        .map((f) => f.at)
        .fold(0, (a, b) => a > b ? a : b),
};

/// The only place an edit time is used, and only to show it.
String editedAt(int millis) {
  final at = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
  final now = DateTime.now();
  final time =
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
  final sameDay =
      at.year == now.year && at.month == now.month && at.day == now.day;
  return sameDay ? time : '${shortDate(iso(at))} $time';
}
