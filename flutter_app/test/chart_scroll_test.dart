import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savings/calc.dart';
import 'package:savings/chart.dart';
import 'package:savings/main.dart';
import 'package:savings/model.dart';
import 'package:savings/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeStore extends Store {
  FakeStore(this.data);
  SavingsData data;
  @override
  Future<SavingsData> load() async => data;
  @override
  Future<void> save(SavingsData next) async => data = next;
}

ScrollPosition _position(WidgetTester tester, AxisDirection direction) {
  final scrollable = tester
      .widgetList<Scrollable>(find.byType(Scrollable))
      .firstWhere((s) => s.axisDirection == direction);
  return tester.state<ScrollableState>(find.byWidget(scrollable)).position;
}

void main() {
  testWidgets('the tab does not scroll, and a mouse drag pans the chart', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 890);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});

    final now = DateTime.now();
    await tester.pumpWidget(
      SavingsApp(
        store: FakeStore(
          SavingsData(
            startDate: iso(now.subtract(const Duration(days: 120))),
            endDate: iso(now.add(const Duration(days: 120))),
            goal: 10000,
            loanAmount: 14000,
            apr: 1.9,
            loanYears: 4,
            entries: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chart = _position(tester, AxisDirection.right);
    final centred = chart.pixels;
    expect(centred, greaterThan(0));

    // The tab itself has no vertical scrolling.
    expect(
      tester
          .widgetList<Scrollable>(find.byType(Scrollable))
          .where((s) => s.axisDirection == AxisDirection.down)
          .length,
      lessThanOrEqualTo(1), // only the Loan tab's, kept alive off-screen
    );

    // Dragging with the left mouse button moves the chart through time.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Chart)),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(chart.pixels, greaterThan(centred));
  });
}
