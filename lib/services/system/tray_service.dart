import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../logger_service.dart';

/// Servicio para ejecutar la aplicación en segundo plano en escritorio (Windows, macOS, Linux).
/// Permite que al presionar la 'X' la app no se cierre, sino que se minimice a la bandeja
/// del sistema (System Tray) con el logo de Software Restaurante, manteniendo activos
/// los servicios de impresión en tiempo real.
class TrayService with TrayListener, WindowListener {
  TrayService._();
  static final TrayService instance = TrayService._();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;

    try {
      // 1. Inicializar Window Manager
      await windowManager.ensureInitialized();
      windowManager.addListener(this);
      await windowManager.setPreventClose(true);

      // Maximizar y asegurar foco en Desktop para que abra en pantalla completa
      await windowManager.waitUntilReadyToShow(
        WindowOptions(
          center: true,
          backgroundColor: Colors.transparent,
          skipTaskbar: false,
          title: 'Software Restaurante',
        ),
        () async {
          await windowManager.maximize();
          await windowManager.show();
          await windowManager.focus();
        },
      );

      // 2. Inicializar Tray Manager
      trayManager.addListener(this);

      String iconPath = 'assets/images/logo_restaurant.png';
      if (Platform.isWindows) {
        // En Windows buscar en orden de prioridad: runner resources, exe dir o assets
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final candidate1 = '$exeDir/data/flutter_assets/assets/images/app_icon.ico';
        final candidate2 = '$exeDir/windows/runner/resources/app_icon.ico';
        final candidate3 = 'windows/runner/resources/app_icon.ico';
        final candidate4 = 'assets/images/app_icon.ico';

        if (File(candidate1).existsSync()) {
          iconPath = candidate1;
        } else if (File(candidate2).existsSync()) {
          iconPath = candidate2;
        } else if (File(candidate3).existsSync()) {
          iconPath = File(candidate3).absolute.path;
        } else if (File(candidate4).existsSync()) {
          iconPath = File(candidate4).absolute.path;
        } else {
          iconPath = candidate3;
        }
      }

      await trayManager.setIcon(iconPath);
      try {
        await trayManager.setToolTip('Software Restaurante — Agente de Impresión');
      } catch (e) {
        // En algunos entornos Linux libayatana no implementa setToolTip directamente
      }

      final menu = Menu(
        items: [
          MenuItem(
            key: 'show_app',
            label: 'Abrir Software Restaurante',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'status',
            label: '● Estado: Activo en segundo plano',
            disabled: true,
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'exit_app',
            label: 'Salir de la aplicación',
          ),
        ],
      );

      await trayManager.setContextMenu(menu);
      _initialized = true;
      LoggerService.info('[TRAY] Bandeja del sistema inicializada correctamente con icono.');
    } catch (e) {
      LoggerService.error('Error inicializando bandeja del sistema: $e');
    }
  }

  // ── Eventos de Ventana ──────────────────────────────────────────
  @override
  void onWindowClose() async {
    final isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      await windowManager.hide();
      LoggerService.info('[TRAY] Ventana minimizada a la bandeja del sistema.');
    }
  }

  // ── Eventos de Bandeja del Sistema ──────────────────────────────
  @override
  void onTrayIconMouseDown() async {
    await showWindow();
  }

  @override
  void onTrayIconRightMouseDown() async {
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show_app') {
      await showWindow();
    } else if (menuItem.key == 'exit_app') {
      await exitApp();
    }
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.maximize();
    await windowManager.focus();
  }

  Future<void> exitApp() async {
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  void dispose() {
    if (_initialized) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
      trayManager.destroy();
    }
  }
}
