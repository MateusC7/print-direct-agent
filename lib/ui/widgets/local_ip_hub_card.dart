import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';

/// Tarjeta de Alto Impacto Visual (Corporate Tier) para Visualización de la IP Local.
/// Diseñada con arquitectura limpia, sin solapamientos, con desenfoque gaussiano
/// y branding estricto en blanco y azul corporativo (#0004AD).
class LocalIpHubCard extends StatefulWidget {
  final int port;
  final String lang;
  final Function(String)? onLog;

  const LocalIpHubCard({
    super.key,
    required this.port,
    required this.lang,
    this.onLog,
  });

  @override
  State<LocalIpHubCard> createState() => _LocalIpHubCardState();
}

class _LocalIpHubCardState extends State<LocalIpHubCard> with SingleTickerProviderStateMixin {
  String _localIp = '';
  bool _isLoadingIp = true;
  bool _hideIp = false;
  bool _copied = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _detectRealLanIp();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// Prioriza la IP física real de la red Wi-Fi o Ethernet del local
  Future<void> _detectRealLanIp() async {
    setState(() => _isLoadingIp = true);
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      String? primaryLanIp;
      String? secondaryLanIp;

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        final isVirtual = name.contains('virtual') ||
            name.contains('wsl') ||
            name.contains('docker') ||
            name.contains('vethernet') ||
            name.contains('loopback');

        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final ip = addr.address;

          if (ip.startsWith('192.168.')) {
            if (!isVirtual) {
              primaryLanIp = ip;
              break;
            } else {
              secondaryLanIp ??= ip;
            }
          } else if (ip.startsWith('10.')) {
            if (!isVirtual) {
              primaryLanIp = ip;
              break;
            } else {
              secondaryLanIp ??= ip;
            }
          } else if (ip.startsWith('172.')) {
            secondaryLanIp ??= ip;
          }
        }
        if (primaryLanIp != null) break;
      }

      final detected = primaryLanIp ?? secondaryLanIp;
      if (mounted) {
        setState(() {
          _localIp = detected ?? '127.0.0.1';
          _isLoadingIp = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _localIp = '127.0.0.1';
          _isLoadingIp = false;
        });
      }
    }
  }

  String get _fullUrl => 'http://${_localIp.isNotEmpty ? _localIp : '127.0.0.1'}:${widget.port}';

  void _copyToClipboard() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: _fullUrl));
    setState(() => _copied = true);
    widget.onLog?.call('[INFO] IP Local copiada: $_fullUrl');

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardBg = isDark ? kSurfaceDark : Colors.white;
    final borderColor = isDark ? kBorderDark : kBorderLight;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.25) : kAccent.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 1. Cabecera: Beacon + Título + Toggle Privacidad ──
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF10B981),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.5 * _pulseAnimation.value),
                          blurRadius: 8 * _pulseAnimation.value,
                          spreadRadius: 1.5 * _pulseAnimation.value,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),

              Expanded(
                child: Text(
                  'IP DE RED LOCAL · PUERTO ${widget.port}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: kAccent,
                  ),
                ),
              ),

              // Botón Privacidad
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _hideIp = !_hideIp);
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _hideIp
                        ? (isDark ? const Color(0xFF332005) : const Color(0xFFFEF3C7))
                        : (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _hideIp
                          ? const Color(0xFFF59E0B)
                          : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _hideIp ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        size: 13,
                        color: _hideIp ? const Color(0xFFD97706) : textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _hideIp ? 'Oculto' : 'Visible',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: _hideIp ? const Color(0xFFD97706) : textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── 2. Caja de la Dirección IP con Desenfoque Gaussiano ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Texto de la IP con filtro de desenfoque cuando _hideIp == true
                ImageFiltered(
                  imageFilter: _hideIp
                      ? ImageFilter.blur(sigmaX: 12, sigmaY: 12)
                      : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lan_outlined,
                        size: 18,
                        color: kAccent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _isLoadingIp
                            ? Text(
                                'Detectando IP de red...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textSecondary,
                                ),
                              )
                            : SelectableText(
                                _fullUrl,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                  color: textPrimary,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),

                // Overlay limpio con candado cuando está en modo privacidad
                if (_hideIp)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1609) : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          size: 13,
                          color: Color(0xFFD97706),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'IP Oculta (Modo Privacidad)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFD97706),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── 3. Botón de Acción: Copiar IP (Full-Width, Cero Solapamiento) ──
          SizedBox(
            height: 36,
            child: ElevatedButton.icon(
              onPressed: _copyToClipboard,
              style: ElevatedButton.styleFrom(
                backgroundColor: _copied ? const Color(0xFF10B981) : kAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: Icon(
                _copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 15,
                color: Colors.white,
              ),
              label: Text(
                _copied ? '¡Dirección IP Copiada!' : 'Copiar Dirección IP',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ── 4. Nota de pie de tarjeta ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 13,
                  color: Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Usa esta dirección IP en la configuración de la Caja Local en tu sistema.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: textSecondary,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Alias para retrocompatibilidad
typedef SslBypassSection = LocalIpHubCard;
