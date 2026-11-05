import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/settings_service.dart';
import '../services/system/windows_auto_start_service.dart';

/// Provider de ajustes de la aplicación.
/// Expone: tema, idioma, puerto, auto-arranque, cloud relay y sincronización con persistencia automática.
class SettingsProvider extends ChangeNotifier {
  final SettingsService _svc = SettingsService.instance;

  late String _theme;
  late String _lang;
  late int _port;
  late String _odooUrl;
  late bool _autoLaunchPos;
  late String _defaultPrinterId;
  late String _odooUsername;
  late String _odooPassword;
  late bool _rememberCredentials;
  late String _odooProtocol;
  late String _apiToken;
  late String _scaleProtocol;
  late String _deviceName;
  late String _deviceUuid;
  late bool _autoStartWindows;
  late bool _enableCloudRelay;
  late bool _enableOdooHeartbeat;
  late bool _enableAck;
  late bool _enableSignature;
  late int _pollIntervalMs;

  SettingsProvider() {
    _theme = _svc.theme;
    _lang = _svc.lang;
    _port = _svc.port;
    _odooUrl = _svc.odooUrl;
    _autoLaunchPos = _svc.autoLaunchPos;
    _defaultPrinterId = _svc.defaultPrinterId;
    _odooUsername = _svc.odooUsername;
    _odooPassword = _svc.odooPassword;
    _rememberCredentials = _svc.rememberCredentials;
    _odooProtocol = _svc.odooProtocol;
    _apiToken = _svc.apiToken;
    _scaleProtocol = _svc.scaleProtocol;
    _deviceName = _svc.deviceName;
    _deviceUuid = _svc.deviceUuid;
    _autoStartWindows = _svc.autoStartWindows;
    _enableCloudRelay = _svc.enableCloudRelay;
    _enableOdooHeartbeat = _svc.enableOdooHeartbeat;
    _enableAck = _svc.enableAck;
    _enableSignature = _svc.enableSignature;
    _pollIntervalMs = _svc.pollIntervalMs;
  }

  String get theme => _theme;
  String get lang => _lang;
  int get port => _port;
  String get odooUrl => _odooUrl;
  bool get autoLaunchPos => _autoLaunchPos;
  String get defaultPrinterId => _defaultPrinterId;
  String get odooUsername => _odooUsername;
  String get odooPassword => _odooPassword;
  bool get rememberCredentials => _rememberCredentials;
  String get odooProtocol => _odooProtocol;
  String get apiToken => _apiToken;
  String get scaleProtocol => _scaleProtocol;
  String get deviceName => _deviceName;
  String get deviceUuid => _deviceUuid;
  bool get autoStartWindows => _autoStartWindows;
  bool get enableCloudRelay => _enableCloudRelay;
  bool get enableOdooHeartbeat => _enableOdooHeartbeat;
  bool get enableAck => _enableAck;
  bool get enableSignature => _enableSignature;
  int get pollIntervalMs => _pollIntervalMs;

  bool get isDark => _theme == 'dark';

  Future<void> setTheme(String value) async {
    _theme = value;
    await _svc.setTheme(value);
    notifyListeners();
  }

  Future<void> setLang(String value) async {
    _lang = value;
    await _svc.setLang(value);
    notifyListeners();
  }

  Future<void> setPort(int value) async {
    _port = value;
    await _svc.setPort(value);
    notifyListeners();
  }

  Future<void> setOdooUrl(String value) async {
    _odooUrl = value;
    await _svc.setOdooUrl(value);
    notifyListeners();
  }

  Future<void> setAutoLaunchPos(bool value) async {
    _autoLaunchPos = value;
    await _svc.setAutoLaunchPos(value);
    notifyListeners();
  }

  Future<void> setDefaultPrinterId(String value) async {
    _defaultPrinterId = value;
    await _svc.setDefaultPrinterId(value);
    notifyListeners();
  }

  Future<void> setOdooUsername(String value) async {
    _odooUsername = value;
    await _svc.setOdooUsername(value);
    notifyListeners();
  }

  Future<void> setOdooPassword(String value) async {
    _odooPassword = value;
    await _svc.setOdooPassword(value);
    notifyListeners();
  }

  Future<void> setRememberCredentials(bool value) async {
    _rememberCredentials = value;
    await _svc.setRememberCredentials(value);
    notifyListeners();
  }

  Future<void> setOdooProtocol(String value) async {
    _odooProtocol = value;
    await _svc.setOdooProtocol(value);
    notifyListeners();
  }

  Future<void> setApiToken(String value) async {
    _apiToken = value;
    await _svc.setApiToken(value);
    notifyListeners();
  }

  Future<void> setScaleProtocol(String value) async {
    _scaleProtocol = value;
    await _svc.setScaleProtocol(value);
    notifyListeners();
  }

  Future<void> setDeviceName(String value) async {
    _deviceName = value;
    await _svc.setDeviceName(value);
    notifyListeners();
  }

  Future<void> setDeviceUuid(String value) async {
    _deviceUuid = value;
    await _svc.setDeviceUuid(value);
    notifyListeners();
  }

  Future<void> setAutoStartWindows(bool value) async {
    _autoStartWindows = value;
    await _svc.setAutoStartWindows(value);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await WindowsAutoStartService.instance.setAutoStart(value);
    }
    notifyListeners();
  }

  Future<void> setEnableCloudRelay(bool value) async {
    _enableCloudRelay = value;
    await _svc.setEnableCloudRelay(value);
    notifyListeners();
  }

  Future<void> setEnableOdooHeartbeat(bool value) async {
    _enableOdooHeartbeat = value;
    await _svc.setEnableOdooHeartbeat(value);
    notifyListeners();
  }

  Future<void> setEnableAck(bool value) async {
    _enableAck = value;
    await _svc.setEnableAck(value);
    notifyListeners();
  }

  Future<void> setEnableSignature(bool value) async {
    _enableSignature = value;
    await _svc.setEnableSignature(value);
    notifyListeners();
  }

  Future<void> setPollIntervalMs(int value) async {
    _pollIntervalMs = value;
    await _svc.setPollIntervalMs(value);
    notifyListeners();
  }

  /// Traduce una clave usando el idioma actual.
  String t(String key) {
    try {
      // ignore: avoid_dynamic_calls
      return _translations[_lang]?[key] ?? _translations['es']![key] ?? key;
    } catch (_) {
      return key;
    }
  }

  static const Map<String, Map<String, String>> _translations = {};
}
