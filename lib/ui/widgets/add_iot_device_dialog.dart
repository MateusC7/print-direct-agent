import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/printer_model.dart';
import '../../services/hardware/scale_service.dart';
import '../../services/hardware/scanner_service.dart';

class AddIotDeviceDialog extends StatefulWidget {
  final Future<void> Function(PrinterModel device) onAdd;

  const AddIotDeviceDialog({super.key, required this.onAdd});

  @override
  State<AddIotDeviceDialog> createState() => _AddIotDeviceDialogState();
}

class _AddIotDeviceDialogState extends State<AddIotDeviceDialog> {
  final _nameCtrl = TextEditingController();
  final _addrCtrl = TextEditingController(text: 'usb');
  PrinterType _selectedType = PrinterType.scale;
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final name = _nameCtrl.text.trim();
      final addr = _addrCtrl.text.trim();
      final device = PrinterModel(
        name: name,
        type: _selectedType,
        address: addr,
      );
      await widget.onAdd(device);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? kSurfaceDark : kBgLight,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.kRadiusLg),
        side: BorderSide(color: isDark ? kBorderDark : kBorderLight),
      ),
      title: Row(
        children: [
          Icon(Icons.important_devices_outlined, size: 18, color: kAccent),
          const SizedBox(width: 8),
          Text(
            'Añadir Dispositivo IoT',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? kTextPrimaryDark : kTextPrimaryLight,
            ),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Name
            Text(
              'NOMBRE DEL DISPOSITIVO',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
              ),
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(hintText: 'Ej: Báscula Principal'),
              validator: (v) => (v == null || v.isEmpty) ? 'Nombre requerido' : null,
            ),
            const SizedBox(height: 12),

            // Type
            Text(
              'TIPO DE DISPOSITIVO',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: isDark ? kBorderDark : kBorderLight),
                borderRadius: BorderRadius.circular(AppTheme.kRadius),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<PrinterType>(
                  value: _selectedType,
                  isExpanded: true,
                  dropdownColor: isDark ? kSurfaceDark : kBgLight,
                  items: const [
                    DropdownMenuItem(value: PrinterType.scale, child: Text('Báscula')),
                    DropdownMenuItem(value: PrinterType.scanner, child: Text('Lector de Códigos')),
                    DropdownMenuItem(value: PrinterType.display, child: Text('Pantalla de Cliente')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedType = v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            Text(
              _selectedType == PrinterType.display
                  ? 'TIPO DE CONEXIÓN DE LA PANTALLA'
                  : 'PUERTO DE CONEXIÓN (COM / USB)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
              ),
            ),
            const SizedBox(height: 4),
            if (_selectedType == PrinterType.display) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: isDark ? kBorderDark : kBorderLight),
                  borderRadius: BorderRadius.circular(AppTheme.kRadius),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _addrCtrl.text.isNotEmpty ? _addrCtrl.text : 'HDMI',
                    isExpanded: true,
                    dropdownColor: isDark ? kSurfaceDark : kBgLight,
                    items: const [
                      DropdownMenuItem(
                        value: 'HDMI',
                        child: Text('HDMI / Monitor Secundario Conectado'),
                      ),
                      DropdownMenuItem(
                        value: 'Web / Red',
                        child: Text('Web / Tablet o Celular en Red'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _addrCtrl.text = val);
                    },
                  ),
                ),
              ),
            ] else ...[
              TextFormField(
                controller: _addrCtrl,
                decoration: InputDecoration(
                  hintText: 'Ej: COM1 o /dev/ttyUSB0',
                  suffixIcon: FutureBuilder<List<String>>(
                    future: _selectedType == PrinterType.scale 
                        ? ScaleService.instance.getAvailablePorts()
                        : ScannerService.instance.getAvailablePorts(),
                    builder: (context, snapshot) {
                      final ports = snapshot.data ?? [];
                      if (ports.isEmpty) return const SizedBox.shrink();
                      return PopupMenuButton<String>(
                        icon: const Icon(Icons.arrow_drop_down),
                        onSelected: (val) {
                          setState(() {
                            _addrCtrl.text = val;
                          });
                        },
                        itemBuilder: (context) => ports.map((p) => PopupMenuItem(value: p, child: Text(p))).toList(),
                      );
                    },
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Puerto requerido' : null,
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: kError, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancelar',
            style: TextStyle(
              color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Añadir Dispositivo'),
        ),
      ],
    );
  }
}
