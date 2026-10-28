import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'calc.dart';
import 'theme.dart';

/// `.panel`
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.flex = false});

  final Widget child;

  /// `.main-panel` — fills the remaining height of `.screen`.
  final bool flex;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: C.panel,
        border: Border.all(color: C.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: child,
    );
    return flex ? Expanded(child: box) : box;
  }
}

/// `button`, in its default, `.primary` and `.danger` flavours.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.child,
    this.onPressed,
    this.primary = false,
    this.danger = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.background,
    this.foreground,
    this.hoverBackground,
    this.hoverForeground,
    this.borderRadius = 2,
    this.outlined = false,
    this.tooltip,
  });

  /// `button.icon` — no background, tighter padding.
  const AppButton.icon({
    super.key,
    required this.child,
    this.onPressed,
    this.tooltip,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.foreground,
    this.hoverForeground,
    this.hoverBackground,
  }) : primary = false,
       danger = false,
       background = Colors.transparent,
       borderRadius = 2,
       outlined = false;

  final Widget child;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;
  final EdgeInsets padding;
  final Color? background;
  final Color? foreground;
  final Color? hoverBackground;
  final Color? hoverForeground;
  final double borderRadius;
  final bool outlined;
  final String? tooltip;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.background ?? (widget.primary ? C.accent : C.button);
    final fg = widget.foreground ?? (widget.primary ? Colors.white : C.text);
    final hoverBg =
        widget.hoverBackground ??
        (widget.primary
            ? C.accentHover
            : widget.danger
            ? C.dangerBg
            : bg == Colors.transparent
            ? C.button
            : C.buttonHover);
    final hoverFg = widget.hoverForeground ?? (widget.danger ? C.red : fg);

    Widget button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _hover ? hoverBg : bg,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: widget.outlined ? Border.all(color: C.accent) : null,
          ),
          child: DefaultTextStyle(
            style: body.copyWith(color: _hover ? hoverFg : fg),
            child: IconTheme(
              data: IconThemeData(color: _hover ? hoverFg : fg),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

/// `label` — caption above a field.
class Labeled extends StatelessWidget {
  const Labeled({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: labelStyle),
      const SizedBox(height: 4),
      child,
    ],
  );
}

InputDecoration fieldDecoration({String? hint}) => InputDecoration(
  isDense: true,
  filled: true,
  fillColor: C.input,
  hintText: hint,
  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
  border: const OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(2)),
    borderSide: BorderSide(color: C.input),
  ),
  enabledBorder: const OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(2)),
    borderSide: BorderSide(color: C.input),
  ),
  focusedBorder: const OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(2)),
    borderSide: BorderSide(color: C.accent),
  ),
  hintStyle: const TextStyle(color: C.muted),
);

/// Keeps the typed text (so "0" or "0." stay visible) and reports it as a
/// number; empty = 0.
class NumField extends StatefulWidget {
  const NumField({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = 130,
    this.decimal = false,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double width;
  final bool decimal;

  @override
  State<NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<NumField> {
  late final TextEditingController _c = TextEditingController(
    text: _show(widget.value),
  );

  static String _show(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  double? _parse(String s) => s.isEmpty ? 0 : double.tryParse(s);

  @override
  void didUpdateWidget(NumField old) {
    super.didUpdateWidget(old);
    // Only reset the text when the value changed behind our back.
    if (_parse(_c.text) != widget.value) _c.text = _show(widget.value);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    child: TextField(
      controller: _c,
      style: body,
      keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          widget.decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
        ),
      ],
      decoration: fieldDecoration(),
      onChanged: (s) {
        final n = _parse(s);
        if (n != null) widget.onChanged(n);
      },
    ),
  );
}

/// Stands in for `<input type="date">`: shows the date, opens a picker on tap.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final d = parseDay(value);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: d,
            firstDate: DateTime(d.year - 20),
            lastDate: DateTime(d.year + 20),
          );
          if (picked != null) onChanged(iso(picked));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: C.input,
            border: Border.all(color: C.input),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(fieldDate(value), style: body),
              const SizedBox(width: 8),
              const Icon(
                Icons.calendar_today_outlined,
                size: 14,
                color: C.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.stat` — a muted caption over a monospaced figure.
class Stat extends StatelessWidget {
  const Stat({
    super.key,
    required this.label,
    required this.value,
    this.big = false,
    this.color,
    this.alignEnd = true,
  });

  final String label;
  final String value;
  final bool big;
  final Color? color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: labelStyle),
      Text(
        value,
        style: (big ? monoBig : mono).copyWith(color: color ?? C.text),
      ),
    ],
  );
}

// ── Icons, drawn from the same paths the SVGs use ───────────────────────────

class ListIcon extends StatelessWidget {
  const ListIcon({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(18, 18),
    painter: _ListIconPainter(color ?? IconTheme.of(context).color!),
  );
}

class _ListIconPainter extends CustomPainter {
  _ListIconPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 16;
    final p = Paint()..color = color;
    void bar(double x, double y, double w, double h) =>
        canvas.drawRect(Rect.fromLTWH(x * s, y * s, w * s, h * s), p);
    bar(1, 2.5, 2, 2);
    bar(5, 3, 10, 1);
    bar(1, 7, 2, 2);
    bar(5, 7.5, 10, 1);
    bar(1, 11.5, 2, 2);
    bar(5, 12, 10, 1);
  }

  @override
  bool shouldRepaint(_ListIconPainter old) => old.color != color;
}

class GraphIcon extends StatelessWidget {
  const GraphIcon({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(18, 18),
    painter: _GraphIconPainter(color ?? IconTheme.of(context).color!),
  );
}

class _GraphIconPainter extends CustomPainter {
  _GraphIconPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 16;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3 * s;
    // M1.5 1.5v13h13
    canvas.drawPath(
      Path()
        ..moveTo(1.5 * s, 1.5 * s)
        ..lineTo(1.5 * s, 14.5 * s)
        ..lineTo(14.5 * s, 14.5 * s),
      p,
    );
    // M3.5 11H6V7.5h3V9h2.5V4H14
    canvas.drawPath(
      Path()
        ..moveTo(3.5 * s, 11 * s)
        ..lineTo(6 * s, 11 * s)
        ..lineTo(6 * s, 7.5 * s)
        ..lineTo(9 * s, 7.5 * s)
        ..lineTo(9 * s, 9 * s)
        ..lineTo(11.5 * s, 9 * s)
        ..lineTo(11.5 * s, 4 * s)
        ..lineTo(14 * s, 4 * s),
      p,
    );
  }

  @override
  bool shouldRepaint(_GraphIconPainter old) => old.color != color;
}

class PlusIcon extends StatelessWidget {
  const PlusIcon({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(18, 18),
    painter: _StrokeIconPainter(
      color ?? IconTheme.of(context).color!,
      plus: true,
      strokeWidth: 2,
    ),
  );
}

class MinusIcon extends StatelessWidget {
  const MinusIcon({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(12, 12),
    painter: _StrokeIconPainter(
      color ?? IconTheme.of(context).color!,
      plus: false,
      strokeWidth: 2.5,
    ),
  );
}

class _StrokeIconPainter extends CustomPainter {
  _StrokeIconPainter(
    this.color, {
    required this.plus,
    required this.strokeWidth,
  });
  final Color color;
  final bool plus;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 16;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * s
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(2 * s, 8 * s), Offset(14 * s, 8 * s), p);
    if (plus) canvas.drawLine(Offset(8 * s, 2 * s), Offset(8 * s, 14 * s), p);
  }

  @override
  bool shouldRepaint(_StrokeIconPainter old) =>
      old.color != color || old.plus != plus;
}

/// The PC's sync button: a QR code.
class QrIcon extends StatelessWidget {
  const QrIcon({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(18, 18),
    painter: _QrIconPainter(color ?? IconTheme.of(context).color!),
  );
}

class _QrIconPainter extends CustomPainter {
  _QrIconPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 16;
    final fill = Paint()..color = color;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s;
    void eye(double x, double y) {
      canvas.drawRect(
        Rect.fromLTWH((x + 0.5) * s, (y + 0.5) * s, 4 * s, 4 * s),
        line,
      );
      canvas.drawRect(
        Rect.fromLTWH((x + 2) * s, (y + 2) * s, 1.5 * s, 1.5 * s),
        fill,
      );
    }

    void dot(double x, double y) =>
        canvas.drawRect(Rect.fromLTWH(x * s, y * s, 1.5 * s, 1.5 * s), fill);

    eye(1, 1);
    eye(10, 1);
    eye(1, 10);
    dot(10, 10);
    dot(13, 12);
    dot(12.5, 14.5);
    dot(7, 7);
  }

  @override
  bool shouldRepaint(_QrIconPainter old) => old.color != color;
}

/// The phone's sync button: a viewfinder.
class ScanIcon extends StatelessWidget {
  const ScanIcon({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(18, 18),
    painter: _ScanIconPainter(color ?? IconTheme.of(context).color!),
  );
}

class _ScanIconPainter extends CustomPainter {
  _ScanIconPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 16;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 1.2
      ..strokeCap = StrokeCap.square;
    // Four corners of a frame, plus the scanning line across the middle.
    void corner(double x, double y, double dx, double dy) {
      canvas.drawLine(Offset(x * s, y * s), Offset((x + dx) * s, y * s), p);
      canvas.drawLine(Offset(x * s, y * s), Offset(x * s, (y + dy) * s), p);
    }

    corner(2, 2, 3.5, 3.5);
    corner(14, 2, -3.5, 3.5);
    corner(2, 14, 3.5, -3.5);
    corner(14, 14, -3.5, -3.5);
    canvas.drawLine(Offset(3 * s, 8 * s), Offset(13 * s, 8 * s), p);
  }

  @override
  bool shouldRepaint(_ScanIconPainter old) => old.color != color;
}
