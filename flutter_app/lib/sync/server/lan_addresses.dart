import 'dart:io';

/// The addresses a phone could reach this PC on, best guess first.
///
/// Virtual adapters (WSL, Docker, VPNs, hypervisors) look exactly like real
/// ones to `NetworkInterface` but are never the right answer, so they go last.
/// OFFLINE_FIRST_SYNC_PLAYBOOK.md §5.1.
final _virtual = RegExp(
  r'vethernet|virtual|vmware|vbox|virtualbox|hyper-?v|wsl|docker|vpn|tap|tun|'
  r'loopback|bluetooth|tailscale|zerotier|radmin',
  caseSensitive: false,
);

bool _isPrivate(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return false;
  final a = int.tryParse(parts[0]) ?? -1;
  final b = int.tryParse(parts[1]) ?? -1;
  if (a == 10) return true;
  if (a == 192 && b == 168) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  return false;
}

class LanAddress {
  const LanAddress(this.address, this.interfaceName);

  final String address;
  final String interfaceName;

  @override
  String toString() => '$address ($interfaceName)';
}

/// Read fresh every time the sync window opens — the network changes.
Future<List<LanAddress>> lanAddresses() async {
  final List<NetworkInterface> interfaces;
  try {
    interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
  } on Exception {
    return const [];
  }

  final found = <LanAddress>[];
  for (final nic in interfaces) {
    for (final address in nic.addresses) {
      if (address.isLoopback) continue;
      if (!_isPrivate(address.address)) continue;
      found.add(LanAddress(address.address, nic.name));
    }
  }

  found.sort((a, b) {
    final aVirtual = _virtual.hasMatch(a.interfaceName);
    final bVirtual = _virtual.hasMatch(b.interfaceName);
    if (aVirtual != bVirtual) return aVirtual ? 1 : -1;
    final aHome = a.address.startsWith('192.168.');
    final bHome = b.address.startsWith('192.168.');
    if (aHome != bHome) return aHome ? -1 : 1;
    return a.address.compareTo(b.address);
  });
  return found;
}
