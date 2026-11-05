import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/printer_model.dart';
import '../../providers/printer_provider.dart';

/// Busca impresoras Wi-Fi (ESC/POS 9100) y Bluetooth cercanas y permite
/// agregarlas con un toque, sin escribir IPs ni emparejar desde Ajustes.
class DiscoverPrintersDialog extends StatefulWidget {
  final PrinterProvider provider;

  const DiscoverPrintersDialog({super.key, required this.provider});

  @override
  State<DiscoverPrintersDialog> createState() => _DiscoverPrintersDialogState();
}

class _DiscoverPrintersDialogState extends State<DiscoverPrintersDialog> {
  final List<PrinterModel> _results = [];
  bool _scanningNetwork = true;
  bool _scanningBluetooth = Platform.isAndroid;

  bool get _scanning => _scanningNetwork || _scanningBluetooth;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  void _addResult(PrinterModel printer) {
    if (!mounted || _results.any((p) => p.id == printer.id)) return;
    setState(() => _results.add(printer));
  }

  Future<void> _startScan() async {
    setState(() {
      _results.clear();
      _scanningNetwork = true;
      _scanningBluetooth = Platform.isAndroid;
    });

    widget.provider
        .scanNetworkPrinters(onFound: _addResult)
        .catchError((_) => <PrinterModel>[])
        .whenComplete(() {
      if (mounted) setState(() => _scanningNetwork = false);
    });

    if (Platform.isAndroid) {
      widget.provider
          .discoverBluetoothPrinters()
          .then((list) => list.forEach(_addResult))
          .catchError((_) {})
          .whenComplete(() {
        if (mounted) setState(() => _scanningBluetooth = false);
      });
    }
  }

  Future<void> _add(PrinterModel printer) async {
    await widget.provider.addSavedPrinter(printer);
    if (mounted) setState(() => _results.removeWhere((p) => p.id == printer.id));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? kTextPrimaryDark : kTextPrimaryLight;

    return AlertDialog(
      backgroundColor: isDark ? kSurfaceDark : kBgLight,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.kRadiusLg),
        side: BorderSide(color: isDark ? kBorderDark : kBorderLight),
      ),
      title: Row(
        children: [
          Icon(Icons.search, size: 18, color: kAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Buscar impresoras',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor),
            ),
          ),
          if (_scanning)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: _results.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  _scanning
                      ? 'Buscando impresoras Wi-Fi${Platform.isAndroid ? ' y Bluetooth' : ''}…'
                      : 'No se encontraron impresoras nuevas. Verifica que estén '
                          'encendidas y en la misma red, o agrégalas por IP.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: textColor),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = _results[i];
                  final isBt = p.type == PrinterType.bluetooth;
                  return ListTile(
                    dense: true,
                    leading: Icon(isBt ? Icons.bluetooth : Icons.wifi, size: 18, color: kAccent),
                    title: Text(p.name, style: TextStyle(fontSize: 13, color: textColor)),
                    subtitle: Text(p.displayAddress, style: const TextStyle(fontSize: 11)),
                    trailing: TextButton(
                      onPressed: () => _add(p),
                      child: const Text('Agregar'),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: _scanning ? null : _startScan,
          child: const Text('Buscar de nuevo'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
