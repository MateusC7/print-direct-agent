import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'providers/printer_provider.dart';
import 'providers/server_provider.dart';
import 'providers/settings_provider.dart';
import 'services/settings_service.dart';
import 'services/server/http_server_service.dart';
import 'services/server/odoo_device_sync_service.dart';
import 'services/server/cloud_relay_service.dart';
import 'services/printer/print_queue_service.dart';
import 'services/system/single_instance_service.dart';
import 'services/system/tray_service.dart';
import 'services/system/auto_update_service.dart';
import 'services/logger_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar LoggerService
  await LoggerService.init();
  LoggerService.info('[INIT] Iniciando Agente de Impresion...');

  // Bloqueo de instancia única para evitar colisiones de puertos en Desktop
  final isSingleInstance = await SingleInstanceService.instance.acquireLock(
    onBringToFront: () {
      TrayService.instance.showWindow();
    },
  );
  if (!isSingleInstance) {
    LoggerService.info('[INIT] Otra instancia detectada. Ventana existente traida al frente. Saliendo de este proceso.');
    exit(0);
  }

  // Inicializar bandeja del sistema y ejecución en segundo plano (Desktop)
  await TrayService.instance.init();

  // Permitir todas las orientaciones (Vertical y Horizontal)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // 1. Inicializar SharedPreferences
  await SettingsService.instance.init();

  // 2. Arrancar la app con todos los providers
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => ServerProvider()),
        ChangeNotifierProvider(create: (_) => PrinterProvider()),
        ChangeNotifierProvider.value(value: OdooDeviceSyncService.instance),
        ChangeNotifierProvider.value(value: CloudRelayService.instance),
      ],
      child: const _AppBootstrap(),
    ),
  );
}

/// Widget intermedio que arranca el servidor HTTP/HTTPS y los servicios de red
/// tras la primera frame, sin bloquear la UI.
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _boot();
    });
  }

  Future<void> _boot() async {
    if (!mounted) return;

    final settings = context.read<SettingsProvider>();
    final server = context.read<ServerProvider>();
    final printers = context.read<PrinterProvider>();

    server.addLog('[INFO] Iniciando Software Restaurante v2.0 (Production Ready)...');
    server.addLog('[INFO] Plataforma: ${Platform.operatingSystem}');

    // Cargar lista de impresoras físicas y virtuales
    await printers.refresh();
    server.addLog('[INFO] ${printers.printers.length} impresora(s) detectada(s).');

    // Inicializar la cola persistente con mutex locks
    await PrintQueueService.instance.init(printers.service);

    // Inicializar servicios de sincronización Odoo y Cloud Relay
    OdooDeviceSyncService.instance.init(printers.service);
    CloudRelayService.instance.init(printers.service);

    // Iniciar servidor HTTP/HTTPS local
    final started = await HttpServerService.instance.start(
      printerService: printers.service,
      port: settings.port,
    );

    if (started) {
      server.addLog('[OK] Servidor de impresión listo en el puerto ${settings.port}');
    } else {
      server.addLog('[ERROR] Fallo al iniciar el servidor local. Revisa permisos.');
    }

    // Iniciar Heartbeat continuo de red con el servidor si está configurada la URL
    if (settings.odooUrl.isNotEmpty && settings.enableOdooHeartbeat) {
      OdooDeviceSyncService.instance.startPeriodicHeartbeat();
      server.addLog('[INFO] Sincronización automática activada.');
    }

    // Conectar canal inverso si está habilitado
    if (settings.enableCloudRelay && settings.odooUrl.isNotEmpty) {
      CloudRelayService.instance.connect();
      server.addLog('[INFO] Conectando canal con el servidor...');
    }

    // Comprobar actualizaciones en segundo plano de forma no bloqueante
    Future.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      final update = await AutoUpdateService.instance.checkForUpdates();
      if (update != null && mounted) {
        AutoUpdateService.instance.showUpdateDialog(context, update);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const PrintAgentApp();
  }
}
