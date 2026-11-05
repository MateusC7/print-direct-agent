import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/printer_model.dart';

/// Ítem de impresora con radio button, tipo badge y botón de copia.
class PrinterListItem extends StatelessWidget {
  final PrinterModel printer;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onCopy;

  const PrinterListItem({
    super.key,
    required this.printer,
    required this.selected,
    required this.onTap,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = selected
        ? (isDark ? kAccent.withValues(alpha: 0.12) : kAccentLight)
        : Colors.transparent;
    final border = selected ? kAccent : Colors.transparent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.kRadius),
        border: Border.all(color: border, width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.kRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              // Radio visual
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? kAccent : (isDark ? kBorderDark : kBorderLight),
                    width: selected ? 4.5 : 1.5,
                  ),
                  color: selected ? Colors.white : Colors.transparent,
                ),
              ),
              const SizedBox(width: 10),

              // Icono por tipo
              Icon(
                _iconForType(printer.type),
                size: 16,
                color: selected
                    ? kAccent
                    : (isDark ? kTextSecondaryDark : kTextSecondaryLight),
              ),
              const SizedBox(width: 8),

              // Nombre
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      printer.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color: isDark ? kTextPrimaryDark : kTextPrimaryLight,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (printer.displayAddress.isNotEmpty)
                      Text(
                        printer.displayAddress,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? kTextSecondaryDark
                              : kTextSecondaryLight,
                        ),
                      ),
                  ],
                ),
              ),

              // Badge tipo
              _TypeBadge(type: printer.type),
              const SizedBox(width: 6),

              // Botón copiar
              if (onCopy != null)
                _CopyButton(onTap: onCopy!),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForType(PrinterType t) => switch (t) {
        PrinterType.local => Icons.print_outlined,
        PrinterType.network => Icons.wifi_outlined,
        PrinterType.bluetooth => Icons.bluetooth,
        PrinterType.sunmi => Icons.point_of_sale_outlined,
        PrinterType.scale => Icons.scale_outlined,
        PrinterType.scanner => Icons.qr_code_scanner_outlined,
        PrinterType.display => Icons.tv_outlined,
      };
}

class _TypeBadge extends StatelessWidget {
  final PrinterType type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      PrinterType.local => ('Local', const Color(0xFF0F9B58)),
      PrinterType.network => ('Red', kAccent),
      PrinterType.bluetooth => ('BT', const Color(0xFF0B5FCB)),
      PrinterType.sunmi => ('Sunmi', const Color(0xFFE9A624)),
      PrinterType.scale => ('Báscula', Colors.purple),
      PrinterType.scanner => ('Lector', Colors.teal),
      PrinterType.display => ('Pantalla', Colors.indigo),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  final VoidCallback onTap;
  const _CopyButton({required this.onTap});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.onTap();
        setState(() => _copied = true);
        Future.delayed(const Duration(seconds: 2),
            () => mounted ? setState(() => _copied = false) : null);
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          _copied ? Icons.check : Icons.copy_outlined,
          key: ValueKey(_copied),
          size: 14,
          color: _copied
              ? kSuccess
              : (Theme.of(context).brightness == Brightness.dark
                  ? kTextSecondaryDark
                  : kTextSecondaryLight),
        ),
      ),
    );
  }
}
