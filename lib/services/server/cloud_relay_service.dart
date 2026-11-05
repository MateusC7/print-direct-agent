import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;
import '../../models/printer_model.dart';
import '../logger_service.dart';
import '../printer/printer_service.dart';
import '../printer/print_queue_service.dart';
import '../settings_service.dart';
import 'relay_crypto.dart';

enum CloudRelayStatus { disconnected, connecting, connected, error }

/// Servicio de Canal Inverso Profesional.
/// Conecta la app de forma saliente hacia el Servidor del Sistema.
///
/// Beneficios:
/// 1. Cero certificados SSL locales (100% compatible con HTTPS y HTTP).
/// 2. Funciona detrás de cualquier router / NAT sin abrir puertos.
/// 3. Permite imprimir desde móviles, tablets y PCs sin configurar IPs.
/// 4. Compatible con Windows, macOS, iOS, Android y Linux.
///
/// Incluye firma HMAC por petición y confirmación (ACK) de trabajos.
class CloudRelayService extends ChangeNotifier {
  CloudRelayService._();
  static final CloudRelayService instance = CloudRelayService._();

  Timer? _pollingTimer;
  Timer? _reconnectTimer;
  CloudRelayStatus _status = CloudRelayStatus.disconnected;
  String _lastError = '';
  PrinterService? _printerService;
  bool _manualDisconnect = false;
  bool _isPolling = false;
  int _pollGeneration = 0;
  DateTime? _lastJobAt;
  static const int _activePollMs = 500;
  static const Duration _activeWindow = Duration(seconds: 30);
  // After a long quiet period the cadence relaxes: fewer requests per
  // restaurant on the shared server. The next job restores the fast cadence.
  static const Duration _deepIdleAfter = Duration(minutes: 15);
  static const int _deepIdleMs = 3000;
  static const int _maxErrorBackoffMs = 30000;
  int _consecutiveErrors = 0;
  DateTime _lastActivityAt = DateTime.now();

  // Long-poll: the server holds the request until a job arrives (near-zero
  // latency, ~1 request per 20 s). Any sign the server cannot hold requests
  // (old version, proxy answering instantly) falls back to classic polling.
  static const int _longPollWaitSeconds = 20;
  static const Duration _longPollRetryAfter = Duration(minutes: 10);
  DateTime? _longPollRetryAt;
  int _immediateStreak = 0;
  int _longPollFailures = 0;
  bool _chainNext = false;

  bool get _longPollActive =>
      _longPollRetryAt == null || DateTime.now().isAfter(_longPollRetryAt!);

  void _disableLongPoll(String reason) {
    _longPollRetryAt = DateTime.now().add(_longPollRetryAfter);
    _immediateStreak = 0;
    _longPollFailures = 0;
    _chainNext = false;
    _consecutiveErrors = 0;
    LoggerService.warn('[CANAL] Espera larga no disponible ($reason); '
        'se usa consulta periódica.');
  }

  // Reused clients keep TCP/TLS connections alive between polls.
  http.Client? _strictClient;
  http.Client? _lenientClient;

  void _stopPolling() {
    _pollGeneration++;
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  String _baseUrl = '';
  String _dbName = '';
  String? _dbSessionCookie;
  StreamSubscription<PrintJobResult>? _resultSub;

  CloudRelayStatus get status => _status;
  String get lastError => _lastError;
  bool get isConnected => _status == CloudRelayStatus.connected;

  void init(PrinterService printerService) {
    _printerService = printerService;
  }

  // ─────────────────────────────────────────────────────────────────────
  // Conexión
  // ─────────────────────────────────────────────────────────────────────
  Future<void> connect() async {
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    _stopPolling();
    _dbSessionCookie = null;
    _consecutiveErrors = 0;
    _lastActivityAt = DateTime.now();
    _longPollRetryAt = null;
    _immediateStreak = 0;
    _chainNext = false;

    final settings = SettingsService.instance;
    _baseUrl = _normalizeBaseUrl(settings.odooUrl);
    if (_baseUrl.isEmpty) {
      _setStatus(CloudRelayStatus.disconnected,
          'Dirección del sistema no configurada');
      return;
    }

    // Odoo 18 no usa ?db= en las rutas de controlador: resolvemos la base
    // automáticamente con una sesión vía /web/login?db=...
    _dbName = _extractDbFromUrl(_baseUrl);

    final token = _token(settings);
    final deviceId = settings.deviceUuid;

    _setStatus(CloudRelayStatus.connecting);
    LoggerService.info('🌐 [CANAL] Conectando con el Sistema: $_baseUrl');

    try {
      await _ensureDbSession();

      // Registro inicial de impresoras en el servidor
      final regResponse = await _registerWithServer(_baseUrl, token, deviceId);

      if (_isSuccessfulRegistration(regResponse)) {
        _setStatus(CloudRelayStatus.connected);
        LoggerService.info('✅ [CANAL] Conectado y listo para imprimir.');
        _subscribeAckResults();
        _startPollingLoop(_baseUrl, token, deviceId);
      } else {
        _onConnectionClosed(_describeHttpError(regResponse));
      }
    } catch (e) {
      LoggerService.error('❌ [CANAL] Fallo conectando al sistema: $e');
      _onConnectionClosed('Fallo de conexión: $e');
    }
  }

  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _stopPolling();
    _setStatus(CloudRelayStatus.disconnected);
    LoggerService.info('🔌 [CANAL] Desconectado manualmente.');
  }

  void _onConnectionClosed(String reason) {
    _setStatus(CloudRelayStatus.disconnected, reason);
    _stopPolling();

    if (!_manualDisconnect) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 5), () {
        LoggerService.info(
            '🔄 [CANAL] Reintentando conexión con el Sistema...');
        connect();
      });
    }
  }

  /// Petición JSON con firma, reutilizable por otros servicios
  /// (por ejemplo, el heartbeat/sincronización de dispositivos).
  Future<http.Response> signedPost(
    String baseUrl,
    String endpointPath,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final normalized = _normalizeBaseUrl(baseUrl);
    if (normalized.isEmpty) {
      throw StateError('Dirección del sistema no configurada');
    }
    _baseUrl = normalized;
    return _postJson(_endpointUri(normalized, endpointPath), payload,
        timeout: timeout);
  }

  Future<String> _localIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback &&
              (addr.address.startsWith('192.168.') ||
                  addr.address.startsWith('10.') ||
                  addr.address.startsWith('172.'))) {
            return addr.address;
          }
        }
      }
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  // ─────────────────────────────────────────────────────────────────────
  // Resolución automática de base (Odoo 18 no usa ?db= en controladores)
  // ─────────────────────────────────────────────────────────────────────
  String _extractDbFromUrl(String url) {
    try {
      final withScheme = url.startsWith('http://') || url.startsWith('https://')
          ? url
          : 'http://$url';
      return Uri.parse(withScheme).queryParameters['db'] ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Fija la base en la sesión de Odoo llamando a `/web/login?db=...`,
  /// que devuelve una cookie `session_id` ligada a esa base. Así las
  /// rutas del relay resuelven la base correcta aunque la URL traiga `?db=`.
  /// Sigue redirecciones (p. ej. HTTP -> HTTPS) hasta obtener la cookie.
  Future<void> _ensureDbSession() async {
    if (_dbName.isEmpty) return;
    final parsed = Uri.parse(_baseUrl);
    final String basePath = parsed.path.endsWith('/')
        ? parsed.path.substring(0, parsed.path.length - 1)
        : parsed.path;
    Uri current = parsed.replace(
      path: '$basePath/web/login',
      queryParameters: {'db': _dbName},
    );

    try {
      for (int hop = 0; hop < 5; hop++) {
        ({String? cookie, Uri? next}) result;
        try {
          result = await _probeLogin(current);
        } catch (e) {
          if (_isCertificateError(e) && _isLocalHost(current.host)) {
            result = await _probeLogin(current, allowInvalidCertificate: true);
          } else {
            rethrow;
          }
        }

        if (result.cookie != null) {
          _dbSessionCookie = result.cookie;
          LoggerService.info(
              '🔐 [CANAL] Base "$_dbName" seleccionada automáticamente.');
          return;
        }

        final next = result.next;
        if (next == null) break;

        // Si sube a HTTPS, actualiza la URL guardada para las siguientes peticiones.
        if (next.scheme == 'https' && parsed.scheme == 'http') {
          final saved = SettingsService.instance.odooUrl;
          if (saved.startsWith('http://')) {
            SettingsService.instance
                .setOdooUrl(saved.replaceFirst('http://', 'https://'));
          }
        }
        current = next;
      }
      LoggerService.warn(
          '⚠️ [CANAL] No se pudo seleccionar la base "$_dbName".');
    } catch (e) {
      LoggerService.warn('[CANAL] Error estableciendo sesión de base: $e');
    }
  }

  /// Hace la petición de login sin seguir redirecciones y devuelve la cookie
  /// de sesión (si el servidor la emite) y el siguiente salto (si redirige).
  Future<({String? cookie, Uri? next})> _probeLogin(
    Uri uri, {
    bool allowInvalidCertificate = false,
  }) async {
    final request = http.Request('GET', uri)..followRedirects = false;
    final streamed =
        await _httpClient(allowInvalidCertificate: allowInvalidCertificate)
            .send(request)
            .timeout(const Duration(seconds: 15));

    final cookie = _extractSessionCookie(streamed.headers);
    final status = streamed.statusCode;
    final location = streamed.headers['location'];
    await streamed.stream.drain<void>();

    Uri? next;
    if (cookie == null &&
        status >= 300 &&
        status < 400 &&
        location != null &&
        location.isNotEmpty) {
      var candidate = Uri.parse(location);
      if (!candidate.hasScheme) candidate = uri.resolve(location);
      if (candidate.toString() != uri.toString()) next = candidate;
    }
    return (cookie: cookie, next: next);
  }

  String? _extractSessionCookie(Map<String, String> headers) {
    final raw = headers['set-cookie'];
    if (raw == null || raw.isEmpty) return null;
    final match = RegExp(r'session_id=([^;,\s]+)').firstMatch(raw);
    if (match == null) return null;
    return 'session_id=${match.group(1)}';
  }

  /// POST con reintento: si la sesión de base expiró (404), la re-establece.
  Future<http.Response> _postJsonWithDbRetry(
    Uri uri,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    var response = await _postJson(uri, payload, timeout: timeout);
    if (response.statusCode == 404 && _dbName.isNotEmpty) {
      _dbSessionCookie = null;
      await _ensureDbSession();
      if (_dbSessionCookie != null) {
        response = await _postJson(uri, payload, timeout: timeout);
      }
    }
    return response;
  }

  // ─────────────────────────────────────────────────────────────────────
  // Helpers de URL / token / headers
  // ─────────────────────────────────────────────────────────────────────
  String _token(SettingsService settings) =>
      settings.apiToken.isNotEmpty ? settings.apiToken : settings.deviceUuid;

  String _normalizeBaseUrl(String url) {
    var clean = url.trim();
    if (clean.isEmpty) return '';
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      final isLocal = clean.startsWith('localhost') ||
          clean.startsWith('127.0.0.1') ||
          clean.startsWith('192.168.') ||
          clean.startsWith('10.');
      clean = isLocal ? 'http://$clean' : 'https://$clean';
    }
    return clean;
  }

  Uri _endpointUri(String baseUrl, String endpointPath) {
    final parsed = Uri.parse(baseUrl);
    final String basePath = parsed.path.endsWith('/')
        ? parsed.path.substring(0, parsed.path.length - 1)
        : parsed.path;
    final String finalPath = '$basePath$endpointPath';
    // Conserva los query params originales de la URL (p. ej. `?db=...`),
    // de modo que configuraciones previas sigan funcionando tal cual.
    return parsed.replace(path: finalPath);
  }

  /// Shared client per certificate mode: reusing it keeps the TCP/TLS
  /// connection alive, so each poll skips the full handshake.
  http.Client _httpClient({bool allowInvalidCertificate = false}) {
    final cached = allowInvalidCertificate ? _lenientClient : _strictClient;
    if (cached != null) return cached;

    final ioClient = HttpClient();
    ioClient.badCertificateCallback =
        (X509Certificate cert, String host, int port) =>
            allowInvalidCertificate || _isLocalHost(host);
    ioClient.connectionTimeout = const Duration(seconds: 10);
    ioClient.idleTimeout = const Duration(seconds: 30);
    final client = http_io.IOClient(ioClient);
    if (allowInvalidCertificate) {
      _lenientClient = client;
    } else {
      _strictClient = client;
    }
    return client;
  }

  /// Drops pooled connections (e.g. after the server closed an idle socket).
  void _resetHttpClients() {
    _strictClient?.close();
    _lenientClient?.close();
    _strictClient = null;
    _lenientClient = null;
  }

  bool _isLocalHost(String host) {
    final h = host.toLowerCase();
    return h == 'localhost' ||
        h == '127.0.0.1' ||
        h == '::1' ||
        h.startsWith('192.168.') ||
        h.startsWith('10.') ||
        h.startsWith('172.') ||
        h.endsWith('.local');
  }

  bool _isCertificateError(Object e) {
    if (e is HandshakeException) return true;
    final s = e.toString().toLowerCase();
    return s.contains('certificate') || s.contains('handshake');
  }

  Map<String, String> _buildHeaders(String bodyStr, {required bool sign}) {
    final settings = SettingsService.instance;
    final headers = <String, String>{'Content-Type': 'application/json'};

    if (_dbSessionCookie != null) {
      headers['Cookie'] = _dbSessionCookie!;
    }

    if (sign && settings.enableSignature) {
      final timestamp =
          (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      headers['X-Timestamp'] = timestamp;
      headers['X-Signature'] =
          RelayCrypto.signBody(_token(settings), bodyStr, timestamp);
    }
    return headers;
  }

  /// Realiza una petición POST JSON con firma opcional y redirecciones.
  /// Si el certificado no es válido (salvo hosts locales), reintenta en modo compatible.
  Future<http.Response> _postJson(
    Uri uri,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 10),
    bool sign = true,
  }) async {
    try {
      return await _postJsonOnce(uri, payload, timeout: timeout, sign: sign);
    } catch (e) {
      // Solo se tolera un certificado inválido en hosts de la red local; un
      // host público con certificado inválido no recibe el token ni los tickets.
      if (_isCertificateError(e) && _isLocalHost(uri.host)) {
        LoggerService.warn(
            '[CANAL] Certificado no válido; reintentando en modo compatible.');
        return await _postJsonOnce(uri, payload,
            timeout: timeout, sign: sign, allowInvalidCertificate: true);
      }
      rethrow;
    }
  }

  Future<http.Response> _postJsonOnce(
    Uri uri,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 10),
    bool sign = true,
    bool allowInvalidCertificate = false,
  }) async {
    final bodyStr = jsonEncode(payload);

    Future<http.Response> doPost(Uri target) {
      return _httpClient(allowInvalidCertificate: allowInvalidCertificate)
          .post(target,
              headers: _buildHeaders(bodyStr, sign: sign), body: bodyStr)
          .timeout(timeout);
    }

    Uri currentUri = uri;
    http.Response response;
    try {
      response = await doPost(currentUri);
    } on SocketException {
      // A pooled keep-alive socket may have been closed by the server/proxy:
      // retry once on a fresh connection.
      _resetHttpClients();
      response = await doPost(currentUri);
    } on http.ClientException {
      _resetHttpClients();
      response = await doPost(currentUri);
    }

    // Redirección automática (ej. Nginx HTTP -> HTTPS con 301)
    if (response.statusCode == 301 ||
        response.statusCode == 302 ||
        response.statusCode == 307 ||
        response.statusCode == 308) {
      final location = response.headers['location'];
      Uri? redirectedUri;

      if (location != null && location.isNotEmpty) {
        redirectedUri = Uri.parse(location);
        if (!redirectedUri.hasScheme) {
          redirectedUri = currentUri.resolve(location);
        }
        if (currentUri.hasQuery && !redirectedUri.hasQuery) {
          redirectedUri = redirectedUri.replace(
              queryParameters: currentUri.queryParameters);
        }
      } else if (currentUri.scheme == 'http') {
        redirectedUri = currentUri.replace(scheme: 'https');
      }

      if (redirectedUri != null) {
        LoggerService.info(
            '🔀 [CANAL] Redirección automática (${response.statusCode}) -> $redirectedUri');
        if (redirectedUri.scheme == 'https') {
          final currentSaved = SettingsService.instance.odooUrl;
          if (currentSaved.startsWith('http://')) {
            SettingsService.instance
                .setOdooUrl(currentSaved.replaceFirst('http://', 'https://'));
          }
        }
        response = await doPost(redirectedUri);
      }
    }
    return response;
  }

  // ─────────────────────────────────────────────────────────────────────
  // Registro
  // ─────────────────────────────────────────────────────────────────────
  Future<http.Response> _registerWithServer(
      String baseUrl, String token, String deviceId) async {
    final printers = await _printerService?.getAllPrinters() ?? [];
    final printersData = printers
        .map((p) => {
              'name': p.name,
              'type': p.type.name,
              'address': p.displayAddress,
            })
        .toList();

    final settings = SettingsService.instance;
    final localIp = await _localIp();
    final proxyUrl = 'http://$localIp:${settings.port}';

    final uri = _endpointUri(baseUrl, '/print_direct/register_agent');
    final response = await _postJsonWithDbRetry(
      uri,
      {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'token': token,
          'device_id': deviceId,
          'device_name': settings.deviceName.isNotEmpty
              ? settings.deviceName
              : 'Agente Local',
          'ip_url': proxyUrl,
          'printers': printersData,
        }
      },
      timeout: const Duration(seconds: 20),
    );

    if (response.statusCode == 200) {
      LoggerService.info(
          '📤 [HARDWARE] Sincronizadas ${printers.length} impresora(s).');
    } else {
      LoggerService.warn(
          '⚠️ [CANAL] Registro respondió HTTP ${response.statusCode}');
    }
    return response;
  }

  bool _isSuccessfulRegistration(http.Response response) {
    if (response.statusCode != 200) return false;
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body.containsKey('error')) return false;
      final result = body['result'];
      if (result is Map && result['status'] == 'error') return false;
      return body.containsKey('result');
    } catch (_) {
      return false;
    }
  }

  String _describeHttpError(http.Response response) {
    switch (response.statusCode) {
      case 404:
        return 'No se pudo contactar al Sistema (HTTP 404). Revisa la dirección configurada.';
      case 401:
      case 403:
        return 'Clave de seguridad rechazada (HTTP ${response.statusCode}).';
      default:
        return 'El Sistema respondió HTTP ${response.statusCode}.';
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Polling
  // ─────────────────────────────────────────────────────────────────────
  void _startPollingLoop(String baseUrl, String token, String deviceId) {
    _pollingTimer?.cancel();
    final generation = ++_pollGeneration;

    // Adaptive cadence: fast right after print activity (bursts of orders),
    // the configured interval when idle.
    Duration nextDelay() {
      // Server unreachable: back off exponentially instead of hammering it.
      if (_consecutiveErrors > 0) {
        final shift = (_consecutiveErrors - 1).clamp(0, 5).toInt();
        final backoff =
            (2000 << shift).clamp(2000, _maxErrorBackoffMs).toInt();
        return Duration(milliseconds: backoff);
      }
      if (_chainNext) {
        _chainNext = false;
        return Duration.zero;
      }
      final idleMs = SettingsService.instance.pollIntervalMs.clamp(250, 10000);
      final fastMs = idleMs < _activePollMs ? idleMs : _activePollMs;
      final now = DateTime.now();
      final last = _lastJobAt;
      final active = last != null && now.difference(last) < _activeWindow;
      if (active) return Duration(milliseconds: fastMs);
      final quietSince = last ?? _lastActivityAt;
      final deepIdle = now.difference(quietSince) > _deepIdleAfter;
      return Duration(
          milliseconds: deepIdle && idleMs < _deepIdleMs ? _deepIdleMs : idleMs);
    }

    void schedule() {
      if (generation != _pollGeneration) return;
      _pollingTimer = Timer(nextDelay(), () async {
        try {
          await _pollOnce(baseUrl, token, deviceId);
        } finally {
          schedule();
        }
      });
    }

    schedule();
  }

  Future<void> _pollOnce(String baseUrl, String token, String deviceId) async {
    {
      if (_isPolling ||
          _manualDisconnect ||
          _status != CloudRelayStatus.connected) {
        return;
      }
      _isPolling = true;

      try {
        final useLong = _longPollActive;
        final started = DateTime.now();
        final uri = _endpointUri(baseUrl,
            useLong ? '/print_direct/poll_wait' : '/print_direct/poll_jobs');
        final response = await _postJsonWithDbRetry(
          uri,
          {
            'jsonrpc': '2.0',
            'method': 'call',
            'params': {
              'token': token,
              'device_id': deviceId,
              if (useLong) 'wait': _longPollWaitSeconds,
            },
          },
          timeout: Duration(seconds: useLong ? _longPollWaitSeconds + 15 : 6),
        );

        if (response.statusCode >= 500) {
          _consecutiveErrors++;
          // The gevent route can fail independently of the regular one:
          // after two failures switch to classic polling instead of waiting.
          if (useLong && ++_longPollFailures >= 2) {
            _disableLongPoll('HTTP ${response.statusCode}');
          }
        } else {
          _consecutiveErrors = 0;
          if (useLong) _longPollFailures = 0;
        }
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final result = body['result'] as Map<String, dynamic>?;
          if (useLong) {
            final held = result?['waited'] == true ||
                DateTime.now().difference(started) > const Duration(seconds: 3);
            final hasJobs = result != null &&
                result['jobs'] is List &&
                (result['jobs'] as List).isNotEmpty;
            if (result == null || body['error'] != null) {
              _disableLongPoll('respuesta inválida');
            } else if (hasJobs || held) {
              // Re-open the wait right away so no job waits for a timer.
              _immediateStreak = 0;
              _chainNext = true;
            } else if (++_immediateStreak >= 3) {
              _disableLongPoll('el servidor responde sin esperar');
            }
          }
          if (result != null && result['jobs'] is List) {
            final jobs = result['jobs'] as List;
            if (jobs.isNotEmpty) _lastJobAt = DateTime.now();
            for (final j in jobs) {
              if (j is Map<String, dynamic>) {
                await _processPrintJob(j);
              }
            }
          }
        } else if (response.statusCode == 404) {
          if (useLong) {
            _disableLongPoll('HTTP 404');
          } else {
            LoggerService.warn(_describeHttpError(response));
          }
        }
      } catch (_) {
        // Corte momentáneo: se reintenta con espera creciente
        _consecutiveErrors++;
        if (_longPollActive && ++_longPollFailures >= 3) {
          _disableLongPoll('errores de red repetidos');
        }
      } finally {
        _isPolling = false;
      }
    }
  }

  /// Procesa los trabajos de impresión encolados
  Future<void> _processPrintJob(Map<String, dynamic> data) async {
    try {
      final printerName = (data['printer'] ?? data['printer_name']) as String?;
      final rawContent = (data['data'] ?? data['raw_data']) as String?;
      final rawType = (data['raw_type'] as String?) ?? 'raw';
      final openCashbox = data['open_cashbox'] == true;
      final jobUuid = data['job_uuid'] as String? ??
          'job-${DateTime.now().millisecondsSinceEpoch}';

      if (printerName == null || rawContent == null) return;

      LoggerService.info('[IMPRESION] Recibido trabajo para "$printerName"');

      if (_printerService == null) return;

      final printers = await _printerService!.getAllPrinters();
      PrinterModel? found;
      if (printerName.isNotEmpty &&
          printerName != 'POS-DEFAULT' &&
          printerName != 'default') {
        try {
          found = printers.firstWhere(
            (p) =>
                p.name.toLowerCase().trim() ==
                    printerName.toLowerCase().trim() ||
                p.name.toLowerCase().contains(printerName.toLowerCase()) ||
                printerName.toLowerCase().contains(p.name.toLowerCase()),
          );
        } catch (_) {}
      }
      final PrinterModel target = found ??
          (printers.isNotEmpty
              ? printers.firstWhere(
                  (p) =>
                      p.type == PrinterType.network ||
                      p.type == PrinterType.sunmi ||
                      p.type == PrinterType.bluetooth,
                  orElse: () => printers.first,
                )
              : PrinterModel(name: printerName, type: PrinterType.local));

      List<int> bytes = base64Decode(rawContent.trim());
      String finalRawType = rawType;

      // Encolamos en la cola persistente con Mutex Lock.
      // El resultado se confirma automáticamente vía onJobResult -> ack_jobs.
      await PrintQueueService.instance.enqueue(
        uuid: jobUuid,
        printerName: target.name,
        bytes: bytes,
        rawType: finalRawType,
        openCashbox: openCashbox,
      );

      LoggerService.info('[IMPRESION] Trabajo "$jobUuid" encolado.');
    } catch (e) {
      LoggerService.error('[IMPRESION] [ERROR] Error procesando trabajo: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Confirmación (ACK)
  // ─────────────────────────────────────────────────────────────────────
  void _subscribeAckResults() {
    _resultSub ??= PrintQueueService.instance.onJobResult.listen((result) {
      _sendAck(result.uuid, result.success);
    });
  }

  Future<void> _sendAck(String jobUuid, bool success) async {
    final settings = SettingsService.instance;
    if (!settings.enableAck) return;
    if (_baseUrl.isEmpty) return;

    final token = _token(settings);
    try {
      final response = await _postJsonWithDbRetry(
        _endpointUri(_baseUrl, '/print_direct/ack_jobs'),
        {
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'token': token,
            'jobs': [
              {'job_uuid': jobUuid, 'success': success}
            ],
          },
        },
        timeout: const Duration(seconds: 8),
      );
      if (response.statusCode == 200) {
        LoggerService.info(
            '[CANAL] [ACK] Trabajo confirmado (success=$success).');
      } else {
        LoggerService.warn(
            '[CANAL] [ACK] No se pudo confirmar (HTTP ${response.statusCode}).');
      }
    } catch (e) {
      LoggerService.warn(
          '[CANAL] [ACK] Error confirmando trabajo $jobUuid: $e');
    }
  }

  void _setStatus(CloudRelayStatus s, [String error = '']) {
    _status = s;
    _lastError = error;
    notifyListeners();
  }

  @override
  void dispose() {
    _resultSub?.cancel();
    _stopPolling();
    _reconnectTimer?.cancel();
    super.dispose();
  }
}
