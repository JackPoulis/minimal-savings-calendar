import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savings/calc.dart';
import 'package:savings/main.dart';
import 'package:savings/model.dart';
import 'package:savings/theme.dart';
import 'package:savings/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the data in memory so the widget tests never touch the real file.
class FakeStore extends Store {
  FakeStore(this.data);

  SavingsData data;
  int saves = 0;

  @override
  Future<SavingsData> load() async => data;

  @override
  Future<void> save(SavingsData next) async {
    data = next;
    saves++;
  }
}

SavingsData _storedData() {
  final seed = File('assets/seed_data.json').existsSync()
      ? File('assets/seed_data.json')
      : File('assets/seed_data.example.json');
  return SavingsData.fromJson(
    jsonDecode(seed.readAsStringSync()) as Map<String, dynamic>,
  );
}

Future<FakeStore> _pump(WidgetTester tester, SavingsData data) async {
  SharedPreferences.setMockInitialValues({});
  final store = FakeStore(data);
  await tester.pumpWidget(SavingsApp(store: store));
  await tester.pumpAndSettle();
  return store;
}

void main() {
  _tabTests();

  // A fixed "today" is not injectable, so these use dates far in the past so
  // every entry counts as already banked.
  final past = SavingsData(
    startDate: '2020-01-01',
    endDate: '2020-03-31',
    goal: 1000,
    loanAmount: 14000,
    apr: 1.9,
    loanYears: 4,
    entries: const [
      Entry(id: 'a', type: 'in', title: 'Salary', amount: 400, date: '2020-01-10'),
      Entry(id: 'b', type: 'out', title: 'Insurance', amount: 100, date: '2020-02-10'),
    ],
  );

  testWidgets('renders the three panels with the computed figures',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(tester, past);

    expect(find.text('Savings'), findsOneWidget);
    expect(find.text('Goal'), findsOneWidget);
    expect(find.text('Loan'), findsNothing); // it lives on the Loan tab

    // 400 in, 100 out, both in the past.
    expect(find.text('300,00 €'), findsOneWidget); // Today
    expect(find.text('Have 300,00 €'), findsOneWidget);
    expect(find.text('Remaining 700,00 €'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.calculate_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Loan'), findsOneWidget);

    // monthlyPayment(14000, 1.9, 4) = 303.12…
    expect(find.text('303,12 €'), findsOneWidget);
    // 303.1211… × 48 − 14000 = 549.81
    expect(find.text('549,81 €'), findsOneWidget);
  });

  testWidgets('draws the goal bar with its three segments', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(tester, past);

    // 300 of a 1000 goal banked, nothing else due before the end date.
    final segments = tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .where((b) => const [C.green, C.barGray, C.red].contains(b.color))
        .toList();
    expect(segments.length, 3);

    for (final color in const [C.green, C.red]) {
      final box = tester.renderObject<RenderBox>(
        find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == color,
        ),
      );
      expect(box.size.height, 18, reason: 'the $color segment has no height');
      expect(box.size.width, greaterThan(0));
    }
  });

  testWidgets('toggles between the graph and the list, and remembers it',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(tester, past);

    // The graph is the default; entry titles only show in the list.
    expect(find.text('Salary'), findsNothing);

    await tester.tap(find.byTooltip('Show list'));
    await tester.pumpAndSettle();
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('Insurance'), findsOneWidget);
    expect(find.text('10/01/20'), findsOneWidget);

    expect(
      (await SharedPreferences.getInstance()).getString('view'),
      'list',
    );

    await tester.tap(find.byTooltip('Show graph'));
    await tester.pumpAndSettle();
    expect(find.text('Salary'), findsNothing);
  });

  testWidgets('adds an entry through the day dialog and saves it',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = await _pump(tester, past);

    await tester.tap(find.byTooltip('Show list'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add entry'));
    await tester.pumpAndSettle();

    expect(find.text('ADD ENTRY'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'e.g. Salary'), 'Bonus');
    await tester.enterText(find.widgetWithText(TextField, '0,00'), '250,50');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    final added = store.data.entries.firstWhere((e) => e.title == 'Bonus');
    expect(added.amount, 250.5);
    expect(added.type, 'in');
    expect(store.saves, 1);
  });

  testWidgets('edits and deletes an existing entry', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = await _pump(tester, past);

    await tester.tap(find.byTooltip('Show list'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salary'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('EDIT ENTRY'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Salary'), 'Salary+');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.data.entries.any((e) => e.title == 'Salary+'), isTrue);
    expect(store.data.entries.length, 2); // edited in place, not appended

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    // A delete is a tombstone now, so it can sync: gone from the app, still
    // in the file.
    expect(store.data.liveEntries.any((e) => e.id == 'a'), isFalse);
    expect(store.data.entries.firstWhere((e) => e.id == 'a').deleted, isTrue);
  });

  testWidgets('the stored data renders without errors', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(tester, _storedData());
    expect(find.text('Savings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone-width layout renders without overflow', (tester) async {
    tester.view.physicalSize = const Size(411, 890); // a typical Android phone
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(tester, _storedData());
    expect(find.text('Savings'), findsOneWidget);

    await tester.tap(find.byTooltip('Show list'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('prompts an end date that precedes the start date',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      past.copyWith(startDate: '2020-03-01', endDate: '2020-01-01'),
    );
    expect(find.text('Set an end date after the start date.'), findsOneWidget);
  });
}

void _tabTests() {
  final data = SavingsData(
    startDate: '2020-01-01',
    endDate: '2020-03-31',
    goal: 1000,
    loanAmount: 14000,
    apr: 1.9,
    loanYears: 4,
    entries: const [],
  );

  Future<void> addForecast(
    WidgetTester tester, {
    required bool income,
    required String title,
    required String amount,
  }) async {
    await tester.tap(find.byTooltip('Add entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(income ? '+ Income' : '− Expense'));
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextField, income ? 'e.g. Salary' : 'e.g. Rent'),
        title);
    await tester.enterText(find.widgetWithText(TextField, '0,00'), amount);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
  }

  Color leftColor(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('forecast-left'))).style!.color!;

  testWidgets('monthly tab starts empty with a zero balance', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, data);

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    expect(find.text('No entries yet.'), findsOneWidget);
    expect(find.text('LEFT AT END OF MONTH'), findsOneWidget);
    expect(find.text(eur(0)), findsOneWidget);
    expect(find.text('Goal'), findsNothing);
  });

  testWidgets('monthly tab adds, sorts, colours, edits and deletes',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await _pump(tester, data);

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();

    await addForecast(tester, income: false, title: 'Rent', amount: '800');
    expect(leftColor(tester), C.red);
    expect(find.text('−${eur(800.00)}'), findsNWidgets(2)); // hero + row

    await addForecast(tester, income: true, title: 'Salary', amount: '2000,50');
    expect(leftColor(tester), C.green);
    expect(find.text('+${eur(1200.50)}'), findsOneWidget);

    await addForecast(tester, income: false, title: 'Gym', amount: '30');

    // Amount descending: Salary, Rent, Gym.
    final y = {
      for (final t in ['Salary', 'Rent', 'Gym'])
        t: tester.getTopLeft(find.text(t)).dy,
    };
    expect(y['Salary']!, lessThan(y['Rent']!));
    expect(y['Rent']!, lessThan(y['Gym']!));
    expect(store.data.forecasts.length, 3);

    // Edit Gym into 100.
    await tester.tap(find.text('Gym'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '0,00'), '100');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('−${eur(100.00)}'), findsOneWidget);
    expect(store.data.forecasts.length, 3);

    // Delete Rent: it stays as a tombstone in the file.
    await tester.tap(find.byTooltip('Remove Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Rent'), findsNothing);
    expect(store.data.forecasts.where((f) => f.deleted).length, 1);
    expect(store.data.liveForecasts.length, 2);
  });

  testWidgets('monthly tab fits a phone screen', (tester) async {
    tester.view.physicalSize = const Size(411, 890);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      data.copyWith(forecasts: [
        for (var i = 0; i < 30; i++)
          Forecast(
              id: 'f$i',
              type: i.isEven ? 'in' : 'out',
              title: 'A fairly long description number $i for wrapping',
              amount: 10.0 + i),
      ]),
    );
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Add entry'), findsOneWidget);
  });

  testWidgets('the settings menu is on every tab and offers sync',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, data);

    for (final (icon, title) in [
      (Icons.show_chart, 'Savings'),
      (Icons.calculate_outlined, 'Loan'),
      (Icons.calendar_month_outlined, 'Monthly'),
    ]) {
      await tester.tap(find.byIcon(icon));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      // The title and the menu share one line.
      expect(
        tester.getCenter(find.text(title)).dy,
        closeTo(tester.getCenter(find.byTooltip('Settings')).dy, 1),
      );
    }

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sync with'), findsOneWidget);
  });

  testWidgets('reopens on the last selected tab', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'tab': 1});
    await tester.pumpWidget(SavingsApp(store: FakeStore(data)));
    await tester.pumpAndSettle();

    expect(find.text('Loan'), findsOneWidget);
    expect(find.text('Goal'), findsNothing);
  });
}
