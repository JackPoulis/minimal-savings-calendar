import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../theme.dart';
import '../../widgets.dart';
import '../protocol/pairing_qr.dart';
import '../repository.dart';
import '../server/device_registry.dart';
import '../server/hub_identity.dart';
import '../server/hub_server.dart';
import '../server/hub_sync_service.dart';
import '../server/lan_addresses.dart';
import '../server/pairing_tokens.dart';

/// The PC's whole sync UI: a QR code. Sharing is on for exactly as long as
/// this window is open, and the sync runs the moment a phone scans the code.
Future<void> showSyncWindow({
  required BuildContext context,
  required SyncRepository repo,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  barrierColor: const Color(0x8C000000),
  builder: (context) => Dialog(
    backgroundColor: C.panel,
    insetPadding: const EdgeInsets.all(16),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: const BorderSide(color: C.dialogBorder),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: _SyncWindow(repo: repo),
    ),
  ),
);

class _SyncWindow extends StatefulWidget {
  const _SyncWindow({required this.repo});

  final SyncRepository repo;

  @override
  State<_SyncWindow> createState() => _SyncWindowState();
}

class _SyncWindowState extends State<_SyncWindow> {
  HubServer? _server;
  PairingTokens? _tokens;

  List<LanAddress> _addresses = const [];
  LanAddress? _address;
  String _serverId = '';
  int _port = 0;
  String? _token;

  String _status = 'Starting…';
  String _error = '';
  bool _busy = false;
  int _sent = 0;
  int _received = 0;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  @override
  void dispose() {
    // Closing the window stops sharing.
    _server?.stop();
    super.dispose();
  }

  Future<void> _begin() async {
    try {
      final identity = HubIdentity(widget.repo);
      final info = await identity.ensure();
      final addresses = await lanAddresses();
      final registry = DeviceRegistry(widget.repo);
      final tokens = PairingTokens();
      final server = HubServer(
        info: info,
        registry: registry,
        tokens: tokens,
        sync: HubSyncService(repo: widget.repo, registry: registry),
        onEvent: _onEvent,
      );
      final port = await server.start();
      if (!mounted) {
        await server.stop();
        return;
      }
      setState(() {
        _server = server;
        _tokens = tokens;
        _serverId = info.serverId;
        _addresses = addresses;
        _address = addresses.isEmpty ? null : addresses.first;
        _port = port;
        _token = tokens.issue();
        _status = 'Scan this with the phone.';
        _error = addresses.isEmpty
            ? 'No network address found. Connect this PC to the same Wi-Fi as '
                  'the phone and reopen this window.'
            : '';
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _status = '';
        _error = 'Could not start sharing: $e';
      });
    }
  }

  void _onEvent(HubEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event.kind) {
        case HubEventKind.paired:
          _busy = true;
          _sent = 0;
          _received = 0;
          _status = '${event.deviceName} connected…';
        case HubEventKind.served:
          _busy = true;
          _sent = event.records;
          _status = 'Syncing…';
        case HubEventKind.applied:
          _busy = false;
          _received = event.records;
          _status = _sent == 0 && _received == 0
              ? 'Already in sync.'
              : 'Synced — sent $_sent, received $_received.';
          // Ready for the next sync straight away.
          _token = _tokens?.issue();
        case HubEventKind.rejected:
          _busy = false;
          _status = 'The phone sent data this PC could not read.';
      }
    });
  }

  void _newCode() => setState(() {
    _token = _tokens?.issue();
    _status = 'Scan this with the phone.';
  });

  Future<void> _close() async {
    if (_busy) {
      final stop = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: C.panel,
          title: const Text('A sync is running', style: h2),
          content: const Text(
            'Closing this window stops it. Nothing will be changed on either '
            'device.',
            style: body,
          ),
          actions: [
            AppButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep it open'),
            ),
            AppButton(
              danger: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Stop'),
            ),
          ],
        ),
      );
      if (stop != true) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  String? get _payload {
    final address = _address;
    final token = _token;
    if (address == null || token == null || _port == 0) return null;
    return PairingCode(
      host: address.address,
      port: _port,
      serverId: _serverId,
      pairingToken: token,
    ).encode();
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Sync with a phone', style: h2)),
              AppButton.icon(
                onPressed: _close,
                tooltip: 'Close',
                child: const Text('✕'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (payload != null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                color: Colors.white,
                child: QrImageView(
                  // The payload is also the key, so a new code really
                  // replaces the old image.
                  key: ValueKey(payload),
                  data: payload,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                  // The code is shown on screen and read straight away, so the
                  // lowest correction level keeps it as coarse as possible.
                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                ),
              ),
            )
          else
            const SizedBox(
              height: 220,
              child: Center(
                child: Text('…', style: TextStyle(color: C.muted)),
              ),
            ),
          const SizedBox(height: 12),
          Text(_status, style: body.copyWith(color: _busy ? C.text : C.muted)),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_error, style: const TextStyle(color: C.red, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          if (_addresses.length > 1) ...[
            Labeled(
              label: 'This PC on the network',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: C.input,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: DropdownButton<LanAddress>(
                  value: _address,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  dropdownColor: C.panel,
                  style: body,
                  items: [
                    for (final address in _addresses)
                      DropdownMenuItem(
                        value: address,
                        child: Text('$address', style: body),
                      ),
                  ],
                  onChanged: (value) => setState(() => _address = value),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ] else if (_address != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${_address!.address}:$_port',
                style: mono.copyWith(color: C.muted, fontSize: 13),
              ),
            ),
          const Text(
            'Keep this window open while the phone syncs. Both devices must be '
            'on the same Wi-Fi, and Windows Firewall has to allow this app on '
            'private networks.',
            style: TextStyle(color: C.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                onPressed: _tokens == null ? null : _newCode,
                child: const Text('Show new QR code'),
              ),
              const SizedBox(width: 12),
              AppButton(
                primary: true,
                onPressed: _close,
                child: const Text('Done'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
