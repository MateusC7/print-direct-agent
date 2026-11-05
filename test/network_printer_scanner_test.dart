import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:print_app/services/printer/network_printer_scanner.dart';

void main() {
  group('subnetHosts', () {
    test('covers the /24 subnet without the local address', () {
      final hosts = NetworkPrinterScanner.subnetHosts('192.168.1.20');
      expect(hosts.length, 253);
      expect(hosts, isNot(contains('192.168.1.20')));
      expect(hosts.first, '192.168.1.1');
      expect(hosts.last, '192.168.1.254');
    });

    test('rejects invalid addresses', () {
      expect(NetworkPrinterScanner.subnetHosts('not-an-ip'), isEmpty);
      expect(NetworkPrinterScanner.subnetHosts('10.0.0'), isEmpty);
      expect(NetworkPrinterScanner.subnetHosts('10.0.0.300'), isEmpty);
    });
  });

  group('scan', () {
    test('returns only responding hosts, sorted numerically', () async {
      final open = {'10.0.0.100', '10.0.0.9', '10.0.0.20'};
      final scanner = NetworkPrinterScanner(
        probe: (host, port, timeout) async => open.contains(host) && port == 9100,
      );
      final reported = <String>[];
      final found = await scanner.scan(
        hosts: NetworkPrinterScanner.subnetHosts('10.0.0.5'),
        onFound: reported.add,
      );
      expect(found, ['10.0.0.9', '10.0.0.20', '10.0.0.100']);
      expect(reported.toSet(), open);
    });

    test('never exceeds the concurrency limit', () async {
      var active = 0;
      var peak = 0;
      final scanner = NetworkPrinterScanner(probe: (h, p, t) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        active--;
        return false;
      });
      await scanner.scan(
        hosts: NetworkPrinterScanner.subnetHosts('10.0.0.5'),
        concurrency: 8,
      );
      expect(peak, lessThanOrEqualTo(8));
    });

    test('detects a real listening TCP socket', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final found = await NetworkPrinterScanner().scan(
        hosts: ['127.0.0.1'],
        port: server.port,
      );
      expect(found, ['127.0.0.1']);
    });
  });
}
