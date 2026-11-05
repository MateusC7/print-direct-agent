import 'auto_start_service.dart';

/// Compatibilidad regresiva: delega a AutoStartService
class WindowsAutoStartService {
  WindowsAutoStartService._();
  static final WindowsAutoStartService instance = WindowsAutoStartService._();

  Future<bool> isAutoStartEnabled() => AutoStartService.instance.isAutoStartEnabled();
  Future<bool> enableAutoStart() => AutoStartService.instance.enableAutoStart();
  Future<bool> disableAutoStart() => AutoStartService.instance.disableAutoStart();
  Future<bool> setAutoStart(bool enable) => AutoStartService.instance.setAutoStart(enable);
}
