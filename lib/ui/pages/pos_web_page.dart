import 'dart:convert';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_presentation_display/flutter_presentation_display.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/printer_model.dart';
import '../../models/xml_escpos_compiler.dart';
import '../../services/printer/printer_service.dart';
import '../../providers/printer_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/server_provider.dart';
import '../../services/hardware/scale_service.dart';
import '../../services/hardware/scanner_service.dart';
import '../../services/hardware/display_service.dart';
import '../widgets/barcode_scanner_sheet.dart';

class PosWebPage extends StatefulWidget {
  const PosWebPage({super.key});

  @override
  State<PosWebPage> createState() => _PosWebPageState();
}

class _PosWebPageState extends State<PosWebPage> with SingleTickerProviderStateMixin {
  InAppWebViewController? _webViewController;
  final FlutterPresentationDisplay _displayManager = FlutterPresentationDisplay();
  bool _isLoading = true;
  bool _showOverlay = true;
  double _loadProgress = 0.0;
  bool _showFloatingMenu = false;
  bool _canPop = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    // Permitir barra de estado con iconos legibles (WiFi, batería, hora) sin barra negra opaca
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    _requestCameraPermission();
    _startCustomerDisplay();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Temporizador de seguridad: si la conexión tarda o hay fallo de red, ocultar overlay para evitar pantalla negra
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && _isLoading) {
        _onLoadingFinished();
      }
    });
  }

  Future<void> _requestCameraPermission() async {
    try {
      await Permission.camera.request();
    } catch (e) {
      debugPrint('Error solicitando permiso de cámara: $e');
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _stopCustomerDisplay();
    _pulseController.dispose();
    super.dispose();
  }

  void _onLoadingFinished() {
    if (!_isLoading) return;
    setState(() {
      _isLoading = false;
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _showOverlay = false;
        });
      }
    });
  }

  void _startCustomerDisplay() async {
    try {
      final displays = await _displayManager.getDisplays();
      if (displays != null && displays.length > 1) {
        final secondaryDisplayId = displays[1].displayId;
        if (secondaryDisplayId != null) {
          await _displayManager.showSecondaryDisplay(
            displayId: secondaryDisplayId,
            routerName: 'presentation',
          );
          debugPrint('Pantalla de cliente secundaria iniciada con ID: $secondaryDisplayId');
        } else {
          debugPrint('El ID de la pantalla secundaria es nulo.');
        }
      } else {
        debugPrint('No se detectó una pantalla secundaria conectada.');
      }
    } catch (e) {
      debugPrint('Error abriendo pantalla de cliente secundaria: $e');
    }
  }

  void _stopCustomerDisplay() async {
    try {
      final displays = await _displayManager.getDisplays();
      if (displays != null && displays.length > 1) {
        final secondaryDisplayId = displays[1].displayId;
        if (secondaryDisplayId != null) {
          await _displayManager.hideSecondaryDisplay(displayId: secondaryDisplayId);
          debugPrint('Pantalla de cliente secundaria cerrada.');
        }
      }
    } catch (e) {
      debugPrint('Error cerrando pantalla de cliente secundaria: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    
    // Limpiar y construir la URL del POS con detección inteligente de protocolo
    String rawUrl = settings.odooUrl.trim();
    String cleanUrl = rawUrl;
    String protocol = settings.odooProtocol;

    if (rawUrl.startsWith('http://')) {
      protocol = 'http';
      cleanUrl = rawUrl.substring(7);
    } else if (rawUrl.startsWith('https://')) {
      protocol = 'https';
      cleanUrl = rawUrl.substring(8);
    }

    while (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }

    String initialUrl = '';
    if (cleanUrl.isNotEmpty) {
      final user = settings.odooUsername.trim();
      final pass = settings.odooPassword;

      if (user.isNotEmpty && pass.isNotEmpty) {
        initialUrl = '$protocol://$cleanUrl/web/login?login=${Uri.encodeComponent(user)}&password=${Uri.encodeComponent(pass)}';
      } else {
        if (!cleanUrl.contains('/')) {
          initialUrl = '$protocol://$cleanUrl/web';
        } else {
          initialUrl = '$protocol://$cleanUrl';
        }
      }
    }

    if (initialUrl.isEmpty) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.link_off, size: 64, color: kError),
                const SizedBox(height: 16),
                const Text(
                  'No se ha configurado la dirección del servidor',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Por favor, configura la dirección del servidor en la pantalla de inicio.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kTextSecondaryLight),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.kRadius)),
                  ),
                  child: const Text('Volver a Configuración', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final controller = _webViewController;
        if (controller != null && await controller.canGoBack()) {
          await controller.goBack();
        } else {
          if (context.mounted) {
            final exit = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('¿Salir del POS?'),
                content: const Text('Si sales, se cerrará la sesión actual de ventas y regresarás al menú de configuración.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(backgroundColor: kError),
                    child: const Text('Salir', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
            if (exit == true && context.mounted) {
              setState(() {
                _canPop = true;
              });
              Navigator.pop(context);
            }
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            // ── WebView Principal dentro de SafeArea para no tapar los iconos del celular ──
            SafeArea(
              bottom: false,
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(initialUrl)),
              initialUserScripts: UnmodifiableListView<UserScript>([
                UserScript(
                  source: '''
                    window.isFlutterPrintAgent = true;
                    window.odooWrapper = window.odooWrapper || { isMobile: true, isMobileApp: true };
                  ''',
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
              ]),
              initialSettings: InAppWebViewSettings(
                userAgent: 'SoftwareRestaurantPrintApp/2.0.0 (Android; NativeBridge)',
                javaScriptEnabled: true,
                domStorageEnabled: true,
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                allowsInlineMediaPlayback: true,
                mediaPlaybackRequiresUserGesture: false,
                useHybridComposition: true,
                supportZoom: false,
                useShouldInterceptRequest: false,
                allowFileAccessFromFileURLs: true,
                allowUniversalAccessFromFileURLs: true,
                cacheEnabled: true,
                clearCache: false,
              ),
              onReceivedServerTrustAuthRequest: (controller, challenge) async {
                // Permite certificados autofirmados, IPs de VPS o SSL sin validar sin mostrar pantalla en blanco/negro
                return ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.PROCEED);
              },
              onReceivedError: (controller, request, error) {
                debugPrint('[WebView Error] ${error.description}');
                _onLoadingFinished();
              },
              onReceivedHttpError: (controller, request, errorResponse) {
                debugPrint('[WebView HTTP Error] ${errorResponse.statusCode}');
                _onLoadingFinished();
              },
              onPermissionRequest: (controller, request) async {
                return PermissionResponse(
                  resources: request.resources,
                  action: PermissionResponseAction.GRANT,
                );
              },
              onPrintRequest: (controller, url, printJobController) async {
                // Al retornar true, cancelamos los diálogos emergentes de Android (Sin Popups)
                final serverProvider = context.read<ServerProvider>();
                serverProvider.addLog('[WebView] Solicitud de impresión interceptada (Silenciosa / Sin Popups).');
                return true;
              },
              onWebViewCreated: (controller) {
                _webViewController = controller;
                _setupJsBridge(controller);
              },
              onLoadStart: (controller, url) {
                setState(() {
                  _isLoading = true;
                  _showOverlay = true;
                  _loadProgress = 0.0;
                });
              },
              onLoadStop: (controller, url) async {
                _onLoadingFinished();
                await _injectFetchInterceptor(controller);
              },
              onProgressChanged: (controller, progress) {
                setState(() {
                  _loadProgress = progress / 100;
                  if (progress >= 100) {
                    _onLoadingFinished();
                  }
                });
              },
              onConsoleMessage: (controller, consoleMessage) {
                final serverProvider = context.read<ServerProvider>();
                serverProvider.addLog('[Consola POS] ${consoleMessage.message}');
              },
            ),
          ),

            // ── Pantalla de Carga Premium / Loading Overlay ──
            if (_showOverlay)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_isLoading,
                  child: AnimatedOpacity(
                    opacity: _isLoading ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                    child: Container(
                      color: const Color(0xFF001938),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ScaleTransition(
                              scale: Tween<double>(begin: 0.95, end: 1.08).animate(
                                CurvedAnimation(
                                  parent: _pulseController,
                                  curve: Curves.easeInOut,
                                ),
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(AppTheme.kRadiusMd * 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF004aad).withOpacity(0.3),
                                      blurRadius: 40,
                                      spreadRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Image.asset(
                                  'assets/images/logo_restaurant.png',
                                  height: 80,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, _, __) => const Icon(
                                    Icons.restaurant_menu_rounded,
                                    size: 64,
                                    color: Color(0xFF004aad),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 35),
                            const Text(
                              'Software Restaurant',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Iniciando punto de venta...',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white60,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 40),
                            const SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // ── Menú Flotante Notion-style ──────────────────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              right: 16,
              bottom: _showFloatingMenu ? 80 : 16,
              child: _showFloatingMenu
                  ? _buildMenuCard()
                  : _buildTriggerButton(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Botón flotante para abrir menú ────────────────────────────────────────
  Widget _buildTriggerButton() {
    return GestureDetector(
      onLongPress: () {
        setState(() => _showFloatingMenu = true);
      },
      onTap: () {
        setState(() => _showFloatingMenu = true);
      },
      child: Opacity(
        opacity: 0.25,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: kBgDark,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.settings, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  // ── Tarjeta de Menú Desplegado ──────────────────────────────────────────
  Widget _buildMenuCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? kSurfaceDark : Colors.white;
    final textCol = isDark ? kTextPrimaryDark : kTextPrimaryLight;

    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppTheme.kRadius * 1.5),
        border: Border.all(color: isDark ? kBorderDark : kBorderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMenuItem(
            icon: Icons.qr_code_scanner_rounded,
            label: 'Escanear Código',
            onTap: () async {
              setState(() => _showFloatingMenu = false);
              final code = await BarcodeScannerSheet.show(context);
              if (code != null && code.isNotEmpty && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Código escaneado: $code'),
                    backgroundColor: kSuccess,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            color: textCol,
          ),
          _buildMenuItem(
            icon: Icons.refresh,
            label: 'Recargar POS',
            onTap: () {
              _webViewController?.reload();
              setState(() => _showFloatingMenu = false);
            },
            color: textCol,
          ),
          _buildMenuItem(
            icon: Icons.dashboard_outlined,
            label: 'Ver Agente / Config',
            onTap: () {
              Navigator.pop(context);
            },
            color: textCol,
          ),
          _buildMenuItem(
            icon: Icons.print_outlined,
            label: 'Imprimir Ticket Prueba',
            onTap: () async {
              setState(() => _showFloatingMenu = false);
              final printers = context.read<PrinterProvider>();
              final server = context.read<ServerProvider>();
              if (printers.selected != null) {
                server.addLog('[WebView Menu] Imprimiendo ticket de prueba...');
                final result = await printers.printTest();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result.success ? 'Ticket impreso correctamente' : 'Error: ${result.message}'),
                      backgroundColor: result.success ? kSuccess : kError,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No hay impresora seleccionada en el Agente'),
                    backgroundColor: kWarning,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            color: textCol,
          ),
          const Divider(height: 12, thickness: 1, indent: 8, endIndent: 8),
          _buildMenuItem(
            icon: Icons.close,
            label: 'Cerrar Menú',
            onTap: () => setState(() => _showFloatingMenu = false),
            color: kError,
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Configurar JSBridge en WebView ────────────────────────────────────────
  void _setupJsBridge(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'odooBridge',
      callback: (args) async {
        final server = context.read<ServerProvider>();
        final printers = context.read<PrinterProvider>();
        final settings = context.read<SettingsProvider>();

        if (args.isEmpty) return {'status': 'error', 'message': 'Argumentos vacíos'};

        final Map<String, dynamic> request = args[0] as Map<String, dynamic>;
        
        // ── MANEJO DE ACCIONES NATIVAS (odooWrapper API) ──────────────────
        final String? action = request['action'] as String?;
        if (action != null) {
          if (action == 'scanBarcode') {
            server.addLog('[WebView JSBridge] Abriendo escáner nativo de código de barras...');
            final code = await BarcodeScannerSheet.show(context);
            return {'status': 'success', 'code': code ?? ''};
          } else if (action == 'vibrate') {
            HapticFeedback.vibrate();
            return {'status': 'success'};
          } else if (action == 'showToast') {
            final msg = request['message'] as String? ?? '';
            if (mounted && msg.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
              );
            }
            return {'status': 'success'};
          } else if (action == 'requestPermission') {
            await Permission.camera.request();
            return {'status': 'granted'};
          }
        }

        final String url = request['url'] as String? ?? '';
        final dynamic rawBody = request['body'];

        server.addLog('[WebView JSBridge] Interceptada petición: $url');

        // Intentar parsear el ID del JSON-RPC
        int? rpcId;
        if (rawBody != null) {
          try {
            final Map<String, dynamic> bodyJson = rawBody is String 
                ? jsonDecode(rawBody) as Map<String, dynamic>
                : Map<String, dynamic>.from(rawBody as Map);
            rpcId = bodyJson['id'] as int?;
          } catch (_) {}
        }

        // A1) INTERCEPTAR /info (Autodescubrimiento y Vinculación)
        if (url.contains('/info')) {
          final allDevices = await printers.service.getAllPrinters();
          final list = allDevices.map((p) => {
            'name': p.name,
            'type': p.type.name,
            'address': p.displayAddress,
          }).toList();

          server.addLog('[WebView JSBridge] /info respondido con ${list.length} dispositivo(s).');
          return {
            'status': 'success',
            'device_name': settings.deviceName.isNotEmpty
                ? settings.deviceName
                : (defaultTargetPlatform == TargetPlatform.android ? 'Dispositivo Android' : 'PC Caja'),
            'device_uuid': settings.deviceUuid,
            'token': settings.apiToken,
            'printers': list,
            'platform': defaultTargetPlatform.name,
            'version': '2.0.0',
          };
        }

        // A2) INTERCEPTAR /get_printers
        if (url.contains('/get_printers')) {
          final allDevices = await printers.service.getAllPrinters();
          final list = allDevices.map((p) => {
            'name': p.name,
            'type': p.type.name,
            'address': p.displayAddress,
          }).toList();
          return {
            'status': 'success',
            'printers': list,
          };
        }

        // A3) INTERCEPTAR /sync_token (Auto-completado en la App desde Odoo)
        if (url.contains('/sync_token')) {
          try {
            final Map<String, dynamic> bodyJson = rawBody is String
                ? jsonDecode(rawBody) as Map<String, dynamic>
                : Map<String, dynamic>.from(rawBody as Map);
            final token = bodyJson['token'] as String?;
            final serverUrl = bodyJson['server_url'] as String?;
            final deviceName = bodyJson['device_name'] as String?;

            if (token != null && token.isNotEmpty) {
              await settings.setApiToken(token);
            }
            if (serverUrl != null && serverUrl.isNotEmpty) {
              await settings.setOdooUrl(serverUrl);
            }
            if (deviceName != null && deviceName.isNotEmpty) {
              await settings.setDeviceName(deviceName);
            }
            server.addLog('[WebView JSBridge] Token y servidor sincronizados desde el Sistema.');
          } catch (e) {
            server.addLog('[WebView JSBridge] Error sync_token: $e');
          }
          return {
            'status': 'success',
            'message': 'Configuración guardada en la App.',
          };
        }

        // B1) INTERCEPTAR PING Y HANDSHAKE DE PROXY (JSON-RPC / HTTP)
        if (url.contains('/hw_proxy/hello')) {
          return 'ping';
        }
        if (url.contains('/hw_proxy/handshake')) {
          return {
            'jsonrpc': '2.0',
            'id': rpcId,
            'result': true,
          };
        }

        // B2) INTERCEPTAR ESTADO DEL PROXY (JSON-RPC)
        if (url.contains('/hw_proxy/status_json')) {
          server.addLog('[WebView JSBridge] Estado del proxy solicitado.');
          final printerStatus = printers.printers.isNotEmpty ? 'connected' : 'disconnected';
          return {
            'jsonrpc': '2.0',
            'id': rpcId,
            'result': {
              'status': 'connected',
              'messages': [],
              'drivers': {
                'escpos': { 'status': printerStatus, 'messages': [] },
                'scale': { 'status': ScaleService.instance.isConnected ? 'connected' : 'disconnected', 'messages': [] },
                'display': { 'status': 'connected', 'messages': [] },
                'scanner': { 'status': ScannerService.instance.isConnected ? 'connected' : 'disconnected', 'messages': [] }
              }
            }
          };
        }

        // C) INTERCEPTAR BÁSCULA (JSON-RPC)
        if (url.contains('/hw_proxy/scale_read') || url.contains('/scale_read')) {
          final weight = ScaleService.instance.currentWeight;
          final unit = ScaleService.instance.unit;
          server.addLog('[WebView JSBridge] Lectura báscula nativa: $weight kg');
          return {
            'jsonrpc': '2.0',
            'id': rpcId,
            'result': {
              'weight': weight,
              'unit': unit,
              'info': 'ok'
            }
          };
        }

        // D) INTERCEPTAR PANTALLA DE CLIENTE (JSON-RPC)
        if (url.contains('/hw_proxy/customer_facing_display')) {
          if (rawBody == null) return {'status': 'error', 'message': 'Payload de display vacío'};

          Map<String, dynamic> data;
          if (rawBody is String) {
            data = jsonDecode(rawBody) as Map<String, dynamic>;
          } else {
            data = Map<String, dynamic>.from(rawBody as Map);
          }

          final params = data['params'] ?? {};
          final displayAction = params['action'] ?? '';

          server.addLog('[WebView JSBridge] Pantalla de cliente - Acción: $displayAction');

          if (displayAction == 'get') {
            final currentHtml = DisplayService.instance.currentHtml;
            return {
              'jsonrpc': '2.0',
              'id': rpcId,
              'result': {
                'status': 'success',
                'data': {
                  'html': currentHtml,
                  'rendered_html': currentHtml,
                }
              }
            };
          }

          final html = params['html'] ?? '';
          if (html.isNotEmpty) {
            DisplayService.instance.updateDisplay(html);
          }

          return {
            'jsonrpc': '2.0',
            'id': rpcId,
            'result': {'status': 'ok'}
          };
        }

        // E) INTERCEPTAR IMPRESIÓN NATIVA XML (Cocina y Recibos POS)
        if (url.contains('/hw_proxy/print_xml_receipt') || url.contains('/hw_proxy/default_printer_action')) {
          server.addLog('[WebView JSBridge] Impresión XML nativa del Sistema interceptada.');
          
          String? xmlReceipt;
          String? targetPrinterName;

          if (rawBody != null) {
            try {
              final Map<String, dynamic> bodyJson = rawBody is String 
                  ? jsonDecode(rawBody) as Map<String, dynamic>
                  : Map<String, dynamic>.from(rawBody as Map);
              final params = bodyJson['params'] as Map<String, dynamic>?;
              if (params != null) {
                xmlReceipt = params['receipt'] as String?;
                targetPrinterName = params['printer_name'] as String?;
              }
            } catch (e) {
              server.addLog('[WebView JSBridge] Error parseando recibo XML: $e');
            }
          }

          if (xmlReceipt != null && xmlReceipt.isNotEmpty) {
            try {
              final bytes = XmlEscposCompiler.compile(xmlReceipt);

              // Buscar la impresora indicada (e.g. "Cocina", "Bar", "Horno")
              PrinterModel? target;
              if (targetPrinterName != null && targetPrinterName.isNotEmpty) {
                try {
                  target = printers.printers.firstWhere((p) => p.name.toLowerCase().contains(targetPrinterName!.toLowerCase()));
                } catch (_) {}
              }

              // Si no se encuentra, usar la impresora por defecto o la seleccionada
              if (target == null && settings.defaultPrinterId.isNotEmpty) {
                try {
                  target = printers.printers.firstWhere((p) => p.id == settings.defaultPrinterId);
                } catch (_) {}
              }
              target ??= printers.selected ?? (printers.printers.isNotEmpty ? printers.printers.first : null);

              if (target != null) {
                server.addLog('[WebView JSBridge] Imprimiendo XML directamente en: ${target.name}');
                await printers.printRaw(
                  printer: target,
                  bytes: bytes,
                  rawType: 'raw',
                );
              } else {
                server.addLog('[WebView JSBridge] [WARN] No hay impresora disponible para imprimir el ticket XML.');
              }
            } catch (e) {
              server.addLog('[WebView JSBridge] Error procesando ticket XML: $e');
            }
          }

          return {
            'jsonrpc': '2.0',
            'id': rpcId,
            'result': true
          };
        }

        // F) INTERCEPTAR IMPRESIÓN RAW (Cocina, Recibos y Etiquetas ZPL)
        if (url.contains('/print_raw')) {
          if (rawBody == null) return {'status': 'error', 'message': 'Payload de impresión vacío'};

          Map<String, dynamic> data;
          if (rawBody is String) {
            data = jsonDecode(rawBody) as Map<String, dynamic>;
          } else {
            data = Map<String, dynamic>.from(rawBody as Map);
          }

          final String? printerName = data['printer_name'] as String?;
          final String? rawB64 = data['raw_data'] as String?;
          final String? rawType = data['raw_type'] as String?;

          if (rawB64 == null) return {'status': 'error', 'message': 'Faltan datos de impresión (raw_data)'};

          final Uint8List bytes = base64Decode(rawB64);

          // Obtener lista completa de impresoras disponibles (Nativas, Red, Sunmi, etc.)
          final allDevices = await printers.service.getAllPrinters();
          
          PrinterModel? target;
          if (printerName != null && printerName.isNotEmpty) {
            try {
              target = allDevices.firstWhere(
                (p) => p.name.toLowerCase().trim() == printerName.toLowerCase().trim() ||
                       p.name.toLowerCase().contains(printerName.toLowerCase()) ||
                       printerName.toLowerCase().contains(p.name.toLowerCase())
              );
            } catch (_) {}
          }

          // Si no se encuentra o es la predeterminada de Odoo, buscar impresora por defecto guardada
          if (target == null && settings.defaultPrinterId.isNotEmpty) {
            try {
              target = allDevices.firstWhere((p) => p.id == settings.defaultPrinterId);
            } catch (_) {}
          }

          // Fallback a la primera impresora válida (Red, Sunmi, Bluetooth, o la seleccionada)
          target ??= printers.selected ?? (allDevices.isNotEmpty ? allDevices.firstWhere((p) => p.type == PrinterType.network || p.type == PrinterType.sunmi || p.type == PrinterType.bluetooth, orElse: () => allDevices.first) : null);

          if (target == null) {
            server.addLog('[WebView JSBridge] [ERROR] No hay ninguna impresora configurada o disponible para imprimir.');
            return {'status': 'error', 'message': 'No hay impresora configurada en el Agente'};
          }

          server.addLog('[WebView JSBridge] Imprimiendo en: ${target.name} (${target.type.name}) - Modo: $rawType');

          final result = await printers.service.printRaw(
            printer: target,
            bytes: bytes.toList(),
            rawType: rawType ?? 'raw',
          );

          server.addLog('[WebView JSBridge] Resultado impresión: ${result.success ? "OK" : result.message}');

          return {
            'status': result.success ? 'success' : 'error',
            'message': result.message,
          };
        }

        return {'status': 'error', 'message': 'Ruta no controlada por el bridge'};
      },
    );
  }

  // ── Inyectar trampa de fetch y odooWrapper en el DOM ─────────────────────
  Future<void> _injectFetchInterceptor(InAppWebViewController controller) async {
    const jsCode = '''
      (function() {
        console.log(">> [NATIVE BRIDGE] Inicializando odooWrapper y trampa de fetch/XHR para emulación de IoT Box...");

        window.isFlutterPrintAgent = true;

        // Expone la interfaz nativa odooWrapper compatible con Odoo Mobile oficial
        window.odooWrapper = {
          isMobile: true,
          isMobileApp: true,
          scanBarcode: async function() {
            console.log(">> [ODOO MOBILE] scanBarcode invocado.");
            try {
              const res = await window.flutter_inappwebview.callHandler('odooBridge', { action: 'scanBarcode' });
              return (res && res.code) ? res.code : (res || "");
            } catch(e) {
              console.error(">> [ODOO MOBILE] Error en scanBarcode:", e);
              return "";
            }
          },
          requestPermission: async function(permission) {
            console.log(">> [ODOO MOBILE] requestPermission: " + permission);
            return await window.flutter_inappwebview.callHandler('odooBridge', { action: 'requestPermission', permission: permission });
          },
          vibrate: function(ms) {
            window.flutter_inappwebview.callHandler('odooBridge', { action: 'vibrate', duration: ms });
          },
          showToast: function(msg) {
            window.flutter_inappwebview.callHandler('odooBridge', { action: 'showToast', message: msg });
          }
        };

        // Polyfill de navigator.mediaDevices para orígenes HTTP sin SSL
        if (!navigator.mediaDevices) {
          navigator.mediaDevices = {};
        }
        if (!navigator.mediaDevices.getUserMedia) {
          navigator.mediaDevices.getUserMedia = async function(constraints) {
            console.log(">> [ODOO MOBILE] Polyfill getUserMedia invocado nativamente.");
            const code = await window.odooWrapper.scanBarcode();
            if (!code) throw new Error("Escaneo cancelado");
            return code;
          };
        }

        // Trampa de window.fetch
        const originalFetch = window.fetch;
        window.fetch = async function(url, options) {
          const urlStr = typeof url === 'string' ? url : (url.url || "");
          if (urlStr.includes('/hw_proxy') || 
              urlStr.includes('/print_raw') || 
              urlStr.includes('/get_printers') || 
              urlStr.includes('/scale_read') ||
              urlStr.includes('18069') ||
              urlStr.includes('8069')) {
            console.log(">> [NATIVE BRIDGE] Interceptado fetch a: " + urlStr);
            try {
              const res = await window.flutter_inappwebview.callHandler('odooBridge', {
                url: urlStr,
                body: options?.body || null
              });
              return new Response(JSON.stringify(res), {
                status: 200,
                headers: { 'Content-Type': 'application/json' }
              });
            } catch (e) {
              console.error(">> [NATIVE BRIDGE] Error en handler nativo:", e);
              return new Response(JSON.stringify({ status: 'error', message: e.toString() }), {
                status: 500,
                headers: { 'Content-Type': 'application/json' }
              });
            }
          }
          return originalFetch.apply(this, arguments);
        };

        // Trampa de XMLHttpRequest
        const originalOpen = XMLHttpRequest.prototype.open;
        const originalSend = XMLHttpRequest.prototype.send;

        XMLHttpRequest.prototype.open = function(method, url) {
          this._url = url;
          this._method = method;
          return originalOpen.apply(this, arguments);
        };

        XMLHttpRequest.prototype.send = function(body) {
          const url = this._url || "";
          if (url.includes('/hw_proxy') || 
              url.includes('/print_raw') || 
              url.includes('/get_printers') || 
              url.includes('/scale_read') ||
              url.includes('18069') ||
              url.includes('8069')) {
            console.log(">> [NATIVE BRIDGE] Interceptado XHR a: " + url);
            
            window.flutter_inappwebview.callHandler('odooBridge', {
              url: url,
              body: body || null
            }).then(res => {
              Object.defineProperty(this, 'readyState', { value: 4 });
              Object.defineProperty(this, 'status', { value: 200 });
              Object.defineProperty(this, 'responseText', { value: JSON.stringify(res) });
              if (this.onreadystatechange) this.onreadystatechange();
              if (this.onload) this.onload();
            }).catch(e => {
              Object.defineProperty(this, 'readyState', { value: 4 });
              Object.defineProperty(this, 'status', { value: 500 });
              Object.defineProperty(this, 'responseText', { value: JSON.stringify({ status: 'error', message: e.toString() }) });
              if (this.onreadystatechange) this.onreadystatechange();
              if (this.onerror) this.onerror();
            });
            return;
          }
          return originalSend.apply(this, arguments);
        };
      })();
    ''';
    await controller.evaluateJavascript(source: jsCode);
  }
}
