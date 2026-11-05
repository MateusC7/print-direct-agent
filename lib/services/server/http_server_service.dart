import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import '../printer/printer_service.dart';
import '../settings_service.dart';
import 'print_handler.dart';
import 'iot_box_handler.dart';
import 'ssl_service.dart';
import 'websocket_manager.dart';

enum ServerStatus { stopped, starting, running, error }

/// Servicio del servidor HTTP universal para Desktop y Móvil.
/// Permite conexiones locales HTTP directas sin certificados SSL,
/// compatible con Odoo, celulares y terminales POS.
class HttpServerService {
  HttpServerService._();
  static final HttpServerService instance = HttpServerService._();

  HttpServer? _server;
  HttpServer? _httpsServer;
  ServerStatus _status = ServerStatus.stopped;
  String _lastError = '';

  ServerStatus get status => _status;
  String get lastError => _lastError;
  bool get isRunning => _status == ServerStatus.running;

  Function(String)? onLog;
  Function(ServerStatus)? onStatusChange;

  void _log(String msg) => onLog?.call(msg);
  void _setStatus(ServerStatus s) {
    _status = s;
    onStatusChange?.call(s);
  }

  /// Obtiene la IP local real del dispositivo en la red Wi-Fi/LAN
  Future<String> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        final isVirtual = name.contains('virtual') ||
            name.contains('wsl') ||
            name.contains('docker') ||
            name.contains('vethernet') ||
            name.contains('loopback');

        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            final ip = addr.address;
            if (ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.')) {
              if (!isVirtual) return ip;
            }
          }
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  /// Inicia el servidor HTTP universal en el puerto configurado (ej: 18069).
  Future<bool> start({
    required PrinterService printerService,
    required int port,
  }) async {
    if (_status == ServerStatus.running) {
      _log('[ADVERTENCIA] El servidor ya está activo en el puerto $port');
      return true;
    }

    WebSocketManager.instance.init(printerService);
    _setStatus(ServerStatus.starting);
    final localIp = await getLocalIp();

    final printHandler = PrintHandler(
      printerService: printerService,
      port: port,
      getLocalIp: () => localIp,
    );

    final iotHandler = IotBoxHandler(
      printerService: printerService,
    );

    final cascade = Cascade()
        .add(printHandler.router.call)
        .add(iotHandler.router.call);

    final pipeline = const Pipeline()
        .addMiddleware(_corsMiddleware())
        .addMiddleware(_authMiddleware())
        .addMiddleware(logRequests(logger: (msg, isError) => _log(msg)))
        .addHandler(cascade.handler);

    try {
      // 1. Iniciar servidor HTTP en el puerto principal (sin requerir SSL)
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );
      _listenAndRoute(_server!, pipeline);
      _setStatus(ServerStatus.running);
      _log('[OK] Servidor HTTP activo en http://$localIp:$port');
      _log('[OK] Servidor local listo para recibir peticiones.');

      // 2. Intentar binding HTTPS complementario opcional en port + 1 si hay certificados
      if (!Platform.isAndroid && !Platform.isIOS) {
        try {
          final ssl = SslService.instance;
          final sslResult = await ssl.ensureCertificates();
          if (sslResult.success) {
            final context = SecurityContext()
              ..useCertificateChain(sslResult.certPath)
              ..usePrivateKey(sslResult.keyPath);

            _httpsServer = await HttpServer.bindSecure(
              InternetAddress.anyIPv4,
              port + 1,
              context,
              shared: true,
            );
            _listenAndRoute(_httpsServer!, pipeline);
            _log('[OK] Servidor HTTPS complementario activo en https://$localIp:${port + 1}');
          }
        } catch (_) {}
      }

      return true;
    } catch (e) {
      _lastError = e.toString();
      _setStatus(ServerStatus.error);
      _log('[ERROR] Error iniciando servidor HTTP: $e');
      return false;
    }
  }

  /// Escucha peticiones nativas para WebSocket y Shelf
  void _listenAndRoute(HttpServer server, Handler pipeline) {
    server.listen((HttpRequest request) async {
      final isWsPath = request.uri.path == '/websocket';
      final isUpgrade = WebSocketTransformer.isUpgradeRequest(request);

      if (isWsPath || isUpgrade) {
        _log('[WEBSOCKET] Conexión detectada. Path: ${request.uri.path}');
        final savedToken = SettingsService.instance.apiToken.trim();
        if (savedToken.isNotEmpty) {
          final queryToken = request.uri.queryParameters['token'] ?? '';
          final authHeader = request.headers.value('Authorization') ?? request.headers.value('authorization');
          String token = queryToken;

          if (token.isEmpty && authHeader != null && authHeader.startsWith('Bearer ')) {
            token = authHeader.substring(7).trim();
          }

          if (token != savedToken) {
            _log('[WEBSOCKET] Token inválido o no suministrado (403)');
            request.response.statusCode = HttpStatus.forbidden;
            request.response.write(jsonEncode({'status': 'error', 'message': 'Forbidden: Invalid API token'}));
            await request.response.close();
            return;
          }
        }

        try {
          final socket = await WebSocketTransformer.upgrade(request);
          WebSocketManager.instance.handleConnection(socket);
          _log('[WEBSOCKET] Cliente WebSocket conectado exitosamente');
        } catch (e) {
          _log('[WEBSOCKET ERROR] Fallo al establecer WebSocket: $e');
        }
        return;
      }

      shelf_io.handleRequest(request, pipeline);
    });
  }

  /// Detiene el servidor.
  Future<void> stop() async {
    await _server?.close(force: true);
    await _httpsServer?.close(force: true);
    _server = null;
    _httpsServer = null;
    _setStatus(ServerStatus.stopped);
    _log('[INFO] Servidor detenido.');
  }

  /// Reinicia el servidor.
  Future<bool> restart({
    required PrinterService printerService,
    required int port,
  }) async {
    await stop();
    return start(printerService: printerService, port: port);
  }

  /// Middleware CORS Universal con soporte para Private Network Access de Chrome/Edge
  static Middleware _corsMiddleware() {
    return (Handler inner) {
      return (Request req) async {
        final reqOrigin = req.headers['origin'] ?? '*';
        final corsHeaders = {
          'Access-Control-Allow-Origin': reqOrigin,
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization, X-Requested-With, Access-Control-Request-Private-Network, Access-Control-Request-Headers',
          'Access-Control-Allow-Credentials': 'true',
          'Access-Control-Allow-Private-Network': 'true', // Requerido por Chrome para llamadas a 192.168.x.x / localhost
          'Access-Control-Max-Age': '86400',
        };

        if (req.method == 'OPTIONS') {
          return Response.ok('', headers: corsHeaders);
        }
        final res = await inner(req);
        return res.change(headers: corsHeaders);
      };
    };
  }

  /// Indica si la petición viene de la propia máquina (127.0.0.1 / ::1).
  static bool _isLoopbackRequest(Request req) {
    final info = req.context['shelf.io.connection_info'];
    if (info is HttpConnectionInfo) {
      return info.remoteAddress.isLoopback;
    }
    return false;
  }

  /// Middleware de Autenticación por Token
  static Middleware _authMiddleware() {
    return (Handler inner) {
      return (Request req) async {
        final savedToken = SettingsService.instance.apiToken.trim();

        if (savedToken.isEmpty) {
          return inner(req);
        }

        if (req.method == 'OPTIONS') {
          return inner(req);
        }

        // Permitir endpoints de descubrimiento, sincronización y estado sin bloquear
        final path = req.url.path;
        if (path == 'get_printers' || path == '' || path == 'hw_proxy/status' || path == 'hw_proxy/hello' || path == 'info') {
          return inner(req);
        }

        // /sync_token reescribe el token y la URL del sistema: solo se acepta
        // sin credenciales desde la propia máquina (navegador local del POS).
        // Desde la red, exige el token vigente (la primera vinculación sin
        // token guardado ya pasa por el early-return de arriba).
        if (path == 'sync_token' && _isLoopbackRequest(req)) {
          return inner(req);
        }

        final authHeader = req.headers['Authorization'] ?? req.headers['authorization'];
        if (authHeader == null || !authHeader.startsWith('Bearer ')) {
          return Response(
            401,
            body: jsonEncode({'status': 'error', 'message': 'Missing or malformed Authorization header'}),
            headers: {
              'Content-Type': 'application/json',
              'Access-Control-Allow-Origin': '*',
              'Access-Control-Allow-Private-Network': 'true',
            },
          );
        }

        final token = authHeader.substring(7).trim();
        if (token != savedToken) {
          return Response(
            403,
            body: jsonEncode({'status': 'error', 'message': 'Forbidden: Invalid API token'}),
            headers: {
              'Content-Type': 'application/json',
              'Access-Control-Allow-Origin': '*',
              'Access-Control-Allow-Private-Network': 'true',
            },
          );
        }

        return inner(req);
      };
    };
  }
}
