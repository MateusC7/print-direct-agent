import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../services/server/http_server_service.dart';

/// Badge animado que muestra el estado del servidor.
class StatusBadge extends StatefulWidget {
  final ServerStatus status;
  final String? customLabel;

  const StatusBadge({
    super.key,
    required this.status,
    this.customLabel,
  });

  @override
  State<StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<StatusBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (label, color, pulsing) = _config(widget.status);
    final displayLabel = widget.customLabel ?? label;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Punto de estado
          if (pulsing)
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.5 + _pulse.value * 0.5),
                ),
              ),
            )
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
              ),
            ),
          const SizedBox(width: 6),
          Text(
            displayLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  static (String, Color, bool) _config(ServerStatus s) => switch (s) {
        ServerStatus.stopped => ('Detenido', kTextSecondaryLight, false),
        ServerStatus.starting => ('Iniciando...', kWarning, true),
        ServerStatus.running => ('En línea', kSuccess, false),
        ServerStatus.error => ('Error', kError, false),
      };
}
