import 'dart:async';
import 'dart:io';

/// Opens a TCP connection and reports whether it succeeded.
typedef TcpProbe = Future<bool> Function(String host, int port, Duration timeout);

/// Finds network thermal printers (ESC/POS over TCP, port 9100 by default) by
/// probing every host of the device's /24 subnet. No popups, no extra
/// permissions beyond INTERNET.
class NetworkPrinterScanner {
  NetworkPrinterScanner({TcpProbe? probe}) : _probe = probe ?? _tcpProbe;

  final TcpProbe _probe;

  static Future<bool> _tcpProbe(String host, int port, Duration timeout) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  /// All host addresses (1-254) of the /24 subnet of [localIp], excluding
  /// [localIp] itself. Returns an empty list for anything that is not a valid
  /// private IPv4 address.
  static List<String> subnetHosts(String localIp) {
    final parts = localIp.split('.');
    if (parts.length != 4) return const [];
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((o) => o == null || o < 0 || o > 255)) return const [];
    final prefix = '${octets[0]}.${octets[1]}.${octets[2]}';
    return [
      for (var host = 1; host <= 254; host++)
        if (host != octets[3]) '$prefix.$host',
    ];
  }

  /// Probes [hosts] on [port] with at most [concurrency] simultaneous
  /// connections. Hosts that answer are returned sorted, and reported to
  /// [onFound] as soon as they are discovered.
  Future<List<String>> scan({
    required List<String> hosts,
    int port = 9100,
    Duration timeout = const Duration(milliseconds: 600),
    int concurrency = 48,
    void Function(String host)? onFound,
  }) async {
    final found = <String>[];
    var next = 0;

    Future<void> worker() async {
      while (next < hosts.length) {
        final host = hosts[next++];
        if (await _probe(host, port, timeout)) {
          found.add(host);
          onFound?.call(host);
        }
      }
    }

    final workers = concurrency < hosts.length ? concurrency : hosts.length;
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);

    found.sort((a, b) => _ipKey(a).compareTo(_ipKey(b)));
    return found;
  }

  static int _ipKey(String ip) {
    final p = ip.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    return p.length == 4 ? (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3] : 0;
  }
}
