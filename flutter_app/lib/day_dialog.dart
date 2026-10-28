import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_page.dart' show narrowWidth;
import 'calc.dart';
import 'model.dart';
import 'theme.dart';
import 'widgets.dart';

String newEntryId() {
  final rnd = math.Random();
  String hex(int n) =>
      List.generate(n, (_) => rnd.nextInt(16).toRadixString(16)).join();
  // RFC 4122 v4 layout, so ids look like the ones already in the file.
  final variant = (8 + rnd.nextInt(4)).toRadixString(16);
  return '${hex(8)}-${hex(4)}-4${hex(3)}-$variant${hex(3)}-${hex(12)}';
}

/// Opens the day's entries: a centred dialog on wide windows, a bottom sheet
/// on phones, matching the 600px breakpoint.
Future<void> showDayDialog({
  required BuildContext context,
  required String day,
  required List<Entry> Function() entries,
  required void Function(Entry entry, Entry? base) onSave,
  required void Function(String) onDelete,
}) {
  final narrow = MediaQuery.sizeOf(context).width < narrowWidth;
  final body = _DayDialogBody(
    day: day,
    entries: entries,
    onSave: onSave,
    onDelete: onDelete,
  );

  if (narrow) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.panel,
      barrierColor: const Color(0x8C000000), // rgba(0,0,0,.55)
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        side: BorderSide(color: C.dialogBorder),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: body,
      ),
    );
  }

  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x8C000000),
    builder: (context) => Dialog(
      backgroundColor: C.panel,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: C.dialogBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: body,
      ),
    ),
  );
}

class _DayDialogBody extends StatefulWidget {
  const _DayDialogBody({
    required this.day,
    required this.entries,
    required this.onSave,
    required this.onDelete,
  });

  final String day;
  final List<Entry> Function() entries;

  /// [base] is the entry as the editor opened it, so a save that happened
  /// after a sync only writes the fields the user actually touched.
  final void Function(Entry entry, Entry? base) onSave;
  final void Function(String) onDelete;

  @override
  State<_DayDialogBody> createState() => _DayDialogBodyState();
}

class _DayDialogBodyState extends State<_DayDialogBody> {
  final _title = TextEditingController();
  final _amount = TextEditingController();

  String? _editingId;
  String _type = 'in';
  late String _date = widget.day;

  // The dialog edits the live list, so it keeps its own copy in step.
  late List<Entry> _all = widget.entries();

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  List<Entry> get _list => _all.where((e) => e.date == widget.day).toList();

  void _blank() {
    setState(() {
      _editingId = null;
      _type = 'in';
      _date = widget.day;
      _title.clear();
      _amount.clear();
    });
  }

  void _edit(Entry e) {
    setState(() {
      _editingId = e.id;
      _type = e.type;
      _date = e.date;
      _title.text = e.title;
      _amount.text = e.amount == e.amount.roundToDouble()
          ? '${e.amount.toInt()}'
          : '${e.amount}';
    });
  }

  void _submit() {
    final amount =
        double.tryParse(_amount.text.replaceAll(',', '.'))?.abs() ?? 0;
    if (amount == 0) return;
    final entry = Entry(
      id: _editingId ?? newEntryId(),
      type: _type,
      title: _title.text.trim().isEmpty
          ? (_type == 'in' ? 'Input' : 'Output')
          : _title.text.trim(),
      amount: amount,
      date: _date,
    );
    widget.onSave(entry, _original(entry.id));
    setState(() {
      _all = [
        for (final e in _all)
          if (e.id == entry.id) entry else e,
        if (!_all.any((e) => e.id == entry.id)) entry,
      ];
    });
    _blank();
  }

  Entry? _original(String id) {
    for (final e in _all) {
      if (e.id == id) return e;
    }
    return null;
  }

  void _delete(String id) {
    widget.onDelete(id);
    setState(() {
      _all = _all.where((e) => e.id != id).toList();
      if (_editingId == id) _editingId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(longDate(widget.day), style: h2)),
              AppButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
                child: const Text('✕'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            const Text(
              'No entries on this day.',
              style: TextStyle(color: C.muted, fontSize: 14),
            ),
          for (final e in list) ...[_entryRow(e), const SizedBox(height: 4)],
          const SizedBox(height: 8),
          const Divider(height: 1, color: C.border),
          const SizedBox(height: 12),
          _form(),
        ],
      ),
    );
  }

  Widget _entryRow(Entry e) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: C.bg,
      borderRadius: BorderRadius.circular(2),
      border: Border.all(
        color: _editingId == e.id ? C.accent : Colors.transparent,
      ),
    ),
    child: Row(
      children: [
        Text(
          '${e.type == 'in' ? '+' : '−'}${eur(e.amount)}',
          style: mono.copyWith(color: e.type == 'in' ? C.green : C.red),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(e.title, overflow: TextOverflow.ellipsis, style: body),
        ),
        const SizedBox(width: 8),
        AppButton(
          onPressed: () => _edit(e),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: const Text('Edit', style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 8),
        AppButton(
          danger: true,
          onPressed: () => _delete(e.id),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: const Text('Delete', style: TextStyle(fontSize: 12)),
        ),
      ],
    ),
  );

  Widget _form() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(_editingId == null ? 'ADD ENTRY' : 'EDIT ENTRY', style: h3),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: AppButton(
              onPressed: () => setState(() => _type = 'in'),
              borderRadius: 0,
              background: _type == 'in' ? C.inBg : C.button,
              foreground: _type == 'in' ? C.green : C.text,
              hoverBackground: _type == 'in' ? C.inBg : C.buttonHover,
              child: const Center(child: Text('+ Input')),
            ),
          ),
          Expanded(
            child: AppButton(
              onPressed: () => setState(() => _type = 'out'),
              borderRadius: 0,
              background: _type == 'out' ? C.dangerBg : C.button,
              foreground: _type == 'out' ? C.red : C.text,
              hoverBackground: _type == 'out' ? C.dangerBg : C.buttonHover,
              child: const Center(child: Text('− Output')),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Labeled(
        label: 'Title',
        child: TextField(
          controller: _title,
          style: body,
          decoration: fieldDecoration(
            hint: _type == 'in' ? 'e.g. Salary' : 'e.g. Insurance',
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Labeled(
              label: 'Amount (€)',
              child: TextField(
                controller: _amount,
                style: body,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onSubmitted: (_) => _submit(),
                decoration: fieldDecoration(hint: '0,00'),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Labeled(
            label: 'Date',
            child: DateField(
              value: _date,
              onChanged: (v) => setState(() => _date = v),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_editingId != null) ...[
            AppButton(onPressed: _blank, child: const Text('Cancel')),
            const SizedBox(width: 12),
          ],
          AppButton(
            primary: true,
            onPressed: _submit,
            child: Text(_editingId == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    ],
  );
}
