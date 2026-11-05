import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/translations.dart';
import '../../providers/settings_provider.dart';
import '../../providers/server_provider.dart';
import '../../providers/printer_provider.dart';
import '../../services/server/http_server_service.dart';
import '../../services/settings_service.dart';
import '../widgets/activity_log.dart';
import '../widgets/local_ip_hub_card.dart';
import '../widgets/status_badge.dart';
import '../widgets/add_printer_dialog.dart';
import '../widgets/discover_printers_dialog.dart';
import '../widgets/add_iot_device_dialog.dart';
import '../../models/printer_model.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/hardware/scale_service.dart';
import '../../services/hardware/scanner_service.dart';
import '../../services/server/odoo_device_sync_service.dart';
import '../../services/server/cloud_relay_service.dart';
import 'pos_web_page.dart';
import 'printer_manager_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late TextEditingController _odooUrlCtrl;
  late TextEditingController _apiTokenCtrl;
  late TextEditingController _portCtrl;
  StreamSubscription<Map<String, String>>? _externalSyncSub;

  String _protocol = 'https';

  bool _portChanged = false;
  bool _savingPort = false;
  bool _testLoading = false;
  bool _isSavingOdooUrl = false;

  Future<void> _saveOdooUrlFromSidebar({bool isAutoSync = false}) async {
    final url = _odooUrlCtrl.text.trim();
    final token = _apiTokenCtrl.text.trim();

    if (url.isEmpty) {
      if (!isAutoSync) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Por favor ingresa la dirección de tu sistema (ej: tu-negocio.com)'),
              ],
            ),
            backgroundColor: kWarning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (token.isEmpty) {
      if (!isAutoSync) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Por favor ingresa la clave de seguridad de tu caja.'),
              ],
            ),
            backgroundColor: kWarning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() => _isSavingOdooUrl = true);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final printers = Provider.of<PrinterProvider>(context, listen: false);
    final server = Provider.of<ServerProvider>(context, listen: false);

    await settings.setOdooUrl(url);
    await settings.setApiToken(token);
    await settings.setOdooProtocol(_protocol);
    await settings.setEnableCloudRelay(true);
    server.addLog('[INFO] Servidor del sistema configurado: $url');
    server.addLog('[INFO] Clave de seguridad configurada.');

    await OdooDeviceSyncService.instance.syncWithOdoo(printers: printers.printers);
    await CloudRelayService.instance.connect();

    if (mounted) {
      setState(() => _isSavingOdooUrl = false);
      if (!isAutoSync) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Configuración guardada y canal conectado exitosamente.'),
              ],
            ),
            backgroundColor: kSuccess,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _testConnectionNow() async {
    final url = _odooUrlCtrl.text.trim();
    final token = _apiTokenCtrl.text.trim();

    if (url.isEmpty || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa la URL y el Token antes de probar la conexión.'),
          backgroundColor: kWarning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final printers = Provider.of<PrinterProvider>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Probando conexión con el servidor...'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );

    await CloudRelayService.instance.connect();
    final res = await OdooDeviceSyncService.instance.syncWithOdoo(printers: printers.printers);

    if (mounted) {
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Conexión exitosa. Impresoras sincronizadas con el servidor.'),
              ],
            ),
            backgroundColor: kSuccess,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Error conectando: ${res['message']}')),
              ],
            ),
            backgroundColor: kError,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();

    _odooUrlCtrl = TextEditingController(text: settings.odooUrl);
    _apiTokenCtrl = TextEditingController(text: settings.apiToken);
    _portCtrl = TextEditingController(text: '${settings.port}');
    _protocol = settings.odooProtocol;

    // Auto-conectar Cloud Relay al iniciar si hay URL
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (settings.odooUrl.isNotEmpty) {
        CloudRelayService.instance.connect();
      }
    });

    _portCtrl.addListener(() {
      final newPort = int.tryParse(_portCtrl.text);
      if (mounted) {
        setState(() {
          _portChanged = newPort != null && newPort != settings.port;
        });
      }
    });

    // Auto-lanzar POS si está configurado y hay URL de servidor
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (settings.autoLaunchPos && settings.odooUrl.isNotEmpty) {
        _pushPremiumPage(context, const PosWebPage());
      }
    });

    // Escuchar auto-sincronización remota (1-clic Detectar y Vincular)
    _externalSyncSub = SettingsService.onExternalSettingsSync.stream.listen((data) async {
      if (!mounted) return;
      final serverUrl = data['odoo_url'];
      final token = data['api_token'];
      if (serverUrl != null && serverUrl.isNotEmpty) {
        _odooUrlCtrl.text = serverUrl;
      }
      if (token != null && token.isNotEmpty) {
        _apiTokenCtrl.text = token;
      }
      // Actualizar automáticamente los ajustes y conectar el canal
      await _saveOdooUrlFromSidebar(isAutoSync: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'Dispositivo vinculado y conectado automáticamente.',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            backgroundColor: kSuccess,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      }
    });
  }

  void _pushPremiumPage(BuildContext context, Widget page) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;

          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);

          return SlideTransition(
            position: offsetAnimation,
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _externalSyncSub?.cancel();
    _odooUrlCtrl.dispose();
    _apiTokenCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _loginAndLaunch() async {
    final serverUrl = _odooUrlCtrl.text.trim();
    if (serverUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, configure la dirección del servidor.'),
          backgroundColor: kWarning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final settings = context.read<SettingsProvider>();

    // Guardar protocolo y servidor
    await settings.setOdooUrl(serverUrl);
    await settings.setOdooProtocol(_protocol);

    // Sincronizar automáticamente la caja y sus impresoras con Odoo (print_direct_odoo)
    final printers = context.read<PrinterProvider>();
    OdooDeviceSyncService.instance.syncWithOdoo(printers: printers.printers);

    if (mounted) {
      _pushPremiumPage(context, const PosWebPage());
    }
  }

  Future<void> _savePort() async {
    final newPort = int.tryParse(_portCtrl.text);
    if (newPort == null || newPort < 1024 || newPort > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Puerto inválido (1024–65535)'),
          backgroundColor: kError,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _savingPort = true);
    final settings = context.read<SettingsProvider>();
    final printers = context.read<PrinterProvider>();

    await settings.setPort(newPort);
    await HttpServerService.instance.restart(
      printerService: printers.service,
      port: newPort,
    );

    if (mounted) {
      setState(() {
        _savingPort = false;
        _portChanged = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Puerto actualizado. Servidor local reiniciado.'),
          backgroundColor: kSuccess,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return _buildWindowsDesktopLayout(context);
    }
    return _buildMobileLayout(context);
  }

  Widget _buildMobileLayout(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      backgroundColor: isDark ? kBgDark : kSurfaceLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: isDark ? Colors.white : kTextPrimaryLight),
            onPressed: () => _showAdvancedSettingsBottomSheet(context),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

              // ── CABECERA CORPORATIVA DE SOFTWARE RESTAURANT ──
              Center(
                child: Column(
                  children: [
                    Image.asset(
                      'assets/images/logo_restaurant.png',
                      height: 80,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: kAccent.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.restaurant_menu_rounded,
                          color: kAccent,
                          size: 58,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Software Restaurante',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: kAccent,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppTranslations.t(settings.lang, 'lbl_print_agent'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // ── SELECTOR HTTP / HTTPS (Estilo segmentado mockup) ──
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: isDark ? kSurfaceDark : Colors.black54.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(AppTheme.kRadiusMd),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _protocol = 'http'),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _protocol == 'http' ? kAccent : Colors.transparent,
                            borderRadius: BorderRadius.circular(AppTheme.kRadiusMd),
                          ),
                          child: Text(
                            'HTTP',
                            style: TextStyle(
                              color: _protocol == 'http' ? Colors.white : (isDark ? kTextSecondaryDark : kTextSecondaryLight),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _protocol = 'https'),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _protocol == 'https' ? kAccent : Colors.transparent,
                            borderRadius: BorderRadius.circular(AppTheme.kRadiusMd),
                          ),
                          child: Text(
                            'HTTPS',
                            style: TextStyle(
                              color: _protocol == 'https' ? Colors.white : (isDark ? kTextSecondaryDark : kTextSecondaryLight),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── FORMULARIO DE CONEXIÓN ──
              // 1. Servidor
              TextFormField(
                controller: _odooUrlCtrl,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: AppTranslations.t(settings.lang, 'lbl_system_address'),
                  hintText: AppTranslations.t(settings.lang, 'hint_sys_addr'),
                  prefixIcon: const Icon(Icons.public, size: 20, color: kAccent),
                  fillColor: isDark ? kSurfaceDark : Colors.white,
                  filled: true,
                ),
              ),
              const SizedBox(height: 20),

              // ── ACCIONES ──
              // Botón Iniciar POS
              ElevatedButton.icon(
                onPressed: _loginAndLaunch,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: Text(AppTranslations.t(settings.lang, 'btn_access_pos')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.kRadiusMd),
                  ),
                  elevation: 2,
                ),
              ),

              const SizedBox(height: 12),

              OutlinedButton.icon(
                onPressed: () {
                  _pushPremiumPage(context, const PrinterManagerPage());
                },
                icon: const Icon(Icons.print_outlined, size: 18),
                label: Text(AppTranslations.t(settings.lang, 'btn_config_printers')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kAccent,
                  side: const BorderSide(color: kAccent, width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.kRadiusMd),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── PANTALLA PRINCIPAL ADAPTATIVA PARA WINDOWS (DASHBOARD IOT BOX) ──
  Widget _buildWindowsDesktopLayout(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final server = context.watch<ServerProvider>();
    final printersProvider = context.watch<PrinterProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bluetoothPrinters = printersProvider.printers
        .where((p) => p.type == PrinterType.bluetooth)
        .toList();

    final systemAndIpPrinters = printersProvider.printers
        .where((p) => p.type != PrinterType.bluetooth)
        .toList();

    return Scaffold(
      backgroundColor: isDark ? kBgDark : const Color(0xFFF8FAFC),
      body: Row(
        children: [
          // ── COLUMNA IZQUIERDA: SIDEBAR MINIMALISTA AZUL Y BLANCO ──
          Container(
            width: 360,
            decoration: BoxDecoration(
              color: isDark ? kSurfaceDark : Colors.white,
              border: Border(
                right: BorderSide(
                  color: isDark ? kBorderDark : const Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cabecera Corporativa con Logo Oficial
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/images/logo_restaurant.png',
                        width: 34,
                        height: 34,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: kAccent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.restaurant_menu_rounded,
                            color: kAccent,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Software Restaurante',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: kAccent,
                                letterSpacing: 0.3,
                              ),
                            ),
                            Text(
                              AppTranslations.t(settings.lang, 'lbl_print_server'),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined, size: 20, color: Color(0xFF64748B)),
                        tooltip: AppTranslations.t(settings.lang, 'lbl_settings_system'),
                        onPressed: () => _showAdvancedSettingsDialog(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),

                // Contenido del Sidebar
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Card 1: Vinculación con el Servidor
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? kBgDark : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isDark ? kBorderDark : const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                AppTranslations.t(settings.lang, 'lbl_conn_system'),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: kAccent,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Campo 1: Servidor
                              Text(
                                AppTranslations.t(settings.lang, 'lbl_sys_addr_step'),
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 38,
                                child: TextFormField(
                                  controller: _odooUrlCtrl,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: InputDecoration(
                                    hintText: AppTranslations.t(settings.lang, 'hint_sys_addr'),
                                    hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                    prefixIcon: const Icon(Icons.public, size: 16, color: kAccent),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    filled: true,
                                    fillColor: isDark ? kSurfaceDark : Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Campo 2: Token de Seguridad
                              Text(
                                AppTranslations.t(settings.lang, 'lbl_sec_key_step'),
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 38,
                                child: TextFormField(
                                  controller: _apiTokenCtrl,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: InputDecoration(
                                    hintText: AppTranslations.t(settings.lang, 'hint_sec_key'),
                                    hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                    prefixIcon: const Icon(Icons.vpn_key_outlined, size: 16, color: kAccent),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    filled: true,
                                    fillColor: isDark ? kSurfaceDark : Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              // Botón Guardar y Conectar
                              ElevatedButton(
                                onPressed: _isSavingOdooUrl ? null : _saveOdooUrlFromSidebar,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                                child: _isSavingOdooUrl
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.sync_rounded, size: 16, color: Colors.white),
                                          const SizedBox(width: 8),
                                          Text(
                                            AppTranslations.t(settings.lang, 'btn_save_connect'),
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                          ),
                                        ],
                                      ),
                              ),
                              const SizedBox(height: 8),
                              // Botón Probar Conexión Ahora
                              OutlinedButton.icon(
                                onPressed: _testConnectionNow,
                                icon: const Icon(Icons.wifi_tethering_rounded, size: 14, color: kAccent),
                                label: Text(AppTranslations.t(settings.lang, 'btn_test_conn'), style: const TextStyle(fontSize: 11.5, color: kAccent)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: kAccent, width: 1.2),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Card 2: Estado del Canal Minimalista
                        AnimatedBuilder(
                          animation: CloudRelayService.instance,
                          builder: (context, _) {
                            final relay = CloudRelayService.instance;
                            final isConnected = relay.isConnected;
                            final isConnecting = relay.status == CloudRelayStatus.connecting;

                            Color badgeBg = isConnected
                                ? const Color(0xFFF0FDF4)
                                : (isConnecting ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC));
                            Color dotColor = isConnected
                                ? const Color(0xFF16A34A)
                                : (isConnecting ? const Color(0xFFD97706) : const Color(0xFF94A3B8));
                            Color textColor = isConnected
                                ? const Color(0xFF15803D)
                                : (isConnecting ? const Color(0xFFB45309) : const Color(0xFF64748B));
                            String statusText = isConnected
                                ? AppTranslations.t(settings.lang, 'status_active_connected')
                                : (isConnecting
                                    ? AppTranslations.t(settings.lang, 'status_connecting')
                                    : AppTranslations.t(settings.lang, 'status_disconnected'));
                            String descText = isConnected
                                ? AppTranslations.t(settings.lang, 'desc_active')
                                : (isConnecting
                                    ? AppTranslations.t(settings.lang, 'desc_connecting')
                                    : AppTranslations.t(settings.lang, 'desc_disconnected'));

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isDark ? kSurfaceDark : badgeBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isDark ? kBorderDark : (isConnected ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0)),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: dotColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          statusText,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: isDark ? Colors.white : textColor,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          descText,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: isDark ? kTextSecondaryDark : const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 18),

                        // Acciones Rápidas
                        OutlinedButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => Dialog(
                                backgroundColor: isDark ? kBgDark : Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: Container(
                                  width: 520,
                                  height: 420,
                                  padding: const EdgeInsets.all(16),
                                  child: ActivityLog(
                                    entries: server.logs,
                                    onClear: () {
                                      server.clearLog();
                                      Navigator.pop(ctx);
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.receipt_long_outlined, size: 16, color: kAccent),
                          label: Text(AppTranslations.t(settings.lang, 'btn_view_logs'), style: const TextStyle(fontSize: 11.5, color: kAccent)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(height: 10),

                        ElevatedButton.icon(
                          onPressed: () => _showAdvancedSettingsDialog(context),
                          icon: const Icon(Icons.tune_rounded, size: 16, color: Color(0xFF475569)),
                          label: Text(AppTranslations.t(settings.lang, 'btn_adv_settings'), style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569))),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? kBgDark : const Color(0xFFF1F5F9),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                // Footer sutil y elegante
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Text(
                    'Software Restaurante',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: isDark ? kTextSecondaryDark : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── COLUMNA DERECHA: ADMINISTRADOR DE HARDWARE ──
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Scaffold(
                backgroundColor: isDark ? kBgDark : kSurfaceLight,
                appBar: AppBar(
                  backgroundColor: isDark ? kSurfaceDark : Colors.white,
                  foregroundColor: isDark ? kTextPrimaryDark : kTextPrimaryLight,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  automaticallyImplyLeading: false,
                  title: Text(
                    AppTranslations.t(settings.lang, 'title_devices_hardware'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  bottom: TabBar(
                    indicatorColor: kAccent,
                    labelColor: kAccent,
                    unselectedLabelColor: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                    tabs: [
                      Tab(
                        icon: const Icon(Icons.wifi, size: 18),
                        text: AppTranslations.t(settings.lang, 'tab_network_iot'),
                      ),
                      Tab(
                        icon: const Icon(Icons.bluetooth, size: 18),
                        text: AppTranslations.t(settings.lang, 'lbl_bluetooth'),
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
                            child: CircularProgressIndicator(strokeWidth: 2, color: kAccent),
                          ),
                        ),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: () => printersProvider.refresh(),
                      ),
                  ],
                ),
                body: TabBarView(
                  children: [
                    // TAB 1: RED IP / SISTEMA / IOT
                    _buildDesktopSystemAndIpTab(systemAndIpPrinters, printersProvider, settings, isDark),

                    // TAB 2: BLUETOOTH
                    _buildDesktopBluetoothTab(bluetoothPrinters, printersProvider, settings, isDark),
                  ],
                ),
                floatingActionButton: FloatingActionButton(
                  onPressed: _testLoading ? null : () => _runDesktopPrintTest(context, printersProvider),
                  backgroundColor: kAccent,
                  foregroundColor: Colors.white,
                  tooltip: AppTranslations.t(settings.lang, 'tooltip_print_test'),
                  child: _testLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.print),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopBluetoothTab(
    List<PrinterModel> printers,
    PrinterProvider provider,
    SettingsProvider settings,
    bool isDark,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final uri = Uri.parse('ms-settings:bluetooth');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
                icon: const Icon(Icons.settings_bluetooth, size: 16, color: kAccent),
                label: Text(AppTranslations.t(settings.lang, 'btn_open_win_bt'), style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () => provider.refresh(),
                icon: const Icon(Icons.refresh, size: 16, color: Colors.white),
                label: Text(AppTranslations.t(settings.lang, 'btn_refresh'), style: const TextStyle(fontSize: 12, color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: kAccent),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (printers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bluetooth_disabled_outlined, size: 54, color: isDark ? kTextSecondaryDark : kTextSecondaryLight),
                  const SizedBox(height: 14),
                  Text(
                    AppTranslations.t(settings.lang, 'msg_no_bt_paired'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? kTextPrimaryDark : kTextPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppTranslations.t(settings.lang, 'msg_win_bt_instructions'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                    ),
                  ),
                ],
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
                return _buildDesktopPrinterCard(p, isSelected, provider, isDark);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopSystemAndIpTab(
    List<PrinterModel> printers,
    PrinterProvider provider,
    SettingsProvider settings,
    bool isDark,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => DiscoverPrintersDialog(provider: provider),
            ),
            icon: const Icon(Icons.search, size: 16),
            label: const Text('Buscar impresoras', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(height: 12),
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
                  label: Text(AppTranslations.t(settings.lang, 'btn_add_ip_printer'), style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: kAccent, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
                  label: Text(AppTranslations.t(settings.lang, 'btn_add_device'), style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: kAccent, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: isDark ? kBorderDark : kBorderLight),
          const SizedBox(height: 16),

          if (printers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  AppTranslations.t(settings.lang, 'msg_no_devices'),
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
                final isNativePrinter = p.address == 'system_print' || (p.type == PrinterType.local && !provider.iotDevices.any((d) => d.id == p.id));
                final canDelete = !isNativePrinter;

                return _buildDesktopPrinterCard(
                  p,
                  isSelected,
                  provider,
                  isDark,
                  trailing: canDelete
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline, color: kError, size: 18),
                          tooltip: AppTranslations.t(settings.lang, 'tooltip_delete_device'),
                          onPressed: () async {
                            if (p.type == PrinterType.network) {
                              await provider.removeNetworkPrinter(p);
                            } else {
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

  Widget _buildDesktopPrinterCard(
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
                          fontSize: 13,
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
                          fontSize: 10,
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

  Future<void> _runDesktopPrintTest(BuildContext context, PrinterProvider provider) async {
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

  // ── DIÁLOGO DE AJUSTES AVANZADOS (DESKTOP) ──
  void _showAdvancedSettingsDialog(BuildContext parentCtx) {
    final server = parentCtx.read<ServerProvider>();
    final settings = parentCtx.read<SettingsProvider>();
    final isDark = Theme.of(parentCtx).brightness == Brightness.dark;

    showDialog(
      context: parentCtx,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: isDark ? kBgDark : Colors.white,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isDark ? kBorderDark : kBorderLight,
                  width: 1,
                ),
              ),
              child: Container(
                width: 560,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(parentCtx).size.height * 0.88,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header con Logo / Titulo
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: kAccent.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.tune_rounded, size: 20, color: kAccent),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppTranslations.t(settings.lang, 'lbl_settings_system'),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: isDark ? Colors.white : kTextPrimaryLight,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  Text(
                                    'Configuraciones y entorno local',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                            ),
                            splashRadius: 18,
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Divider(height: 1, color: isDark ? kBorderDark : kBorderLight),
                      const SizedBox(height: 18),

                      // 1. IP Local de Red
                      LocalIpHubCard(
                        port: settings.port,
                        lang: settings.lang,
                        onLog: (msg) => server.addLog(msg),
                      ),
                      const SizedBox(height: 18),

                      // 2. Puerto del Servidor Local
                      Text(
                        AppTranslations.t(settings.lang, 'port_local_default'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark ? kTextSecondaryDark : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: TextFormField(
                                controller: _portCtrl,
                                keyboardType: TextInputType.number,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  hintText: '18069',
                                  filled: true,
                                  fillColor: isDark ? kSurfaceDark : const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: isDark ? kBorderDark : kBorderLight),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: isDark ? kBorderDark : kBorderLight),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: kAccent, width: 1.5),
                                  ),
                                ),
                                onChanged: (val) {
                                  final newPort = int.tryParse(val);
                                  setDialogState(() {
                                    _portChanged = newPort != null && newPort != settings.port;
                                  });
                                },
                              ),
                            ),
                          ),
                          if (_portChanged) ...[
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: _savingPort
                                  ? null
                                  : () async {
                                      setDialogState(() => _savingPort = true);
                                      await _savePort();
                                      setDialogState(() {
                                        _savingPort = false;
                                        _portChanged = false;
                                      });
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kAccent,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text(AppTranslations.t(settings.lang, 'btn_save')),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 18),

                      // 3. Protocolo de Báscula
                      Text(
                        AppTranslations.t(settings.lang, 'lbl_scale_protocol'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark ? kTextSecondaryDark : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 40,
                        child: DropdownButtonFormField<String>(
                          value: settings.scaleProtocol,
                          isExpanded: true,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                            filled: true,
                            fillColor: isDark ? kSurfaceDark : const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: isDark ? kBorderDark : kBorderLight),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: isDark ? kBorderDark : kBorderLight),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: kAccent, width: 1.5),
                            ),
                          ),
                          dropdownColor: isDark ? kSurfaceDark : Colors.white,
                          items: [
                            DropdownMenuItem(value: 'generic', child: Text(AppTranslations.t(settings.lang, 'scale_generic'))),
                            DropdownMenuItem(value: 'cas', child: Text(AppTranslations.t(settings.lang, 'scale_cas'))),
                            DropdownMenuItem(value: 'toledo', child: Text(AppTranslations.t(settings.lang, 'scale_toledo'))),
                            DropdownMenuItem(value: 'dibal', child: Text(AppTranslations.t(settings.lang, 'scale_dibal'))),
                          ],
                          onChanged: (val) async {
                            if (val != null) {
                              await settings.setScaleProtocol(val);
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 18),

                      // 4. Selector de Idioma / Language
                      Text(
                        AppTranslations.t(settings.lang, 'lbl_select_lang'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark ? kTextSecondaryDark : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 40,
                        child: DropdownButtonFormField<String>(
                          value: settings.lang == 'en' ? 'en' : 'es',
                          isExpanded: true,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                            filled: true,
                            fillColor: isDark ? kSurfaceDark : const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: isDark ? kBorderDark : kBorderLight),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: isDark ? kBorderDark : kBorderLight),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: kAccent, width: 1.5),
                            ),
                          ),
                          dropdownColor: isDark ? kSurfaceDark : Colors.white,
                          items: const [
                            DropdownMenuItem(value: 'es', child: Text('Español (ES)')),
                            DropdownMenuItem(value: 'en', child: Text('English (EN)')),
                          ],
                          onChanged: (val) async {
                            if (val != null) {
                              await settings.setLang(val);
                              setDialogState(() {});
                              setState(() {});
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 18),

                      // 5. Modo Oscuro y Auto-Launch
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? kSurfaceDark : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isDark ? kBorderDark : kBorderLight),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  AppTranslations.t(settings.lang, 'dark_mode'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : kTextPrimaryLight,
                                  ),
                                ),
                                Switch(
                                  value: settings.isDark,
                                  activeColor: kAccent,
                                  onChanged: (val) async {
                                    await settings.setTheme(val ? 'dark' : 'light');
                                    setDialogState(() {});
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),

                      // 6. Botón Lanzar POS Local
                      SizedBox(
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: _loginAndLaunch,
                          icon: const Icon(Icons.open_in_new_rounded, size: 17, color: Colors.white),
                          label: Text(
                            AppTranslations.t(settings.lang, 'btn_launch_local_pos'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kAccent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── PANEL DE CONFIGURACIÓN AVANZADA (BOTTOM SHEET) ──
  void _showAdvancedSettingsBottomSheet(BuildContext parentCtx) {
    final server = parentCtx.read<ServerProvider>();
    final settings = parentCtx.read<SettingsProvider>();
    final isDark = Theme.of(parentCtx).brightness == Brightness.dark;

    showModalBottomSheet(
      context: parentCtx,
      isScrollControlled: true,
      backgroundColor: isDark ? kBgDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppTranslations.t(settings.lang, 'lbl_settings_agent'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      StatusBadge(status: server.status),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  // 1. Puerto del servidor local
                  Text(
                    AppTranslations.t(settings.lang, 'lbl_local_server_port'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _portCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          onChanged: (val) {
                            final newPort = int.tryParse(val);
                            setModalState(() {
                              _portChanged = newPort != null && newPort != settings.port;
                            });
                          },
                        ),
                      ),
                      if (_portChanged) ...[
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _savingPort
                              ? null
                              : () async {
                                  setModalState(() => _savingPort = true);
                                  await _savePort();
                                  setModalState(() {
                                    _savingPort = false;
                                    _portChanged = false;
                                  });
                                },
                          style: ElevatedButton.styleFrom(backgroundColor: kAccent),
                          child: Text(AppTranslations.t(settings.lang, 'btn_save')),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 2. Selector de Idioma / Language
                  Text(
                    AppTranslations.t(settings.lang, 'lbl_select_lang'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 40,
                    child: DropdownButtonFormField<String>(
                      value: settings.lang == 'en' ? 'en' : 'es',
                      isExpanded: true,
                      style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        border: OutlineInputBorder(),
                      ),
                      dropdownColor: isDark ? kSurfaceDark : Colors.white,
                      items: const [
                        DropdownMenuItem(value: 'es', child: Text('Español (ES)')),
                        DropdownMenuItem(value: 'en', child: Text('English (EN)')),
                      ],
                      onChanged: (val) async {
                        if (val != null) {
                          await settings.setLang(val);
                          setModalState(() {});
                          setState(() {});
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. Modo Oscuro
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppTranslations.t(settings.lang, 'dark_mode'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      Switch(
                        value: settings.isDark,
                        activeColor: kAccent,
                        onChanged: (val) async {
                          await settings.setTheme(val ? 'dark' : 'light');
                          setModalState(() {});
                          setState(() {}); // Actualiza pantalla de fondo
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 4. Auto-lanzar POS al iniciar app
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppTranslations.t(settings.lang, 'lbl_auto_launch_pos'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      Switch(
                        value: settings.autoLaunchPos,
                        activeColor: kAccent,
                        onChanged: (val) async {
                          await settings.setAutoLaunchPos(val);
                          setModalState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 4. IP Local para el Sistema
                  Text(
                    'CONEXIÓN IP LOCAL DEL SISTEMA',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LocalIpHubCard(
                    port: settings.port,
                    lang: settings.lang,
                    onLog: (msg) => server.addLog(msg),
                  ),
                  const SizedBox(height: 20),

                  // 5. Visualizar logs
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Logs de Actividad: ${server.logs.length} líneas',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context); // Cierra bottom sheet
                          showModalBottomSheet(
                            context: parentCtx,
                            builder: (_) => Container(
                              color: isDark ? kBgDark : Colors.white,
                              padding: const EdgeInsets.all(16),
                              child: ActivityLog(
                                entries: server.logs,
                                onClear: () {
                                  server.clearLog();
                                  Navigator.pop(parentCtx);
                                },
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.receipt_long_outlined, size: 16),
                        label: const Text('Ver Logs', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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
