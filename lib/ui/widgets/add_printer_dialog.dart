import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/translations.dart';
import '../../core/constants.dart';

/// Diálogo para añadir una impresora de red (IP + Puerto).
/// Usado principalmente en Android pero disponible en todas las plataformas.
class AddNetworkPrinterDialog extends StatefulWidget {
  final String lang;
  final Future<void> Function(String name, String ip, int port) onAdd;

  const AddNetworkPrinterDialog({
    super.key,
    required this.lang,
    required this.onAdd,
  });

  @override
  State<AddNetworkPrinterDialog> createState() => _AddNetworkPrinterDialogState();
}

class _AddNetworkPrinterDialogState extends State<AddNetworkPrinterDialog> {
  final _nameCtrl = TextEditingController();
  final _ipCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '${AppConstants.defaultNetworkPort}');
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ipCtrl.dispose();
    _portCtrl.dispose();
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
      final ip = _ipCtrl.text.trim();
      final port = int.tryParse(_portCtrl.text.trim()) ?? AppConstants.defaultNetworkPort;
      await widget.onAdd(name, ip, port);
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
    final t = AppTranslations.t;
    final lang = widget.lang;

    return AlertDialog(
      backgroundColor: isDark ? kSurfaceDark : kBgLight,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.kRadiusLg),
        side: BorderSide(color: isDark ? kBorderDark : kBorderLight),
      ),
      title: Row(
        children: [
          Icon(Icons.wifi_outlined, size: 18, color: kAccent),
          const SizedBox(width: 8),
          Text(
            t(lang, 'lbl_network'),
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
            // Nombre
            _InputField(
              controller: _nameCtrl,
              label: 'Nombre de la Impresora',
              hint: 'Ej: Cocina, Barra, etc.',
              isDark: isDark,
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 12),

            // IP
            _InputField(
              controller: _ipCtrl,
              label: t(lang, 'lbl_ip'),
              hint: '192.168.1.100',
              isDark: isDark,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              validator: (v) {
                if (v == null || v.isEmpty) return 'IP requerida';
                final parts = v.split('.');
                if (parts.length != 4) return 'IP inválida';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Puerto
            _InputField(
              controller: _portCtrl,
              label: t(lang, 'lbl_printer_port'),
              hint: '9100',
              isDark: isDark,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                if (v == null || v.isEmpty) return 'Puerto requerido';
                final p = int.tryParse(v);
                if (p == null || p < 1 || p > 65535) return 'Puerto inválido (1-65535)';
                return null;
              },
            ),

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
              : Text(t(lang, 'btn_add')),
        ),
      ],
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool isDark;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  const _InputField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.isDark,
    required this.keyboardType,
    this.inputFormatters,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}
