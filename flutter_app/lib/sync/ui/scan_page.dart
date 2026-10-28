import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../theme.dart';
import '../../widgets.dart';
import '../client/hub_api.dart';
import '../client/pairing_service.dart';
import '../client/sync_client.dart';
import '../merge/merge_models.dart';
import '../protocol/pairing_qr.dart';
import '../repository.dart';
import 'conflict_page.dart';

/// The phone's whole sync UI: point the camera at the PC's QR code. A good
/// scan pairs and syncs in one go — there is no pairing step and no sync
/// button to press afterwards.
Future<void> openScanPage({
  required BuildContext context,
  required SyncRepository repo,
}) => Navigator.of(context)
    .push<void>(MaterialPageRoute(builder: (context) => ScanPage(repo: repo)));

enum _Phase { scanning, working, result }

class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.repo});

  final SyncRepository repo;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  _Phase _phase = _Phase.scanning;
  String _status = '';
  String _message = '';
  bool _ok = false;
  bool _canRescan = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_phase != _Phase.scanning) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _sync(raw);
        return;
      }
    }
  }

  Future<void> _sync(String raw) async {
    setState(() {
      _phase = _Phase.working;
      _status = 'Connecting to the PC…';
    });
    await _controller.stop().catchError((_) {});

    try {
      final code = PairingCode.decode(raw);
      await PairingService(repo: widget.repo).pair(code);
      if (!mounted) return;
      setState(() => _status = 'Syncing…');
      final summary = await SyncClient(repo: widget.repo)
          .run(resolver: _resolve);
      _finish(ok: true, message: summary.text, canRescan: false);
    } on SyncException catch (e) {
      _finish(ok: false, message: e.message, canRescan: true);
    } on FormatException catch (e) {
      _finish(ok: false, message: e.message, canRescan: true);
    } on Object catch (e) {
      _finish(ok: false, message: 'Sync failed: $e', canRescan: true);
    }
  }

  void _finish({
    required bool ok,
    required String message,
    required bool canRescan,
  }) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.result;
      _ok = ok;
      _message = message;
      _canRescan = canRescan;
    });
  }

  Future<Map<String, ConflictChoice>?> _resolve(
    List<Conflict> conflicts,
  ) async {
    if (!mounted) return null;
    return Navigator.of(context).push<Map<String, ConflictChoice>>(
      MaterialPageRoute(
        builder: (context) => ConflictPage(conflicts: conflicts),
      ),
    );
  }

  Future<void> _again() async {
    setState(() {
      _phase = _Phase.scanning;
      _message = '';
    });
    try {
      await _controller.start();
    } on Object {
      // The error builder already tells the user what the camera is doing.
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => _camera(error),
        ),
        SafeArea(
          child: Column(
            children: [
              _bar(),
              const Spacer(),
              if (_phase == _Phase.working) _working(),
              if (_phase == _Phase.result) _result(),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _bar() => Container(
    padding: const EdgeInsets.all(12),
    color: const Color(0xB3000000),
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'Scan the QR code on the PC',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        AppButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Close',
          foreground: Colors.white,
          child: const Text('✕'),
        ),
      ],
    ),
  );

  Widget _card({required Widget child}) => Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: C.panel,
      border: Border.all(color: C.border),
      borderRadius: BorderRadius.circular(4),
    ),
    child: child,
  );

  Widget _working() => _card(
    child: Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(_status, style: body)),
      ],
    ),
  );

  Widget _result() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_ok ? 'Synced' : 'Not synced', style: h2),
        const SizedBox(height: 6),
        Text(_message, style: body.copyWith(color: _ok ? C.text : C.red)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_canRescan) ...[
              AppButton(onPressed: _again, child: const Text('Scan again')),
              const SizedBox(width: 12),
            ],
            AppButton(
              primary: true,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _camera(MobileScannerException error) => Center(
    child: _card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('The camera is not available', style: h2),
          const SizedBox(height: 6),
          Text(
            error.errorCode == MobileScannerErrorCode.permissionDenied
                ? 'Allow camera access for this app to read the PC\'s QR '
                      'code.'
                : error.errorDetails?.message ?? '${error.errorCode}',
            style: const TextStyle(color: C.red, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}
