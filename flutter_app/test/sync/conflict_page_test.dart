import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savings/main.dart';
import 'package:savings/sync/merge/merge.dart';
import 'package:savings/sync/merge/merge_models.dart';
import 'package:savings/sync/role.dart';
import 'package:savings/sync/ui/conflict_page.dart';
import 'package:savings/theme.dart';
import 'package:savings/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';
import 'merge_test.dart' show local, remote;

/// The conflict screen and the one sync control in the header.

Future<Map<String, ConflictChoice>?> _show(
  WidgetTester tester,
  List<Conflict> conflicts,
) async {
  Map<String, ConflictChoice>? answer;
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: DefaultTextStyle(
      style: body,
      child: Builder(
        builder: (context) => ElevatedButton(
          child: const Text('open'),
          onPressed: () async {
            answer = await Navigator.of(context)
                .push<Map<String, ConflictChoice>>(MaterialPageRoute(
              builder: (context) => ConflictPage(conflicts: conflicts),
            ));
          },
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return answer;
}

List<Conflict> _amountConflict() {
  const base = {
    'type': 'in',
    'title': 'Salary',
    'amount': 1500.0,
    'date': '2026-01-05',
    deletedField: false,
  };
  final plan = planSync(
    locals: [local(values: {...base, 'amount': 1700.0}, dirty: {'amount'})],
    remotes: [
      remote(values: {...base, 'amount': 1600.0}, revs: {'amount': 6}),
    ],
    since: 5,
  );
  return plan.conflicts;
}

void main() {
  testWidgets('Apply only returns once every conflict has an answer',
      (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final conflicts = _amountConflict();
    await _show(tester, conflicts);

    expect(find.text('1 conflict'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    // Both values are on screen, with the phone's first.
    expect(find.textContaining('1.700'), findsOneWidget);
    expect(find.textContaining('1.600'), findsOneWidget);

    // Apply does nothing while no side is picked.
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('1 conflict'), findsOneWidget);

    await tester.tap(find.text('This phone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('1 conflict'), findsNothing);
  });

  testWidgets('Cancel sync comes back with no answers', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _show(tester, _amountConflict());
    await tester.tap(find.text('Cancel sync'));
    await tester.pumpAndSettle();
    expect(find.text('Apply'), findsNothing);
  });

  testWidgets('"Keep all mine" answers every conflict at once', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _show(tester, _amountConflict());
    await tester.tap(find.text('Keep all mine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Amount'), findsNothing);
  });

  testWidgets('the header offers the QR code on a PC and scanning on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});

    Future<void> pump(SyncRole role) async {
      await tester.pumpWidget(SavingsApp(
        store: MemoryStore(sampleData(entries: [sampleEntry(id: 'e1')])),
        role: role,
      ));
      await tester.pumpAndSettle();
    }

    Future<void> openMenu() async {
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
    }

    await pump(SyncRole.hub);
    await openMenu();
    expect(find.text('Sync with a phone'), findsOneWidget);
    expect(find.byType(QrIcon), findsOneWidget);
    await tester.tapAt(Offset.zero); // dismiss the menu
    await tester.pumpAndSettle();

    await pump(SyncRole.client);
    await openMenu();
    expect(find.text('Sync with the PC'), findsOneWidget);
    expect(find.byType(ScanIcon), findsOneWidget);
  });
}
