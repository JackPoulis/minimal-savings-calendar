import 'dart:math' as math;

import 'package:intl/intl.dart';

import 'model.dart';

DateTime parseDay(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String iso(DateTime d) {
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)}';
}

String todayIso() => iso(DateTime.now());

List<String> dayRange(String start, String end) {
  final days = <String>[];
  var d = parseDay(start);
  final last = parseDay(end);
  while (!d.isAfter(last) && days.length < 3700) {
    days.add(iso(d));
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return days;
}

double signed(Entry e) => e.type == 'in' ? e.amount : -e.amount;

/// Monthly forecast totals: what comes in, what goes out, and what is left.
({double income, double expenses, double left}) forecastTotals(
  Iterable<Forecast> list,
) {
  var income = 0.0;
  var expenses = 0.0;
  for (final f in list) {
    if (f.type == 'in') {
      income += f.amount;
    } else {
      expenses += f.amount;
    }
  }
  return (income: income, expenses: expenses, left: income - expenses);
}

/// Largest amount first; ties keep a stable, alphabetical order.
List<Forecast> sortForecasts(Iterable<Forecast> list) =>
    [...list]..sort((a, b) {
      final byAmount = b.amount.compareTo(a.amount);
      return byAmount != 0 ? byAmount : a.title.compareTo(b.title);
    });

/// Balance at the end of each day: all entries dated on or before that day.
List<DayPoint> series(List<String> days, List<Entry> entries) {
  final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));
  var i = 0;
  var bal = 0.0;
  return days.map((day) {
    var net = 0.0;
    var count = 0;
    while (i < sorted.length && sorted[i].date.compareTo(day) <= 0) {
      if (sorted[i].date == day) {
        net += signed(sorted[i]);
        count++;
      }
      bal += signed(sorted[i]);
      i++;
    }
    return DayPoint(day: day, balance: bal, net: net, count: count);
  }).toList();
}

double totalUntil(String day, List<Entry> entries) =>
    entries.fold(0.0, (s, e) => e.date.compareTo(day) <= 0 ? s + signed(e) : s);

double monthlyPayment(double principal, double apr, int years) {
  final n = years * 12;
  if (principal == 0 || n == 0) return 0;
  final r = apr / 12 / 100;
  if (r == 0) return principal / n;
  return (principal * r) / (1 - math.pow(1 + r, -n));
}

/// A day on the chart: the running balance plus what happened on that day.
class DayPoint {
  const DayPoint({
    required this.day,
    required this.balance,
    required this.net,
    required this.count,
  });

  final String day;
  final double balance;
  final double net;
  final int count;
}

final _fmt = NumberFormat.currency(locale: 'de_DE', symbol: '€');
String eur(double v) => _fmt.format(v);

final _fmtShort = NumberFormat.decimalPattern('de_DE')
  ..maximumFractionDigits = 0;
String eurShort(double v) => '${_fmtShort.format(v)} €';

// ── Date labels ─────────────────────────────────────────────────────────────
// Spelled out here rather than via locale data so the strings are en-GB
// exactly and tests need no locale initialisation.

const monthsShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const monthsLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const weekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const weekdaysLong = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _p(int n) => n.toString().padLeft(2, '0');

/// `dd/MM/yy` — the date column in the list view.
String shortDate(String day) {
  final d = parseDay(day);
  return '${_p(d.day)}/${_p(d.month)}/${_p(d.year % 100)}';
}

/// `dd/MM/yyyy` — the start/end date fields.
String fieldDate(String day) {
  final d = parseDay(day);
  return '${_p(d.day)}/${_p(d.month)}/${d.year}';
}

/// `Sun, 21 Sep 2026` — the chart tooltip.
String tipDate(String day) {
  final d = parseDay(day);
  return '${weekdaysShort[d.weekday - 1]}, ${d.day} '
      '${monthsShort[d.month - 1]} ${d.year}';
}

/// `Sunday, 21 September 2026` — the day dialog heading.
String longDate(String day) {
  final d = parseDay(day);
  return '${weekdaysLong[d.weekday - 1]}, ${d.day} '
      '${monthsLong[d.month - 1]} ${d.year}';
}
