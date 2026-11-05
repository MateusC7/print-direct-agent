import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../models/printer_model.dart';

/// Servicio de persistencia: lee y escribe ajustes en SharedPreferences.
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  /// Canal global de transmisión para auto-sincronización reactiva desde Odoo en tiempo real
  static final StreamController<Map<String, String>> onExternalSettingsSync =
      StreamController<Map<String, String>>.broadcast();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // ── Puerto ────────────────────────────────────────────────────────────
  int get port => _prefs?.getInt(AppConstants.prefPort) ?? AppConstants.defaultPort;

  Future<void> setPort(int value) async {
    await _prefs?.setInt(AppConstants.prefPort, value);
  }

  // ── Tema ──────────────────────────────────────────────────────────────
  String get theme => _prefs?.getString(AppConstants.prefTheme) ?? 'light';

  Future<void> setTheme(String value) async {
    await _prefs?.setString(AppConstants.prefTheme, value);
  }

  // ── Idioma ────────────────────────────────────────────────────────────
  String get lang => _prefs?.getString(AppConstants.prefLang) ?? 'es';

  Future<void> setLang(String value) async {
    await _prefs?.setString(AppConstants.prefLang, value);
  }

  // ── Odoo POS URL ──────────────────────────────────────────────────────
  String get odooUrl => _prefs?.getString(AppConstants.prefOdooUrl) ?? '';

  Future<void> setOdooUrl(String value) async {
    await _prefs?.setString(AppConstants.prefOdooUrl, value);
  }

  // ── Confirmación (ACK) de impresión ──────────────────────────────────
  bool get enableAck => _prefs?.getBool(AppConstants.prefEnableAck) ?? true;

  Future<void> setEnableAck(bool value) async {
    await _prefs?.setBool(AppConstants.prefEnableAck, value);
  }

  // ── Firma HMAC de las peticiones al servidor ─────────────────────────
  bool get enableSignature => _prefs?.getBool(AppConstants.prefEnableSignature) ?? true;

  Future<void> setEnableSignature(bool value) async {
    await _prefs?.setBool(AppConstants.prefEnableSignature, value);
  }

  // ── Intervalo de polling del canal inverso (ms) ──────────────────────
  int get pollIntervalMs => _prefs?.getInt(AppConstants.prefPollIntervalMs) ?? 2000;

  Future<void> setPollIntervalMs(int value) async {
    await _prefs?.setInt(AppConstants.prefPollIntervalMs, value);
  }

  // ── Iniciar POS automáticamente ─────────────────────────────────────────
  bool get autoLaunchPos => _prefs?.getBool(AppConstants.prefAutoLaunchPos) ?? false;

  Future<void> setAutoLaunchPos(bool value) async {
    await _prefs?.setBool(AppConstants.prefAutoLaunchPos, value);
  }

  // ── Impresora por defecto ───────────────────────────────────────────────
  String get defaultPrinterId => _prefs?.getString(AppConstants.prefDefaultPrinterId) ?? '';

  Future<void> setDefaultPrinterId(String value) async {
    await _prefs?.setString(AppConstants.prefDefaultPrinterId, value);
  }

  // ── Credenciales y Protocolo del Servidor ────────────────────────────────
  String get odooUsername => _prefs?.getString(AppConstants.prefOdooUsername) ?? '';

  Future<void> setOdooUsername(String value) async {
    await _prefs?.setString(AppConstants.prefOdooUsername, value);
  }

  String get odooPassword => _prefs?.getString(AppConstants.prefOdooPassword) ?? '';

  Future<void> setOdooPassword(String value) async {
    await _prefs?.setString(AppConstants.prefOdooPassword, value);
  }

  bool get rememberCredentials => _prefs?.getBool(AppConstants.prefRememberCredentials) ?? true;

  Future<void> setRememberCredentials(bool value) async {
    await _prefs?.setBool(AppConstants.prefRememberCredentials, value);
  }

  String get odooProtocol => _prefs?.getString(AppConstants.prefOdooProtocol) ?? 'https';

  Future<void> setOdooProtocol(String value) async {
    await _prefs?.setString(AppConstants.prefOdooProtocol, value);
  }

  String get apiToken => _prefs?.getString(AppConstants.prefApiToken) ?? '';

  Future<void> setApiToken(String value) async {
    await _prefs?.setString(AppConstants.prefApiToken, value);
  }

  String get scaleProtocol => _prefs?.getString(AppConstants.prefScaleProtocol) ?? 'generic';

  Future<void> setScaleProtocol(String value) async {
    await _prefs?.setString(AppConstants.prefScaleProtocol, value);
  }

  // ── Identificador y Nombre del Dispositivo ─────────────────────────────
  String get deviceUuid => _prefs?.getString(AppConstants.prefDeviceUuid) ?? '';

  Future<void> setDeviceUuid(String value) async {
    await _prefs?.setString(AppConstants.prefDeviceUuid, value);
  }

  String get deviceName => _prefs?.getString(AppConstants.prefDeviceName) ?? '';

  Future<void> setDeviceName(String value) async {
    await _prefs?.setString(AppConstants.prefDeviceName, value);
  }

  // ── Producción: Auto-arranque en Windows ──────────────────────────────
  bool get autoStartWindows => _prefs?.getBool(AppConstants.prefAutoStartWindows) ?? true;

  Future<void> setAutoStartWindows(bool value) async {
    await _prefs?.setBool(AppConstants.prefAutoStartWindows, value);
  }

  // ── Producción: Conexión Automática / Cloud Relay ─────────────────
  bool get enableCloudRelay => _prefs?.getBool(AppConstants.prefEnableCloudRelay) ?? true;

  Future<void> setEnableCloudRelay(bool value) async {
    await _prefs?.setBool(AppConstants.prefEnableCloudRelay, value);
  }

  // ── Producción: Heartbeat Odoo ─────────────────────────────────────────
  bool get enableOdooHeartbeat => _prefs?.getBool(AppConstants.prefEnableOdooHeartbeat) ?? true;

  Future<void> setEnableOdooHeartbeat(bool value) async {
    await _prefs?.setBool(AppConstants.prefEnableOdooHeartbeat, value);
  }

  // ── Impresoras de red guardadas (Android principalmente) ──────────────
  static const String _prefNetworkPrinters = 'network_printers';

  List<PrinterModel> get savedNetworkPrinters {
    final raw = _prefs?.getString(_prefNetworkPrinters);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => PrinterModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveNetworkPrinters(List<PrinterModel> printers) async {
    final list = printers.map((p) => p.toJson()).toList();
    await _prefs?.setString(_prefNetworkPrinters, jsonEncode(list));
  }

  // ── Dispositivos IoT Personalizados (Básculas, Lectores, Pantallas) ────
  static const String _prefIotDevices = 'iot_devices';

  List<PrinterModel> get savedIotDevices {
    final raw = _prefs?.getString(_prefIotDevices);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => PrinterModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveIotDevices(List<PrinterModel> devices) async {
    final list = devices.map((d) => d.toJson()).toList();
    await _prefs?.setString(_prefIotDevices, jsonEncode(list));
  }
}
