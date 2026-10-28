import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'calc.dart';
import 'model.dart';
import 'theme.dart';

const _w = 18.0; // px per day
const _top = 12.0;
const _bottom = 54.0; // day + month labels, plus space below them
const _minPh = 120.0; // smallest plot height
const _yAxisWidth = 64.0;

double niceStep(double span) {
  final raw = span / 4;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final f = raw / mag;
  return (f <= 1
          ? 1
          : f <= 2
          ? 2
          : f <= 5
          ? 5
          : 10) *
      mag;
}

/// The y scale shared by the axis and the plot.
class _Scale {
  _Scale(List<DayPoint> points, double goal) {
    var l = 0.0;
    var peak = 0.0;
    for (final p in points) {
      l = math.min(l, p.balance);
      peak = math.max(peak, p.balance);
    }
    // 10% headroom above the goal or the highest balance, whichever is more.
    var h = math.max(goal, peak) * 1.1;
    if (h <= l) h = l + 1000;
    final step = niceStep(h - l);
    l = (l / step).floor() * step;
    h = (h / step).ceil() * step;
    lo = l;
    hi = h;
    for (var v = l; v <= h + step / 2; v += step) {
      ticks.add(v);
    }
  }

  late final double lo;
  late final double hi;
  final List<double> ticks = [];
}

/// A month's span of day columns, used for the label and the separator.
class _Month {
  _Month(this.key, this.first, this.label);
  final String key;
  final int first;
  int last = 0;
  final String label;
}

List<_Month> _months(List<DayPoint> points) {
  final groups = <_Month>[];
  final multiYear =
      points.isNotEmpty &&
      points.first.day.substring(0, 4) != points.last.day.substring(0, 4);
  for (var i = 0; i < points.length; i++) {
    final key = points[i].day.substring(0, 7);
    if (groups.isNotEmpty && groups.last.key == key) {
      groups.last.last = i;
    } else {
      final d = parseDay('$key-01');
      final label = monthsShort[d.month - 1] + (multiYear ? ' ${d.year}' : '');
      groups.add(_Month(key, i, label)..last = i);
    }
  }
  return groups;
}

class Chart extends StatefulWidget {
  const Chart({
    super.key,
    required this.points,
    required this.today,
    required this.entries,
    required this.goal,
    required this.onPick,
  });

  final double goal;
  final List<DayPoint> points;
  final String today;
  final List<Entry> entries;
  final ValueChanged<String> onPick;

  @override
  State<Chart> createState() => _ChartState();
}

class _ChartState extends State<Chart> {
  final _scroll = ScrollController();
  int? _hover;
  String? _centeredOn; // the range we last auto-scrolled for

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Puts today in the middle of the viewport.
  void _centerToday(double viewport) {
    final points = widget.points;
    if (points.isEmpty) return;
    final key = '${points.first.day}..${points.length}..${widget.today}';
    if (_centeredOn == key) return;
    _centeredOn = key;
    var idx = points.indexWhere((p) => p.day == widget.today);
    if (idx < 0) {
      idx = widget.today.compareTo(points.last.day) > 0 ? points.length - 1 : 0;
    }
    final target = idx * _w - viewport / 2;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(
        target.clamp(0.0, math.max(0.0, _scroll.position.maxScrollExtent)),
      );
    });
  }

  int? _indexAt(double dx) {
    final i = (dx / _w).floor();
    return i >= 0 && i < widget.points.length ? i : null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final h = box.maxHeight;
        final ph = math.max(_minPh, h - _top - _bottom);
        final viewport = math.max(0.0, box.maxWidth - _yAxisWidth);
        final width = widget.points.length * _w;
        final scale = _Scale(widget.points, widget.goal);
        _centerToday(viewport);

        final hp = _hover != null && _hover! < widget.points.length
            ? widget.points[_hover!]
            : null;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _yAxisWidth,
              height: h,
              child: CustomPaint(
                painter: _AxisPainter(scale: scale, ph: ph),
              ),
            ),
            Expanded(
              child: ClipRect(
                child: ScrollConfiguration(
                  // Let a mouse drag the chart too, not just touch.
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.stylus,
                      PointerDeviceKind.trackpad,
                    },
                    scrollbars: false,
                  ),
                  child: SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      height: h,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            onHover: (e) {
                              final i = _indexAt(e.localPosition.dx);
                              if (i != _hover) setState(() => _hover = i);
                            },
                            onExit: (_) => setState(() => _hover = null),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (e) {
                                final i = _indexAt(e.localPosition.dx);
                                if (i != null) {
                                  widget.onPick(widget.points[i].day);
                                }
                              },
                              // Touch has no hover, so a long press peeks the
                              // same tooltip.
                              onLongPressStart: (e) => setState(
                                () => _hover = _indexAt(e.localPosition.dx),
                              ),
                              onLongPressMoveUpdate: (e) {
                                final i = _indexAt(e.localPosition.dx);
                                if (i != _hover) setState(() => _hover = i);
                              },
                              onLongPressEnd: (_) =>
                                  setState(() => _hover = null),
                              onLongPressCancel: () =>
                                  setState(() => _hover = null),
                              child: CustomPaint(
                                size: Size(width, h),
                                painter: _PlotPainter(
                                  points: widget.points,
                                  today: widget.today,
                                  scale: scale,
                                  goal: widget.goal,
                                  ph: ph,
                                  height: h,
                                  hover: _hover,
                                  scroll: _scroll,
                                  viewport: viewport,
                                ),
                              ),
                            ),
                          ),
                          if (hp != null)
                            Positioned(
                              left: math.min(
                                _hover! * _w + _w + 6,
                                width - 190,
                              ),
                              top: 8,
                              child: _Tooltip(
                                point: hp,
                                entries: widget.entries
                                    .where((e) => e.date == hp.day)
                                    .toList(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Tooltip extends StatelessWidget {
  const _Tooltip({required this.point, required this.entries});

  final DayPoint point;
  final List<Entry> entries;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: 184,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: C.panel,
        border: Border.all(color: C.dialogBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tipDate(point.day),
            style: const TextStyle(color: C.muted, fontSize: 12),
          ),
          Text(eur(point.balance), style: mono.copyWith(fontSize: 12)),
          for (final e in entries)
            Text(
              '${e.type == 'in' ? '+' : '−'}${eur(e.amount)} ${e.title}',
              style: TextStyle(
                fontSize: 12,
                color: e.type == 'in' ? C.green : C.red,
              ),
            ),
        ],
      ),
    ),
  );
}

TextPainter _text(String s, TextStyle style) => TextPainter(
  text: TextSpan(text: s, style: style),
  textDirection: TextDirection.ltr,
)..layout();

class _AxisPainter extends CustomPainter {
  _AxisPainter({required this.scale, required this.ph});

  final _Scale scale;
  final double ph;

  @override
  void paint(Canvas canvas, Size size) {
    for (final t in scale.ticks) {
      final tp = _text(
        eurShort(t),
        const TextStyle(
          color: C.muted,
          fontSize: 11,
          fontFamily: 'Consolas',
          fontFamilyFallback: monoFallback,
        ),
      );
      // SVG: x=58, baseline at y(t)+4, anchored at the end.
      final y = _top + ph - (t - scale.lo) / (scale.hi - scale.lo) * ph;
      tp.paint(canvas, Offset(58 - tp.width, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_AxisPainter old) =>
      old.scale.lo != scale.lo || old.scale.hi != scale.hi || old.ph != ph;
}

class _PlotPainter extends CustomPainter {
  _PlotPainter({
    required this.points,
    required this.today,
    required this.scale,
    required this.goal,
    required this.ph,
    required this.height,
    required this.hover,
    required this.scroll,
    required this.viewport,
  }) : super(repaint: scroll);

  final List<DayPoint> points;
  final String today;
  final _Scale scale;
  final double goal;
  final double ph;
  final double height;
  final int? hover;
  final ScrollController scroll;
  final double viewport;

  double _y(double v) =>
      _top + ph - (v - scale.lo) / (scale.hi - scale.lo) * ph;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final todayIdx = points.indexWhere((p) => p.day == today);

    // Negative region.
    if (scale.lo < 0) {
      canvas.drawRect(
        Rect.fromLTRB(0, _y(0), width, _top + ph),
        Paint()..color = C.neg,
      );
    }

    // Grid + zero line.
    for (final t in scale.ticks) {
      final y = _y(t);
      canvas.drawLine(
        Offset(0, y),
        Offset(width, y),
        Paint()
          ..color = t == 0 ? C.zero : C.grid
          ..strokeWidth = 1,
      );
    }

    // Goal: a dotted line across the plot, labelled at the visible left edge.
    if (goal > 0) {
      final gy = _y(goal);
      final goalPaint = Paint()
        ..color = C.green
        ..strokeWidth = 1.5;
      for (var x = 0.0; x < width; x += 6) {
        canvas.drawLine(
          Offset(x, gy),
          Offset(math.min(x + 2, width), gy),
          goalPaint,
        );
      }
      final tp = _text(
        'Goal',
        const TextStyle(
          color: C.green,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      );
      final lx = scroll.hasClients ? scroll.offset : 0.0;
      tp.paint(canvas, Offset(lx + 4, gy - tp.height - 2));
    }

    // Month separators (dashed 2 3).
    final months = _months(points);
    final sep = Paint()
      ..color = C.border
      ..strokeWidth = 1;
    for (final m in months) {
      if (m.first == 0) continue;
      final x = m.first * _w;
      for (var y = _top; y < height; y += 5) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 2, height)), sep);
      }
    }

    // Today and hover columns.
    if (todayIdx >= 0) {
      canvas.drawRect(
        Rect.fromLTWH(todayIdx * _w, _top, _w, ph),
        Paint()..color = C.todayCol,
      );
    }
    if (hover != null) {
      canvas.drawRect(
        Rect.fromLTWH(hover! * _w, _top, _w, ph),
        Paint()..color = C.hoverCol,
      );
    }

    // Step line: solid up to today, dashed after.
    final past = Path();
    final future = Path();
    var pastStarted = false;
    var futureStarted = false;
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final x0 = i * _w;
      final yy = _y(p.balance);
      if (p.day.compareTo(today) <= 0) {
        if (!pastStarted) {
          past.moveTo(x0, yy);
          pastStarted = true;
        } else {
          past.lineTo(x0, yy);
        }
        past.lineTo(x0 + _w, yy);
      } else if (!futureStarted) {
        final prev = i > 0 ? _y(points[i - 1].balance) : yy;
        future.moveTo(x0, prev);
        future.lineTo(x0, yy);
        future.lineTo(x0 + _w, yy);
        futureStarted = true;
      } else {
        future.lineTo(x0, yy);
        future.lineTo(x0 + _w, yy);
      }
    }
    final linePaint = Paint()
      ..color = C.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(past, linePaint);
    canvas.drawPath(
      _dash(future, 5, 4),
      Paint()
        ..color = C.accent.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    // Today marker.
    if (todayIdx >= 0) {
      canvas.drawLine(
        Offset(todayIdx * _w + _w / 2, _top),
        Offset(todayIdx * _w + _w / 2, _top + ph),
        Paint()
          ..color = C.accent
          ..strokeWidth = 1.5,
      );
    }

    // Entry dots.
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.count == 0) continue;
      final future = p.day.compareTo(today) > 0;
      final alpha = future ? 0.6 : 1.0;
      final center = Offset(i * _w + _w / 2, _y(p.balance));
      canvas.drawCircle(
        center,
        5,
        Paint()
          ..color = (p.net >= 0 ? C.green : C.red).withValues(alpha: alpha),
      );
      canvas.drawCircle(
        center,
        5,
        Paint()
          ..color = C.bg.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Day numbers.
    for (var i = 0; i < points.length; i++) {
      final isToday = i == todayIdx;
      final tp = _text(
        int.parse(points[i].day.substring(8)).toString(),
        TextStyle(
          color: isToday ? C.accent : C.muted,
          fontSize: 11,
          fontWeight: isToday ? FontWeight.w700 : FontWeight.normal,
        ),
      );
      // SVG baseline at TOP+PH+16, centred in the column.
      tp.paint(
        canvas,
        Offset(
          i * _w + _w / 2 - tp.width / 2,
          _top + ph + 16 - tp.height * 0.8,
        ),
      );
    }

    // Month labels, centred on the visible part of each month.
    final left = scroll.hasClients ? scroll.offset : 0.0;
    for (final m in months) {
      final a = math.max(m.first * _w, left);
      final b = math.min((m.last + 1) * _w, left + viewport);
      final x = b > a ? (a + b) / 2 : (m.first + m.last + 1) / 2 * _w;
      final tp = _text(
        m.label,
        const TextStyle(
          color: C.text,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );
      tp.paint(
        canvas,
        Offset(x - tp.width / 2, _top + ph + 36 - tp.height * 0.8),
      );
    }
  }

  /// Dashes a path, standing in for SVG's stroke-dasharray.
  Path _dash(Path source, double on, double off) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var d = 0.0;
      var draw = true;
      while (d < metric.length) {
        final next = math.min(d + (draw ? on : off), metric.length);
        if (draw) out.addPath(metric.extractPath(d, next), Offset.zero);
        d = next;
        draw = !draw;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(_PlotPainter old) =>
      old.points != points ||
      old.today != today ||
      old.hover != hover ||
      old.ph != ph ||
      old.height != height ||
      old.viewport != viewport ||
      old.scale.lo != scale.lo ||
      old.scale.hi != scale.hi ||
      old.goal != goal;
}
