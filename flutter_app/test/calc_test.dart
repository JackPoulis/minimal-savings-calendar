import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:savings/calc.dart';
import 'package:savings/model.dart';

/// Expected values were computed independently from the same inputs.
void main() {
  final seed = File('assets/seed_data.json').existsSync()
      ? File('assets/seed_data.json')
      : File('assets/seed_data.example.json');
  final raw = jsonDecode(seed.readAsStringSync()) as Map<String, dynamic>;
  final data = SavingsData.fromJson(raw);
  final hasRealData = data.entries.isNotEmpty;

  group('forecast', () {
    const list = [
      Forecast(id: 'a', type: 'in', title: 'Salary', amount: 2000),
      Forecast(id: 'b', type: 'out', title: 'Rent', amount: 800),
      Forecast(id: 'c', type: 'out', title: 'Gym', amount: 30.5),
    ];

    test('totals are income minus expenses', () {
      final t = forecastTotals(list);
      expect(t.income, 2000);
      expect(t.expenses, 830.5);
      expect(t.left, 1169.5);
      expect(forecastTotals(const []).left, 0);
    });

    test('sorts by amount descending', () {
      expect(sortForecasts(list.reversed).map((f) => f.id), ['a', 'b', 'c']);
    });

    test('old data without forecasts still loads', () {
      final d = SavingsData.fromJson({'entries': []});
      expect(d.forecasts, isEmpty);
      expect(d.toJson().containsKey('forecasts'), isFalse);
    });
  });

  group('dayRange', () {
    test('is inclusive of both ends', () {
      expect(dayRange('2026-09-01', '2026-09-30').length, 30);
      expect(dayRange('2026-09-01', '2026-09-01'), ['2026-09-01']);
      expect(dayRange('2026-09-02', '2026-09-01'), isEmpty);
    });

    test('crosses month and year boundaries', () {
      expect(dayRange('2026-12-30', '2027-01-02'),
          ['2026-12-30', '2026-12-31', '2027-01-01', '2027-01-02']);
    });

    test('is capped at 3700 days', () {
      expect(dayRange('2000-01-01', '2099-01-01').length, 3700);
    });
  });

  group('series', () {
    final entries = [
      const Entry(id: 'a', type: 'in', title: 'A', amount: 100, date: '2026-01-02'),
      const Entry(id: 'b', type: 'in', title: 'B', amount: 50, date: '2026-01-02'),
      const Entry(id: 'c', type: 'out', title: 'C', amount: 30, date: '2026-01-04'),
    ];

    test('carries the balance forward and counts entries per day', () {
      final s = series(dayRange('2026-01-01', '2026-01-05'), entries);
      expect(s.map((p) => p.balance), [0, 150, 150, 120, 120]);
      expect(s.map((p) => p.net), [0, 150, 0, -30, 0]);
      expect(s.map((p) => p.count), [0, 2, 0, 1, 0]);
    });

    test('includes entries dated before the range in the running balance', () {
      final s = series(dayRange('2026-01-03', '2026-01-04'), entries);
      expect(s.first.balance, 150);
      expect(s.first.count, 0);
    });
  });

  group('monthlyPayment', () {
    test('matches the JS result for the stored loan', () {
      expect(monthlyPayment(14000, 1.9, 4), closeTo(303.1211062772826, 1e-9));
    });

    test('divides evenly at 0% APR', () {
      expect(monthlyPayment(12000, 0, 5), 200);
    });

    test('is zero without a principal or a term', () {
      expect(monthlyPayment(0, 1.9, 4), 0);
      expect(monthlyPayment(14000, 1.9, 0), 0);
    });
  });

  group('formatting', () {
    test('euros use de-DE grouping with a non-breaking space', () {
      expect(eur(1234.5), '1.234,50 €');
      expect(eur(-700), '-700,00 €');
    });

    test('short euros drop the decimals', () {
      expect(eurShort(15000), '15.000 €');
      expect(eurShort(0), '0 €');
    });

    test('date labels are the en-GB strings', () {
      expect(shortDate('2026-09-21'), '21/09/26');
      expect(fieldDate('2026-09-21'), '21/09/2026');
      expect(tipDate('2026-09-21'), 'Mon, 21 Sep 2026');
      expect(longDate('2026-09-21'), 'Monday, 21 September 2026');
    });
  });

  group('stored data', () {
    test('re-encodes key-for-key', () {
      final out = jsonDecode(jsonEncode(data.toJson()));
      expect(out, equals(raw));
    });

    test('totals match the JS run', () {
      if (!hasRealData) return; // clean checkout: only the example seed exists
      expect(totalUntil('2026-09-30', data.entries), 3800);
      expect(totalUntil('2027-05-31', data.entries), 10400);
    });

    test('the chart series matches the JS run', () {
      if (!hasRealData) return;
      final s = series(dayRange('2026-09-01', '2026-10-02'), data.entries);
      final byDay = {for (final p in s) p.day: p};
      expect(byDay['2026-09-20']!.balance, 0);
      expect(byDay['2026-09-21']!.balance, 2700);
      expect(byDay['2026-09-21']!.count, 3);
      expect(byDay['2026-09-30']!.balance, 3800);
      expect(byDay['2026-09-30']!.net, 1100);
      expect(byDay['2026-10-01']!.balance, 3800);
    });
  });
}
