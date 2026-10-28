import 'package:flutter/material.dart';

import 'calc.dart';
import 'model.dart';
import 'theme.dart';
import 'widgets.dart';

class EntryListView extends StatelessWidget {
  const EntryListView({
    super.key,
    required this.entries,
    required this.today,
    required this.onPick,
    required this.onDelete,
    required this.onAdd,
  });

  final List<Entry> entries;
  final String today;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onDelete;
  final VoidCallback onAdd;

  Future<void> _confirmRemove(BuildContext context, Entry e) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x8C000000),
      builder: (context) => AlertDialog(
        backgroundColor: C.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: C.dialogBorder),
        ),
        content: Text('Remove "${e.title}"?', style: body),
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
    if (ok ?? false) onDelete(e.id);
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));
    final narrow = MediaQuery.sizeOf(context).width < 600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sorted.isEmpty)
          const SizedBox(
            height: 60,
            child: Text(
              'No entries yet.',
              style: TextStyle(color: C.muted, fontSize: 14),
            ),
          ),
        Expanded(
          child: ListView.separated(
            itemCount: sorted.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, i) {
              final e = sorted[i];
              final past = e.date.compareTo(today) <= 0;
              return Opacity(
                opacity: past ? 0.6 : 1,
                child: Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        onPressed: () => onPick(e.date),
                        tooltip: 'Edit this day',
                        background: C.bg,
                        hoverBackground: C.rowHover,
                        padding: EdgeInsets.all(narrow ? 8 : 10)
                            .copyWith(top: 8, bottom: 8),
                        child: Row(
                          children: [
                            Text(
                              shortDate(e.date),
                              style: mono.copyWith(
                                color: C.muted,
                                fontSize: 12,
                              ),
                            ),
                            SizedBox(width: narrow ? 8 : 12),
                            Expanded(
                              child: Text(
                                e.title,
                                // Long titles wrap on phones instead of
                                // being cut off.
                                maxLines: narrow ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: body.copyWith(
                                  height: narrow ? 1.25 : 1.4,
                                ),
                              ),
                            ),
                            SizedBox(width: narrow ? 8 : 12),
                            Text(
                              '${e.type == 'in' ? '+' : '−'}${eur(e.amount)}',
                              style: mono.copyWith(
                                color: e.type == 'in' ? C.green : C.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      onPressed: () => _confirmRemove(context, e),
                      tooltip: 'Remove ${e.title}',
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
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // Bottom-right, below the list so it never covers a row.
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
              onPressed: onAdd,
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
    );
  }
}
