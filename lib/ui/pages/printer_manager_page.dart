import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/printer_model.dart';
import '../../providers/printer_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/printer/android_printer_service.dart';
import '../../services/settings_service.dart';
import '../../services/hardware/scale_service.dart';
import '../../services/hardware/scanner_service.dart';
import '../widgets/add_printer_dialog.dart';
import '../widgets/discover_printers_dialog.dart';
import '../widgets/add_iot_device_dialog.dart';

class PrinterManagerPage extends StatefulWidget {
  const PrinterManagerPage({super.key});

  @override
  State<PrinterManagerPage> createState() => _PrinterManagerPageState();
}

class _PrinterManagerPageState extends State<PrinterManagerPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _testLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PrinterProvider>().refresh();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final printersProvider = context.watch<PrinterProvider>();
    final settings = context.watch<SettingsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bluetoothPrinters = printersProvider.printers
        .where((p) => p.type == PrinterType.bluetooth)
        .toList();

    final systemAndIpPrinters = printersProvider.printers
        .where((p) => p.type != PrinterType.bluetooth)
        .toList();

    return Scaffold(
      backgroundColor: isDark ? kBgDark : kBgLight,
      appBar: AppBar(
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Administrador de Impresoras',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(
              icon: Icon(Icons.wifi, size: 18),
              text: 'Red IP / Sistema / IoT',
            ),
            Tab(
              icon: Icon(Icons.bluetooth, size: 18),
              text: 'Bluetooth',
            ),
          ],
        ),
        actions: [
          if (printersProvider.loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () => printersProvider.refresh(),
            ),
        ],
      ),
        body: TabBarView(
          controller: _tabController,
          children: [
            // ── TAB 1: RED IP / SISTEMA / IOT ─────────────────────────────────
            _buildSystemAndIpTab(systemAndIpPrinters, printersProvider, settings, isDark),

            // ── TAB 2: BLUETOOTH ──────────────────────────────────────────────
            _buildBluetoothTab(bluetoothPrinters, printersProvider, isDark),
          ],
        ),
      floatingActionButton: FloatingActionButton(
        onPressed: _testLoading ? null : () => _runPrintTest(context, printersProvider),
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        tooltip: 'Impresión de prueba',
        child: _testLoading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.print),
      ),
    );
  }

  Widget _buildBluetoothTab(
    List<PrinterModel> printers,
    PrinterProvider provider,
    bool isDark,
  ) {
    if (printers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bluetooth_disabled_outlined, size: 48, color: isDark ? kTextSecondaryDark : kTextSecondaryLight),
              const SizedBox(height: 12),
              Text(
                'No se detectaron impresoras Bluetooth vinculadas',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? kTextPrimaryDark : kTextPrimaryLight,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Vincule su impresora en los Ajustes de Bluetooth del dispositivo primero.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: printers.length,
      itemBuilder: (context, index) {
        final p = printers[index];
        final isSelected = provider.selected?.id == p.id;
        return _buildPrinterCard(p, isSelected, provider, isDark);
      },
    );
  }

  Widget _buildSystemAndIpTab(
    List<PrinterModel> printers,
    PrinterProvider provider,
    SettingsProvider settings,
    bool isDark,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (Platform.isAndroid) ...[
            OutlinedButton.icon(
              onPressed: () => AndroidPrinterService.openPrintSettings(),
              icon: const Icon(Icons.print_outlined, size: 16, color: Colors.orange),
              label: const Text('⚙️ Configurar Servicios Canon / HP / Sistema Android', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.orange, width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              ),
            ),
            const SizedBox(height: 10),
          ],
          // Búsqueda automática de impresoras Wi-Fi y Bluetooth (sin popups)
          FilledButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => DiscoverPrintersDialog(provider: provider),
            ),
            icon: const Icon(Icons.search, size: 16),
            label: const Text('Buscar impresoras', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(height: 10),
          // Acciones de agregar hardware
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => AddNetworkPrinterDialog(
                        lang: settings.lang,
                        onAdd: (name, ip, port) => provider.addNetworkPrinter(name, ip, port),
                      ),
                    );
                  },
                  icon: const Icon(Icons.wifi, size: 16, color: kAccent),
                  label: const Text('Agregar IP Red', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: kAccent, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => AddIotDeviceDialog(
                        onAdd: (device) => provider.addIotDevice(device),
                      ),
                    );
                  },
                  icon: const Icon(Icons.device_hub_outlined, size: 16, color: kAccent),
                  label: const Text('Agregar Dispositivo', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: kAccent, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: isDark ? kBorderDark : kBorderLight),
          const SizedBox(height: 12),

          // Lista de impresoras IP, locales y del sistema
          if (printers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'No hay dispositivos configurados',
                  style: TextStyle(color: isDark ? kTextSecondaryDark : kTextSecondaryLight),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: printers.length,
              itemBuilder: (context, index) {
                final p = printers[index];
                final isSelected = provider.selected?.id == p.id;
                
                // Opción para eliminar si es de red IP o báscula manual
                final canDelete = p.type == PrinterType.network || p.type == PrinterType.scale || p.type == PrinterType.scanner;

                return _buildPrinterCard(
                  p,
                  isSelected,
                  provider,
                  isDark,
                  trailing: canDelete
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline, color: kError, size: 18),
                          onPressed: () async {
                            if (p.type == PrinterType.network) {
                              await provider.removeNetworkPrinter(p);
                            } else {
                              // Quitar de dispositivos IoT
                              await provider.removeIotDevice(p);
                            }
                          },
                        )
                      : null,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPrinterCard(
    PrinterModel printer,
    bool isSelected,
    PrinterProvider provider,
    bool isDark, {
    Widget? trailing,
  }) {
    IconData icon;
    if (printer.address == 'system_print') {
      icon = Icons.picture_as_pdf_outlined;
    } else if (printer.type == PrinterType.sunmi) {
      icon = Icons.tablet_android;
    } else if (printer.type == PrinterType.bluetooth) {
      icon = Icons.bluetooth;
    } else if (printer.type == PrinterType.network) {
      icon = Icons.wifi;
    } else if (printer.type == PrinterType.scale) {
      icon = Icons.monitor_weight_outlined;
    } else if (printer.type == PrinterType.scanner) {
      icon = Icons.qr_code_scanner;
    } else {
      icon = Icons.print_outlined;
    }

    final cardBg = isDark ? kSurfaceDark : Colors.white;
    final borderCol = isDark ? kBorderDark : kBorderLight;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppTheme.kRadiusMd),
        border: Border.all(
          color: isSelected ? kAccent : borderCol,
          width: isSelected ? 1.8 : 1.0,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: kAccent.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => provider.select(printer),
          borderRadius: BorderRadius.circular(AppTheme.kRadiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? kAccent.withOpacity(0.12) 
                        : (isDark ? Colors.white10 : Colors.black54.withOpacity(0.04)),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: isSelected ? kAccent : (isDark ? kTextSecondaryDark : kTextSecondaryLight),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        printer.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          color: isDark ? kTextPrimaryDark : kTextPrimaryLight,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        printer.address == 'system_print'
                            ? 'Diálogo de impresión del sistema'
                            : (printer.address ?? 'Sin dirección'),
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                        ),
                      ),
                      if (printer.type == PrinterType.scale) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: ScaleService.instance.isConnected ? Colors.green : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              ScaleService.instance.isConnected
                                  ? 'Conectado · Peso: ${ScaleService.instance.currentWeight} ${ScaleService.instance.unit}'
                                  : 'Desconectado',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: ScaleService.instance.isConnected ? Colors.green : (isDark ? Colors.white60 : Colors.black54),
                              ),
                            ),
                            if (!ScaleService.instance.isConnected) ...[
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => ScaleService.instance.connect(printer.address ?? ''),
                                child: const Text(
                                  'Conectar',
                                  style: TextStyle(fontSize: 11, color: kAccent, decoration: TextDecoration.underline),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _SimulateButton(
                              label: '+0.5 kg',
                              onTap: () => ScaleService.instance.simulateWeight(ScaleService.instance.currentWeight + 0.5),
                              isDark: isDark,
                            ),
                            const SizedBox(width: 6),
                            _SimulateButton(
                              label: '+1.5 kg',
                              onTap: () => ScaleService.instance.simulateWeight(ScaleService.instance.currentWeight + 1.5),
                              isDark: isDark,
                            ),
                            const SizedBox(width: 6),
                            _SimulateButton(
                              label: 'Reset',
                              onTap: () => ScaleService.instance.simulateWeight(0.0),
                              isDark: isDark,
                              color: kError,
                            ),
                          ],
                        ),
                      ],
                      if (printer.type == PrinterType.scanner) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: ScannerService.instance.isConnected ? Colors.green : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                ScannerService.instance.isConnected
                                    ? 'Conectado ${ScannerService.instance.lastBarcode.isNotEmpty ? "· Último: ${ScannerService.instance.lastBarcode}" : "· Esperando lectura..."}'
                                    : 'Desconectado',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: ScannerService.instance.isConnected ? Colors.green : (isDark ? Colors.white60 : Colors.black54),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!ScannerService.instance.isConnected) ...[
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => ScannerService.instance.connect(printer.address ?? ''),
                                child: const Text(
                                  'Conectar',
                                  style: TextStyle(fontSize: 11, color: kAccent, decoration: TextDecoration.underline),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {}, // Bloquea propagación de tap a la tarjeta
                                child: SizedBox(
                                  height: 30,
                                  child: TextField(
                                    onSubmitted: (val) {
                                      if (val.trim().isNotEmpty) {
                                        ScannerService.instance.simulateScan(val.trim());
                                      }
                                    },
                                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.black),
                                    decoration: InputDecoration(
                                      hintText: 'Simular escaneo (Código)',
                                      hintStyle: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.black38),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      suffixIcon: const Icon(Icons.qr_code, size: 12),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        borderSide: BorderSide(color: isDark ? kBorderDark : kBorderLight),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        borderSide: BorderSide(color: isDark ? kBorderDark : kBorderLight),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (printer.type == PrinterType.display) ...[
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () async {
                            final port = SettingsService.instance.port;
                            final uri = Uri.parse('http://localhost:$port/display');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.open_in_new, size: 12, color: kAccent),
                              SizedBox(width: 4),
                              Text(
                                'Abrir vista de Pantalla de Cliente',
                                style: TextStyle(fontSize: 11, color: kAccent, decoration: TextDecoration.underline),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  trailing,
                  const SizedBox(width: 8),
                ],
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: isSelected ? 20 : 0,
                  height: 20,
                  curve: Curves.easeInOut,
                  child: AnimatedScale(
                    scale: isSelected ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutBack,
                    child: const Icon(Icons.check_circle_rounded, size: 20, color: kAccent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _runPrintTest(BuildContext context, PrinterProvider provider) async {
    if (provider.selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleccione una impresora primero.'),
          backgroundColor: kWarning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _testLoading = true);
    final res = await provider.printTest();
    setState(() => _testLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.success ? 'Impresión de prueba enviada con éxito' : 'Error: ${res.message}'),
          backgroundColor: res.success ? kSuccess : kError,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _SimulateButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isDark;
  final Color? color;

  const _SimulateButton({
    required this.label,
    required this.onTap,
    required this.isDark,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? (isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
          foregroundColor: color != null ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        onPressed: onTap,
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
