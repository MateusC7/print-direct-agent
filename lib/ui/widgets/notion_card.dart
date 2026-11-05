import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Card Notion-style: borde fino, sin elevación, esquinas sutiles.
class NotionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;

  const NotionCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = backgroundColor ??
        (isDark ? kSurfaceDark : kBgLight);
    final border = isDark ? kBorderDark : kBorderLight;

    final card = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.kRadiusMd),
        border: Border.all(color: border, width: 1),
        boxShadow: isDark ? [] : AppTheme.subtleShadow,
      ),
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.kRadiusMd),
        child: card,
      );
    }
    return card;
  }
}

/// Encabezado de sección estilo Notion con label en mayúsculas.
class NotionSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const NotionSectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? kTextSecondaryDark : kTextSecondaryLight;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Divider Notion-style.
class NotionDivider extends StatelessWidget {
  final double indent;
  const NotionDivider({super.key, this.indent = 0});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      height: 1,
      thickness: 1,
      indent: indent,
      color: isDark ? kDividerDark : kDividerLight,
    );
  }
}
