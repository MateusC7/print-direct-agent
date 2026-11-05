import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/print_job_model.dart';
import '../../models/printer_model.dart';
import '../logger_service.dart';
import 'printer_service.dart';

/// Resultado final de un trabajo de impresión.
/// Se emite al completarse con éxito o al agotar los reintentos.
class PrintJobResult {
  final String uuid;
  final bool success;
  const PrintJobResult(this.uuid, this.success);
}

/// Servicio de Cola de Impresión Persistente.
/// Proporciona Idempotencia, Mutex por Impresora y Reintentos Automáticos de Fondo.
class PrintQueueService extends ChangeNotifier {
  static final PrintQueueService instance = PrintQueueService._();
  PrintQueueService._();

  late final PrinterService _printerService;
  final List<PrintJobModel> _jobs = [];
  bool _initialized = false;
  File? _queueFile;

  /// Emite el resultado final de cada trabajo (éxito o fallo definitivo).
  final StreamController<PrintJobResult> _resultController =
      StreamController<PrintJobResult>.broadcast();
  Stream<PrintJobResult> get onJobResult => _resultController.stream;

  static const int maxRetries = 10;

  // Locks por impresora para evitar accesos concurrentes (consecutivos / superpuestos)
  final Map<String, bool> _activeLocks = {};

  List<PrintJobModel> get jobs => List.unmodifiable(_jobs);

  final Set<String> _completedUuids = {};

  Future<void> init(PrinterService printerService) async {
    if (_initialized) return;
    _printerService = printerService;

    try {
      Directory baseDir;
      try {
        baseDir = await getApplicationSupportDirectory();
      } catch (_) {
        baseDir = await getApplicationDocumentsDirectory();
      }
      _queueFile = File('${baseDir.path}/print_queue.json');
      await _loadQueue();
      _initialized = true;

      // Iniciar el bucle periódico de reintentos
      _startQueueProcessor();
      LoggerService.info(
          '[QUEUE] Inicializada con ${_jobs.length} trabajo(s) en cola.');
    } catch (e) {
      LoggerService.error('[QUEUE] Error inicializando base de cola local: $e');
    }
  }

  // ── Cargar / Guardar la Cola Persistente ─────────────────────────────
  Future<void> _loadQueue() async {
    if (_queueFile == null || !await _queueFile!.exists()) return;
    try {
      final content = await _queueFile!.readAsString();
      if (content.isEmpty) return;
      final rawList = jsonDecode(content) as List<dynamic>;
      _jobs.clear();
      _jobs.addAll(rawList
          .map((x) => PrintJobModel.fromJson(x as Map<String, dynamic>)));

      // Revertir estados inestables por apagado repentino
      for (final j in _jobs) {
        if (j.status == 'printing') {
          j.status = 'pending';
        } else if (j.status == 'completed') {
          _completedUuids.add(j.uuid);
        }
      }
      _pruneOldJobs();
    } catch (e) {
      LoggerService.error('[QUEUE] Error decodificando cola guardada: $e');
    }
  }

  Future<void> _saveQueue() async {
    if (_queueFile == null) return;
    try {
      final list = _jobs.map((j) => j.toJson()).toList();
      await _queueFile!.writeAsString(jsonEncode(list), flush: true);
    } catch (e) {
      LoggerService.error('[QUEUE] Error persistiendo la cola: $e');
    }
  }

  /// Limpia los trabajos completados o fallidos antiguos para no acumular basura
  void _pruneOldJobs() {
    final limit = DateTime.now().subtract(const Duration(minutes: 30));
    _jobs.removeWhere((j) =>
        (j.status == 'completed' || j.status == 'failed') &&
        j.timestamp.isBefore(limit));
    if (_completedUuids.length > 500) {
      _completedUuids.clear();
    }
  }

  // ── Métodos Públicos ─────────────────────────────────────────────────

  /// Encola un nuevo trabajo. Si ya existe el UUID, retorna el existente para evitar duplicados (Idempotencia).
  Future<PrintJobModel> enqueue({
    required String uuid,
    required String printerName,
    required List<int> bytes,
    required String rawType,
    bool openCashbox = false,
  }) async {
    // 1. Idempotencia: Verificar duplicados en completados o en cola
    if (_completedUuids.contains(uuid)) {
      LoggerService.info(
          '[QUEUE] Trabajo ya completado previamente (UUID: $uuid). Ignorando re-impresión.');
      return PrintJobModel(
        uuid: uuid,
        printerName: printerName,
        bytes: Uint8List(0),
        rawType: rawType,
        openCashbox: openCashbox,
        timestamp: DateTime.now(),
        status: 'completed',
      );
    }

    final existingIndex = _jobs.indexWhere((j) => j.uuid == uuid);
    if (existingIndex != -1) {
      LoggerService.info(
          '[QUEUE] Petición duplicada interceptada (UUID: $uuid). Ignorando re-impresión.');
      return _jobs[existingIndex];
    }

    // 2. Crear y persistir el trabajo
    final job = PrintJobModel(
      uuid: uuid,
      printerName: printerName,
      bytes: Uint8List.fromList(bytes),
      rawType: rawType,
      openCashbox: openCashbox,
      timestamp: DateTime.now(),
    );

    _jobs.add(job);
    _saveQueue();
    notifyListeners();

    // Iniciar procesamiento asíncrono inmediato del nuevo elemento
    _processJob(job);

    return job;
  }

  PrintJobModel? getJob(String uuid) {
    try {
      return _jobs.firstWhere((j) => j.uuid == uuid);
    } catch (_) {
      return null;
    }
  }

  // ── Procesamiento en Segundo Plano y Mutex Locks ───────────────────

  void _startQueueProcessor() {
    Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!_initialized) return;
      _pruneOldJobs();

      // Obtener pendientes y fallidos con reintentos restantes
      final pendingJobs = _jobs
          .where((j) =>
              j.status == 'pending' ||
              (j.status == 'failed' && j.retryCount < maxRetries))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      for (final job in pendingJobs) {
        // Mutex: Si esta impresora ya está en uso, saltamos al siguiente
        if (_activeLocks[job.printerName] == true) continue;

        _processJob(job);
      }
    });
  }

  Future<void> _processJob(PrintJobModel job) async {
    if (_activeLocks[job.printerName] == true) return;

    _activeLocks[job.printerName] = true;
    job.status = 'printing';
    notifyListeners();

    try {
      LoggerService.info(
          '[QUEUE] Procesando impresion de trabajo "${job.printerName}" (UUID: ${job.uuid.substring(0, job.uuid.length.clamp(0, 8))}...)');

      final printers = await _printerService.getAllPrinters();
      PrinterModel? target;
      try {
        target = printers.firstWhere((p) => p.name == job.printerName);
      } catch (_) {
        target = PrinterModel(name: job.printerName, type: PrinterType.local);
      }

      final result = await _printerService.printRaw(
        printer: target,
        bytes: job.bytes.toList(),
        rawType: job.rawType,
        openCashbox: job.openCashbox,
      );

      if (result.success) {
        job.status = 'completed';
        job.errorMessage = null;
        _completedUuids.add(job.uuid);
        LoggerService.info(
            '[QUEUE] [OK] Trabajo impreso con exito en "${job.printerName}"');
        _resultController.add(PrintJobResult(job.uuid, true));
      } else {
        job.status = 'failed';
        job.errorMessage = result.message;
        job.retryCount++;
        LoggerService.error(
            '[QUEUE] [ERROR] Fallo imprimiendo en "${job.printerName}": ${result.message} (Intento ${job.retryCount}/$maxRetries)');
        if (job.retryCount >= maxRetries) {
          _resultController.add(PrintJobResult(job.uuid, false));
        }
      }
    } catch (e) {
      job.status = 'failed';
      job.errorMessage = e.toString();
      job.retryCount++;
      LoggerService.error(
          '[QUEUE] [ERROR] Excepcion inesperada en "${job.printerName}": $e');
      if (job.retryCount >= maxRetries) {
        _resultController.add(PrintJobResult(job.uuid, false));
      }
    } finally {
      _activeLocks[job.printerName] = false;
      await _saveQueue();
      notifyListeners();
    }
  }
}
