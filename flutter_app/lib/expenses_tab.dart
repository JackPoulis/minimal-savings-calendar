import 'package:flutter/material.dart';

import 'app_page.dart' show narrowWidth;
import 'calc.dart';
import 'forecast_dialog.dart';
import 'model.dart';
import 'theme.dart';
import 'widgets.dart';

/// The monthly forecast: what comes in and goes out every month, and what is
/// left at the end of it. The tab itself never scrolls, only the list does.
class ExpensesTab extends StatelessWidget {
  const ExpensesTab({
    super.key,
    required this.forecasts,
    required this.onSave,
    required this.onDelete,
  });

  final List<Forecast> forecasts;
  final void Function(Forecast forecast, Forecast? base) onSave;
  final void Function(String id) onDelete;

  Future<void> _confirmRemove(BuildContext context, Forecast f) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x8C000000),
      builder: (context) => AlertDialog(
        backgroundColor: C.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: C.dialogBorder),
        ),
        content: Text('Remove "${f.title}"?', style: body),
        actions: [
          AppButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          AppButton(
            danger: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok ?? false) onDelete(f.id);
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < narrowWidth;
    final sorted = sortForecasts(forecasts);
    final totals = forecastTotals(forecasts);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Remaining(totals: totals),
          const SizedBox(height: 12),
          Panel(
            flex: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: sorted.isEmpty
                      ? const Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            'No entries yet.',
                            style: TextStyle(color: C.muted, fontSize: 14),
                          ),
                        )
                      : ListView.separated(
                          itemCount: sorted.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 4),
                          itemBuilder: (context, i) =>
                              _row(context, sorted[i], narrow),
                        ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x80000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: AppButton(
                      onPressed: () =>
                          showForecastDialog(context: context, onSave: onSave),
                      tooltip: 'Add entry',
                      borderRadius: 22,
                      padding: EdgeInsets.zero,
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(child: PlusIcon()),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, Forecast f, bool narrow) {
    final color = f.type == 'in' ? C.green : C.red;
    return Row(
      children: [
        Expanded(
          child: AppButton(
            onPressed: () => showForecastDialog(
              context: context,
              existing: f,
              onSave: onSave,
            ),
            tooltip: 'Edit entry',
            background: C.bg,
            hoverBackground: C.rowHover,
            padding: EdgeInsets.all(narrow ? 8 : 10)
                .copyWith(top: 8, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    f.title,
                    maxLines: narrow ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: body.copyWith(
                      color: color,
                      height: narrow ? 1.25 : 1.4,
                    ),
                  ),
                ),
                SizedBox(width: narrow ? 8 : 12),
                Text(
                  '${f.type == 'in' ? '+' : '−'}${eur(f.amount)}',
                  style: mono.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        AppButton(
          onPressed: () => _confirmRemove(context, f),
          tooltip: 'Remove ${f.title}',
          foreground: C.red,
          hoverForeground: C.red,
          hoverBackground: C.dangerBg,
          borderRadius: 14,
          padding: EdgeInsets.zero,
          child: const SizedBox(
            width: 28,
            height: 28,
            child: Center(child: MinusIcon()),
          ),
        ),
      ],
    );
  }
}

/// The hero figure: income minus expenses, green when positive, red when
/// negative.
class _Remaining extends StatelessWidget {
  const _Remaining({required this.totals});

  final ({double income, double expenses, double left}) totals;

  @override
  Widget build(BuildContext context) {
    final left = totals.left;
    final color = left > 0 ? C.green : (left < 0 ? C.red : C.text);
    final sign = left > 0 ? '+' : (left < 0 ? '−' : '');
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('LEFT AT END OF MONTH', style: h3),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$sign${eur(left.abs())}',
              key: const Key('forecast-left'),
              style: monoBig.copyWith(
                color: color,
                fontSize: 34,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Income ${eur(totals.income)}  ·  Expenses ${eur(totals.expenses)}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: C.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
