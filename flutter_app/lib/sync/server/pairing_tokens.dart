import 'dart:convert';
import 'dart:math';

/// The short-lived secret inside the QR code: 16 random bytes, single use,
/// valid for five minutes, and only ever one at a time — issuing a new one
/// invalidates the old. OFFLINE_FIRST_SYNC_PLAYBOOK.md §5.1.
class PairingTokens {
  PairingTokens({int Function()? clock, Random? random})
    : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
      _random = random ?? Random.secure();

  static const lifetime = Duration(minutes: 5);
  static const _bytes = 16;

  final int Function() _clock;
  final Random _random;

  String? _token;
  int _expiresAt = 0;

  String? get current =>
      _token != null && _clock() < _expiresAt ? _token : null;

  int get expiresAt => _expiresAt;

  String issue() {
    final bytes = List<int>.generate(_bytes, (_) => _random.nextInt(256));
    _token = base64Url.encode(bytes).replaceAll('=', '');
    _expiresAt = _clock() + lifetime.inMilliseconds;
    return _token!;
  }

  /// True exactly once per issued token, and only before it expires.
  bool consume(String token) {
    if (_token == null || token != _token || _clock() >= _expiresAt) {
      return false;
    }
    clear();
    return true;
  }

  void clear() {
    _token = null;
    _expiresAt = 0;
  }
}
