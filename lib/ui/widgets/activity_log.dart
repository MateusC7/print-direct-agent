import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Log de actividad con autoscroll, timestamps y formato monospace.
class ActivityLog extends StatefulWidget {
  final List<String> entries;
  final VoidCallback? onClear;

  const ActivityLog({
    super.key,
    required this.entries,
    this.onClear,
  });

  @override
  State<ActivityLog> createState() => _ActivityLogState();
}

class _ActivityLogState extends State<ActivityLog> {
  final _scroll = ScrollController();
  bool _autoScroll = true;

  @override
  void didUpdateWidget(ActivityLog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_autoScroll && widget.entries.length != oldWidget.entries.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF141414) : const Color(0xFFF9F9F8);
    final border = isDark ? kBorderDark : kBorderLight;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.kRadiusMd),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header del log
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal_outlined,
                    size: 14,
                    color: isDark ? kTextSecondaryDark : kTextSecondaryLight),
                const SizedBox(width: 6),
                Text(
                  'LOG',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                  ),
                ),
                const Spacer(),
                // Auto-scroll toggle
                GestureDetector(
                  onTap: () => setState(() => _autoScroll = !_autoScroll),
                  child: Icon(
                    _autoScroll
                        ? Icons.vertical_align_bottom
                        : Icons.pause_outlined,
                    size: 14,
                    color: _autoScroll
                        ? kAccent
                        : (isDark ? kTextSecondaryDark : kTextSecondaryLight),
                  ),
                ),
                const SizedBox(width: 10),
                // Copiar todo
                GestureDetector(
                  onTap: () {
                    final text = widget.entries.join('\n');
                    Clipboard.setData(ClipboardData(text: text));
                  },
                  child: Icon(Icons.copy_outlined,
                      size: 14,
                      color: isDark ? kTextSecondaryDark : kTextSecondaryLight),
                ),
                if (widget.onClear != null) ...[
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: widget.onClear,
                    child: Icon(Icons.delete_outline,
                        size: 14,
                        color: isDark
                            ? kTextSecondaryDark
                            : kTextSecondaryLight),
                  ),
                ],
              ],
            ),
          ),

          // Contenido del log
          Expanded(
            child: widget.entries.isEmpty
                ? Center(
                    child: Text(
                      'Sin actividad registrada...',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                : NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n is UserScrollNotification) {
                        setState(() => _autoScroll = false);
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(10),
                      itemCount: widget.entries.length,
                      itemBuilder: (ctx, i) {
                        final entry = widget.entries[i];
                        final color = _colorForEntry(entry, isDark);
                        return Text(
                          entry,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            height: 1.6,
                            color: color,
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Color _colorForEntry(String entry, bool isDark) {
    if (entry.contains('[OK]') || entry.contains('✓')) return kSuccess;
    if (entry.contains('[ERROR]') || entry.contains('Error') || entry.contains('error')) {
      return kError;
    }
    if (entry.contains('[ADVERTENCIA]') || entry.contains('Warn') || entry.contains('warn')) {
      return kWarning;
    }
    if (entry.contains('[INFO]') || entry.contains('Iniciando')) {
      return kAccent;
    }
    return isDark ? kTextPrimaryDark.withValues(alpha: 0.8) : kTextPrimaryLight.withValues(alpha: 0.7);
  }
}
