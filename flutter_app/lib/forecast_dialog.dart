import 'package:flutter/material.dart';

import 'app_page.dart' show narrowWidth;
import 'day_dialog.dart' show newEntryId;
import 'model.dart';
import 'theme.dart';
import 'widgets.dart';

/// Adds a monthly forecast line, or edits [existing]: a centred dialog on wide
/// windows, a bottom sheet on phones, like the day dialog.
Future<void> showForecastDialog({
  required BuildContext context,
  Forecast? existing,
  required void Function(Forecast forecast, Forecast? base) onSave,
}) {
  final narrow = MediaQuery.sizeOf(context).width < narrowWidth;
  final body = _ForecastDialogBody(existing: existing, onSave: onSave);

  if (narrow) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.panel,
      barrierColor: const Color(0x8C000000),
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

class _ForecastDialogBody extends StatefulWidget {
  const _ForecastDialogBody({required this.existing, required this.onSave});

  final Forecast? existing;

  /// [base] is the line as the editor opened it, so only the fields the user
  /// touched are written.
  final void Function(Forecast forecast, Forecast? base) onSave;

  @override
  State<_ForecastDialogBody> createState() => _ForecastDialogBodyState();
}

class _ForecastDialogBodyState extends State<_ForecastDialogBody> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _amount = TextEditingController(text: _initialAmount());
  late String _type = widget.existing?.type ?? 'in';

  String _initialAmount() {
    final a = widget.existing?.amount;
    if (a == null) return '';
    return a == a.roundToDouble() ? '${a.toInt()}' : '$a';
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final amount =
        double.tryParse(_amount.text.replaceAll(',', '.'))?.abs() ?? 0;
    if (amount == 0) return;
    final forecast = Forecast(
      id: widget.existing?.id ?? newEntryId(),
      type: _type,
      title: _title.text.trim().isEmpty
          ? (_type == 'in' ? 'Income' : 'Expense')
          : _title.text.trim(),
      amount: amount,
    );
    widget.onSave(forecast, widget.existing);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(editing ? 'EDIT ENTRY' : 'ADD ENTRY', style: h3),
              ),
              AppButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
                child: const Text('✕'),
              ),
            ],
          ),
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
                  child: const Center(child: Text('+ Income')),
                ),
              ),
              Expanded(
                child: AppButton(
                  onPressed: () => setState(() => _type = 'out'),
                  borderRadius: 0,
                  background: _type == 'out' ? C.dangerBg : C.button,
                  foreground: _type == 'out' ? C.red : C.text,
                  hoverBackground: _type == 'out' ? C.dangerBg : C.buttonHover,
                  child: const Center(child: Text('− Expense')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Labeled(
            label: 'Description',
            child: TextField(
              controller: _title,
              style: body,
              decoration: fieldDecoration(
                hint: _type == 'in' ? 'e.g. Salary' : 'e.g. Rent',
              ),
            ),
          ),
          const SizedBox(height: 10),
          Labeled(
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
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (editing) ...[
                AppButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
              ],
              AppButton(
                primary: true,
                onPressed: _submit,
                child: Text(editing ? 'Save' : 'Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
