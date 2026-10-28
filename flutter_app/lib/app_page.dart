import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'calc.dart';
import 'chart.dart';
import 'day_dialog.dart';
import 'entry_list.dart';
import 'expenses_tab.dart';
import 'model.dart';
import 'sync/repository.dart';
import 'sync/role.dart';
import 'sync/ui/scan_page.dart';
import 'sync/ui/sync_window.dart';
import 'theme.dart';
import 'widgets.dart';

/// Below this width the layout switches to its phone form.
const narrowWidth = 600.0;

class AppPage extends StatefulWidget {
  const AppPage({super.key, required this.repo, required this.role});

  /// Every read and write goes through here, so sync sees every edit.
  final SyncRepository repo;

  /// The PC shows the QR code; the phone scans it.
  final SyncRole role;

  @override
  State<AppPage> createState() => _AppPageState();
}

class _AppPageState extends State<AppPage> with WidgetsBindingObserver {
  SavingsData? _data;
  String _error = '';
  String _today = todayIso();
  String _view = 'graph';
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.repo.changes.addListener(_onData);
    _load();
  }

  @override
  void dispose() {
    widget.repo.changes.removeListener(_onData);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A sync replaces the whole document; this is how the page notices.
  void _onData() {
    if (!mounted) return;
    setState(() => _data = widget.repo.changes.value);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The day can roll over while the app sits open.
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => _today = todayIso());
    }
  }

  Future<void> _load() async {
    SavingsData data;
    try {
      data = await widget.repo.load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load data');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _data = data;
      _error = '';
      _today = todayIso();
      _view = prefs.getString('view') ?? 'graph';
      _tab = (prefs.getInt('tab') ?? 0).clamp(0, 2);
    });
  }

  Future<void> _selectTab(int next) async {
    setState(() => _tab = next);
    try {
      (await SharedPreferences.getInstance()).setInt('tab', next);
    } catch (_) {
      // A lost tab preference is not worth reporting.
    }
  }

  Future<void> _toggleView() async {
    final next = _view == 'graph' ? 'list' : 'graph';
    setState(() => _view = next);
    try {
      (await SharedPreferences.getInstance()).setString('view', next);
    } catch (_) {
      // A lost view preference is not worth reporting.
    }
  }

  /// A settings field. [base] is what the editor showed, so a value that
  /// arrived from a sync meanwhile is never overwritten blindly.
  void _update(SavingsData next, {SavingsData? base}) =>
      _write(widget.repo.updateSettings(next, base: base ?? _data));

  void _saveEntry(Entry entry, Entry? base) =>
      _write(widget.repo.saveEntry(entry, base: base));

  void _deleteEntry(String id) => _write(widget.repo.deleteEntry(id));

  void _saveForecast(Forecast forecast, Forecast? base) =>
      _write(widget.repo.saveForecast(forecast, base: base));

  void _deleteForecast(String id) => _write(widget.repo.deleteForecast(id));

  void _write(Future<void> work) {
    work.then(
      (_) {
        if (mounted && _error.isNotEmpty) setState(() => _error = '');
      },
      onError: (_) {
        if (mounted) setState(() => _error = 'Save failed');
      },
    );
  }

  Future<void> _openDay(String day) async {
    await showDayDialog(
      context: context,
      day: day,
      entries: () => _data!.liveEntries,
      onSave: _saveEntry,
      onDelete: _deleteEntry,
    );
  }

  /// The PC opens its QR window; the phone opens the camera and, on a good
  /// scan, pairs and syncs without another tap.
  Future<void> _openSync() => widget.role.isHub
      ? showSyncWindow(context: context, repo: widget.repo)
      : openScanPage(context: context, repo: widget.repo);

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error.isEmpty ? 'Loading…' : _error, style: body),
        ),
      );
    }

    final narrow = MediaQuery.sizeOf(context).width < narrowWidth;
    final entries = data.liveEntries;
    final have = totalUntil(_today, entries);
    final goal = data.goal;
    // Net of the entries still to come (after today, up to the end date) —
    // not including what we already have.
    final upcoming = entries.fold<double>(
      0,
      (s, e) =>
          e.date.compareTo(_today) > 0 && e.date.compareTo(data.endDate) <= 0
          ? s + signed(e)
          : s,
    );
    final expected = have + upcoming;
    double pct(double v) => goal > 0
        ? math.min(100, math.max(0, v / goal * 100))
        : v > 0
        ? 100
        : 0;
    final greenPct = pct(have);
    final grayPct = math.max(0.0, pct(expected) - greenPct);
    final remaining = math.max(0.0, goal - expected);
    final monthly = monthlyPayment(data.loanAmount, data.apr, data.loanYears);
    final interest = monthly * data.loanYears * 12 - data.loanAmount;

    final points = (data.endDate.compareTo(data.startDate) < 0)
        ? const <DayPoint>[]
        : series(dayRange(data.startDate, data.endDate), entries);

    // The tab never scrolls: the graph/list panel takes whatever height the
    // goal panel leaves, and only the list scrolls.
    final savingsTab = Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, narrow ? 16 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Panel(
                  flex: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _mainControls(data, have, narrow),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _view == 'list'
                            ? EntryListView(
                                entries: entries,
                                today: _today,
                                onPick: _openDay,
                                onAdd: () => _openDay(_today),
                                onDelete: _deleteEntry,
                              )
                            : points.isNotEmpty
                            ? Chart(
                                points: points,
                                today: _today,
                                entries: entries,
                                goal: goal,
                                onPick: _openDay,
                              )
                            : const Align(
                                alignment: Alignment.topLeft,
                                child: Text(
                                  'Set an end date after the '
                                  'start date.',
                                  style: TextStyle(
                                    color: C.muted,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _goalPanel(
            data,
            have,
            upcoming,
            expected,
            remaining,
            greenPct,
            grayPct,
          ),
        ],
      ),
    );

    final loanTab = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: _loanPanel(data, monthly, interest, narrow),
    );

    // IndexedStack keeps each tab's scroll position and inputs alive.
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _titleBar(),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  savingsTab,
                  loanTab,
                  ExpensesTab(
                    forecasts: data.liveForecasts,
                    onSave: _saveForecast,
                    onDelete: _deleteForecast,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _selectTab,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            tooltip: 'Savings',
            label: '',
          ),
          NavigationDestination(
            icon: Icon(Icons.calculate_outlined),
            selectedIcon: Icon(Icons.calculate),
            tooltip: 'Loan',
            label: '',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            tooltip: 'Monthly expenses',
            label: '',
          ),
        ],
      ),
    );
  }

  static const _tabTitles = ['Savings', 'Loan', 'Monthly'];

  /// The tab's name on the left and the settings menu on the right, on one
  /// line so the menu takes no extra height.
  Widget _titleBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
    child: SizedBox(
      height: 36,
      child: Row(
        children: [
          Text(_tabTitles[_tab], style: h1),
          if (_error.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(_error, style: const TextStyle(color: C.red, fontSize: 12)),
          ],
          const Spacer(),
          _settingsMenu(),
        ],
      ),
    ),
  );

  Widget _mainControls(SavingsData data, double have, bool narrow) {
    final toggle = AppButton.icon(
      onPressed: _toggleView,
      tooltip: _view == 'graph' ? 'Show list' : 'Show graph',
      foreground: C.muted,
      hoverForeground: C.text,
      hoverBackground: C.button,
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Center(
          child: _view == 'graph' ? const ListIcon() : const GraphIcon(),
        ),
      ),
    );

    final stat = Stat(
      label: 'Today',
      value: eur(have),
      big: true,
      color: have < 0 ? C.red : C.green,
      alignEnd: !narrow,
    );

    final start = Labeled(
      label: 'Start',
      child: DateField(
        value: data.startDate,
        onChanged: (v) => _update(data.copyWith(startDate: v)),
      ),
    );
    final end = Labeled(
      label: 'End',
      child: DateField(
        value: data.endDate,
        onChanged: (v) => _update(data.copyWith(endDate: v)),
      ),
    );

    // The toggle keeps the top-right corner; on phones the fields and the
    // Today figure wrap underneath each other instead of overflowing.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: narrow
              ? Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [start, end, stat],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    start,
                    const SizedBox(width: 12),
                    end,
                    const Spacer(),
                    stat,
                    const SizedBox(width: 12),
                  ],
                ),
        ),
        toggle,
      ],
    );
  }

  /// The three-dots menu that stays at the top right on every tab. Sync is
  /// its only option for now.
  Widget _settingsMenu() => PopupMenuButton<String>(
    tooltip: 'Settings',
    icon: const Icon(Icons.more_vert, color: C.muted),
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    color: C.panel,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: const BorderSide(color: C.dialogBorder),
    ),
    onSelected: (value) {
      if (value == 'sync') _openSync();
    },
    itemBuilder: (context) => [
      PopupMenuItem<String>(
        value: 'sync',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: widget.role.isHub ? const QrIcon() : const ScanIcon(),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                widget.role.isHub ? 'Sync with a phone' : 'Sync with the PC',
                style: body,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _goalPanel(
    SavingsData data,
    double have,
    double upcoming,
    double expected,
    double remaining,
    double greenPct,
    double grayPct,
  ) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Goal', style: h2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Target €', style: labelStyle),
                const SizedBox(width: 8),
                NumField(
                  value: data.goal,
                  onChanged: (v) => _update(data.copyWith(goal: v)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Container(
            height: 18,
            color: C.input,
            // stretch, or a childless ColoredBox collapses to no height.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: (greenPct * 100).round(),
                  child: const ColoredBox(color: C.green),
                ),
                Expanded(
                  flex: (grayPct * 100).round(),
                  child: const ColoredBox(color: C.barGray),
                ),
                Expanded(
                  flex: ((100 - greenPct - grayPct) * 100).round(),
                  child: const ColoredBox(color: C.red),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text('Have ${eur(have)}', style: mono.copyWith(color: C.green)),
            Text(
              'Expected ${upcoming >= 0 ? '+' : '−'}'
              '${eur(upcoming.abs())} → ${eur(expected)}',
              style: mono.copyWith(color: C.expected),
            ),
            Text(
              'Remaining ${eur(remaining)}',
              style: mono.copyWith(color: C.red),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _loanPanel(
    SavingsData data,
    double monthly,
    double interest,
    bool narrow,
  ) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Labeled(
              label: 'Max loan €',
              child: NumField(
                value: data.loanAmount,
                onChanged: (v) => _update(data.copyWith(loanAmount: v)),
              ),
            ),
            Labeled(
              label: 'APR %',
              child: NumField(
                value: data.apr,
                decimal: true,
                onChanged: (v) => _update(data.copyWith(apr: v)),
              ),
            ),
            Labeled(
              label: 'Years',
              child: NumField(
                value: data.loanYears.toDouble(),
                width: 80,
                onChanged: (v) {
                  if (v >= 1) {
                    _update(data.copyWith(loanYears: v.floor()));
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // The figures hug the right edge on a wide window and go left on
        // phones.
        SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: narrow ? 16 : 24,
            runSpacing: 12,
            alignment: narrow ? WrapAlignment.start : WrapAlignment.end,
            children: [
              Stat(
                label: 'Monthly payment',
                value: eur(monthly),
                big: true,
                alignEnd: !narrow,
              ),
              Stat(
                label: 'Total interest',
                value: eur(interest > 0 ? interest : 0),
                alignEnd: !narrow,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
