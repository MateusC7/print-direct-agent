import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Botón primario de acción con acento corporativo #004AAD.
class NotionButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool small;
  final bool outlined;
  final Color? color;

  const NotionButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.small = false,
    this.outlined = false,
    this.color,
  });

  @override
  State<NotionButton> createState() => _NotionButtonState();
}

class _NotionButtonState extends State<NotionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.color ?? kAccent;
    final height = widget.small ? 32.0 : 40.0;
    final fontSize = widget.small ? 12.0 : 14.0;
    final hPad = widget.small ? 12.0 : 16.0;

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) => _ctrl.reverse(),
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: widget.outlined
            ? _buildOutlined(height, fontSize, hPad)
            : _buildFilled(bg, height, fontSize, hPad),
      ),
    );
  }

  Widget _buildFilled(Color bg, double height, double fontSize, double hPad) {
    return SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: widget.loading ? null : widget.onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          disabledBackgroundColor: bg.withValues(alpha: 0.5),
          padding: EdgeInsets.symmetric(horizontal: hPad),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.kRadius),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
        ),
        child: _buildChild(),
      ),
    );
  }

  Widget _buildOutlined(double height, double fontSize, double hPad) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? kBorderDark : kBorderLight;
    final textColor = isDark ? kTextPrimaryDark : kTextPrimaryLight;

    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: widget.loading ? null : widget.onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: textColor,
          side: BorderSide(color: borderColor),
          padding: EdgeInsets.symmetric(horizontal: hPad),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.kRadius),
          ),
          textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500),
        ),
        child: _buildChild(),
      ),
    );
  }

  Widget _buildChild() {
    if (widget.loading) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white,
        ),
      );
    }
    if (widget.icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, size: widget.small ? 14 : 16),
          const SizedBox(width: 6),
          Text(widget.label),
        ],
      );
    }
    return Text(widget.label);
  }
}
