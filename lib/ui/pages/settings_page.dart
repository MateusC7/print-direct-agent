import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/translations.dart';
import '../../core/constants.dart';
import '../../providers/settings_provider.dart';
import '../../providers/server_provider.dart';
import '../../providers/printer_provider.dart';
import '../../services/server/http_server_service.dart';
import '../../services/system/auto_update_service.dart';
import '../widgets/notion_card.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _portCtrl;
  late TextEditingController _tokenCtrl;
  bool _portChanged = false;
  bool _tokenChanged = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _portCtrl = TextEditingController(text: '${settings.port}');
    _portCtrl.addListener(() {
      final newPort = int.tryParse(_portCtrl.text);
      setState(() {
        _portChanged = newPort != null && newPort != settings.port;
      });
    });

    _tokenCtrl = TextEditingController(text: settings.apiToken);
    _tokenCtrl.addListener(() {
      setState(() {
        _tokenChanged = _tokenCtrl.text.trim() != settings.apiToken;
      });
    });
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _savePort(BuildContext context) async {
    final newPort = int.tryParse(_portCtrl.text);
    if (newPort == null || newPort < 1024 || newPort > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Puerto inválido (1024–65535)'),
          backgroundColor: kError,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final settings = context.read<SettingsProvider>();
    final server = context.read<ServerProvider>();
    final printers = context.read<PrinterProvider>();

    await settings.setPort(newPort);

    // Reiniciar el servidor con el nuevo puerto
    await HttpServerService.instance.restart(
      printerService: printers.service,
      port: newPort,
    );

    setState(() {
      _saving = false;
      _portChanged = false;
    });

    server.addLog('[INFO] Puerto actualizado a $newPort. Servidor reiniciado.');

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppTranslations.t(settings.lang, 'msg_restart')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: kSuccess,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  Future<void> _saveToken(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final server = context.read<ServerProvider>();
    final newToken = _tokenCtrl.text.trim();
    
    await settings.setApiToken(newToken);
    
    setState(() {
      _tokenChanged = false;
    });

    server.addLog('[INFO] Token de seguridad actualizado.');
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Token de seguridad guardado con éxito.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: kSuccess,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = AppTranslations.t;
    final lang = settings.lang;

    return Scaffold(
      backgroundColor: isDark ? kBgDark : kSurfaceLight,
      appBar: AppBar(
        title: Text(t(lang, 'btn_settings')),
        backgroundColor: isDark ? kBgDark : kBgLight,
        foregroundColor: isDark ? kTextPrimaryDark : kTextPrimaryLight,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: isDark ? kBorderDark : kBorderLight,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Apariencia ──────────────────────────────────────────────
          NotionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'APARIENCIA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                  ),
                ),
                const SizedBox(height: 16),

                // Tema
                Row(
                  children: [
                    Icon(Icons.dark_mode_outlined, size: 18,
                        color: isDark ? kTextPrimaryDark : kTextPrimaryLight),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t(lang, 'lbl_theme'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDark ? kTextPrimaryDark : kTextPrimaryLight,
                        ),
                      ),
                    ),
                    // Toggle tema
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? kSurfaceDark : kSurfaceLight,
                        borderRadius: BorderRadius.circular(AppTheme.kRadius),
                        border: Border.all(color: isDark ? kBorderDark : kBorderLight),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ThemeOption(
                            label: t(lang, 'theme_light'),
                            icon: Icons.light_mode_outlined,
                            selected: !isDark,
                            onTap: () => settings.setTheme('light'),
                          ),
                          _ThemeOption(
                            label: t(lang, 'theme_dark'),
                            icon: Icons.dark_mode_outlined,
                            selected: isDark,
                            onTap: () => settings.setTheme('dark'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                Container(height: 1, color: isDark ? kBorderDark : kBorderLight),
                const SizedBox(height: 16),

                // Idioma
                Row(
                  children: [
                    Icon(Icons.language_outlined, size: 18,
                        color: isDark ? kTextPrimaryDark : kTextPrimaryLight),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t(lang, 'lbl_lang'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDark ? kTextPrimaryDark : kTextPrimaryLight,
                        ),
                      ),
                    ),
                    // Selector de idioma
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? kSurfaceDark : kSurfaceLight,
                        borderRadius: BorderRadius.circular(AppTheme.kRadius),
                        border: Border.all(color: isDark ? kBorderDark : kBorderLight),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: AppTranslations.supportedLangs
                            .map((l) => _LangOption(
                                  code: l,
                                  label: AppTranslations.langName(l),
                                  selected: lang == l,
                                  onTap: () => settings.setLang(l),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Servidor ────────────────────────────────────────────────
          NotionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'SERVIDOR',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Icon(Icons.router_outlined, size: 18,
                        color: isDark ? kTextPrimaryDark : kTextPrimaryLight),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t(lang, 'lbl_port'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDark ? kTextPrimaryDark : kTextPrimaryLight,
                        ),
                      ),
                    ),
                    // Campo de puerto
                    SizedBox(
                      width: 90,
                      child: TextFormField(
                        controller: _portCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? kTextPrimaryDark : kTextPrimaryLight,
                        ),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),

                if (_portChanged) ...[
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : () => _savePort(context),
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: Colors.white),
                          )
                        : const Icon(Icons.save_outlined, size: 16),
                    label: Text(t(lang, 'btn_save')),
                  ),
                ],

                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? kSurfaceDark : kSurfaceLight,
                    borderRadius: BorderRadius.circular(AppTheme.kRadius),
                    border: Border.all(color: isDark ? kBorderDark : kBorderLight),
                  ),
                  child: Text(
                    'Puerto por defecto: ${AppConstants.defaultPort}\n'
                    'Rango válido: 1024 – 65535\n'
                    'El servidor se reiniciará automáticamente al guardar.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Seguridad ────────────────────────────────────────────────
          NotionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'SEGURIDAD',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 18,
                        color: isDark ? kTextPrimaryDark : kTextPrimaryLight),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Token de Seguridad',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDark ? kTextPrimaryDark : kTextPrimaryLight,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: TextFormField(
                        controller: _tokenCtrl,
                        obscureText: true,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? kTextPrimaryDark : kTextPrimaryLight,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Sin token (Inseguro)',
                          hintStyle: const TextStyle(fontSize: 12),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _tokenCtrl.text));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Token copiado al portapapeles'),
                                  behavior: SnackBarBehavior.floating,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                if (_tokenChanged) ...[
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _saveToken(context),
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: Text(t(lang, 'btn_save')),
                  ),
                ],

                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? kSurfaceDark : kSurfaceLight,
                    borderRadius: BorderRadius.circular(AppTheme.kRadius),
                    border: Border.all(color: isDark ? kBorderDark : kBorderLight),
                  ),
                  child: Text(
                    'Si configuras un token, todas las solicitudes entrantes desde el Punto de Venta deberán incluirlo en la cabecera de autorización Bearer.\n'
                    'Copia este token y pégalo en la configuración de la Caja Local en tu panel de control.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Sistema y Producción ────────────────────────────────────
          NotionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'SISTEMA Y PRODUCCIÓN',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                  ),
                ),
                const SizedBox(height: 16),

                // Auto-arranque con Windows / macOS
                if (Platform.isWindows || Platform.isMacOS) ...[
                  Row(
                    children: [
                      Icon(Icons.power_settings_new_outlined, size: 18,
                          color: isDark ? kTextPrimaryDark : kTextPrimaryLight),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              Platform.isMacOS
                                  ? 'Inicio automático con macOS'
                                  : 'Inicio automático con Windows',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: isDark ? kTextPrimaryDark : kTextPrimaryLight,
                              ),
                            ),
                            Text(
                              'El agente se ejecuta silenciosamente en segundo plano al encender el equipo',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Activo',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(height: 1, color: isDark ? kBorderDark : kBorderLight),
                  const SizedBox(height: 14),
                ],

                // Conexión Automática en la Nube
                Row(
                  children: [
                    Icon(Icons.cloud_sync_outlined, size: 18,
                        color: isDark ? kTextPrimaryDark : kTextPrimaryLight),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Conexión Automática en la Nube',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark ? kTextPrimaryDark : kTextPrimaryLight,
                            ),
                          ),
                          Text(
                            'Permite imprimir desde cualquier celular o PC sin configurar IPs ni certificados',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Activo',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                Container(height: 1, color: isDark ? kBorderDark : kBorderLight),
                const SizedBox(height: 14),

                // Auto-Sincronización de Red y Caja
                Row(
                  children: [
                    Icon(Icons.monitor_heart_outlined, size: 18,
                        color: isDark ? kTextPrimaryDark : kTextPrimaryLight),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Auto-Sincronización de Red y Caja',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark ? kTextPrimaryDark : kTextPrimaryLight,
                            ),
                          ),
                          Text(
                            'Detecta si la IP cambia tras reiniciar el router y mantiene vinculadas las impresoras',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Activo',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Acerca de ───────────────────────────────────────────────
          NotionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ACERCA DE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                  ),
                ),
                const SizedBox(height: 16),
                _AboutRow(icon: Icons.print_outlined,
                    label: 'Versión', value: AppConstants.appVersion, isDark: isDark),
                const SizedBox(height: 8),
                _AboutRow(icon: Icons.business_outlined,
                    label: 'Desarrollador', value: AppConstants.madeBy, isDark: isDark),
                const SizedBox(height: 8),
                _AboutRow(icon: Icons.info_outline,
                    label: 'Plataformas', value: 'Windows · macOS · Linux · Android', isDark: isDark),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Buscando actualizaciones...'),
                          duration: Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      final update = await AutoUpdateService.instance.checkForUpdates();
                      if (context.mounted) {
                        if (update != null) {
                          AutoUpdateService.instance.showUpdateDialog(context, update);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Tienes instalada la versión más reciente.'),
                              backgroundColor: kSuccess,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.sync_rounded, size: 16, color: kAccent),
                    label: const Text(
                      'Comprobar Actualizaciones',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kAccent),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kAccent, width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────
class _ThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? kAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.kRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: selected ? Colors.white : null),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: selected ? Colors.white : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LangOption extends StatelessWidget {
  final String code;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LangOption({
    required this.code,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? kAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.kRadius),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : null,
          ),
        ),
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  const _AboutRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16,
            color: isDark ? kTextSecondaryDark : kTextSecondaryLight),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? kTextPrimaryDark : kTextPrimaryLight,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
