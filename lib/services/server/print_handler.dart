import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../models/printer_model.dart';
import '../printer/printer_service.dart';
import '../printer/print_queue_service.dart';
import '../settings_service.dart';

/// Manejador de rutas HTTP del agente de impresión.
/// Expone: GET / · GET /info · GET /get_printers · POST /print_raw
class PrintHandler {
  final PrinterService printerService;
  final int port;

  // Función para obtener la IP local actual
  String Function() getLocalIp;

  PrintHandler({
    required this.printerService,
    required this.port,
    required this.getLocalIp,
  });

  Router get router {
    final r = Router();

    // ── GET / — Página de bypass SSL ──────────────────────────────────
    r.get('/', _handleRoot);

    // ── GET /info — Autodescubrimiento de hardware y token ─────────────
    r.get('/info', _handleInfo);
    r.add('OPTIONS', '/info',
        (Request req) => Response.ok('', headers: _corsJson));

    // ── GET /get_printers ──────────────────────────────────────────────
    r.get('/get_printers', _handleGetPrinters);
    r.add('OPTIONS', '/get_printers',
        (Request req) => Response.ok('', headers: _corsJson));

    // ── POST /print_raw ────────────────────────────────────────────────
    r.post('/print_raw', _handlePrintRaw);
    r.add('OPTIONS', '/print_raw',
        (Request req) => Response.ok('', headers: _corsJson));

    // ── POST /sync_token ──────────────────────────────────────────────
    r.post('/sync_token', _handleSyncToken);
    r.add('OPTIONS', '/sync_token',
        (Request req) => Response.ok('', headers: _corsJson));

    // ── GET /print_job/status/<uuid> ───────────────────────────────────
    r.get('/print_job/status/<uuid>', _handlePrintJobStatus);

    return r;
  }

  // ── HTML corporativo estilo Notion (Siempre blanco y elegante con Logo) ──
  Response _handleRoot(Request req) {
    final html = '''<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Agente de Impresión · SoftwareRestaurante</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    :root {
      --accent: #004AAD;
      --accent-light: #E8F0FC;
      --bg: #FFFFFF;
      --surface: #F7F7F5;
      --text: #37352F;
      --text-secondary: #7C7B77;
      --border: #EDEDEB;
      --success: #0F9B58;
      --success-bg: #E6F6EE;
      --radius: 8px;
    }
    html, body {
      height: 100%;
      background-color: #F8F9FA;
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
      color: var(--text);
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
    }
    .card {
      background: #FFFFFF;
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 56px 40px;
      max-width: 480px;
      width: 100%;
      text-align: center;
      box-shadow: 0 4px 20px rgba(0, 0, 0, 0.05);
    }
    .logo-wrap {
      width: 88px;
      height: 88px;
      background: var(--accent-light);
      border-radius: 20px;
      display: flex;
      align-items: center;
      justify-content: center;
      margin: 0 auto 24px;
    }
    .logo-wrap svg {
      width: 56px;
      height: 56px;
    }
    .badge {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      background: var(--accent);
      color: white;
      font-size: 11px;
      font-weight: 600;
      letter-spacing: 0.5px;
      padding: 4px 12px;
      border-radius: 100px;
      margin-bottom: 20px;
    }
    h1 {
      font-size: 22px;
      font-weight: 700;
      color: var(--text);
      margin-bottom: 8px;
      letter-spacing: -0.3px;
    }
    .brand {
      font-size: 14px;
      color: var(--accent);
      font-weight: 600;
      margin-bottom: 20px;
    }
    .status-box {
      background: var(--success-bg);
      border: 1px solid rgba(15, 155, 88, 0.15);
      border-radius: var(--radius);
      padding: 16px 20px;
      margin: 24px 0;
    }
    .status-box p {
      color: var(--success);
      font-weight: 600;
      font-size: 14px;
      margin-bottom: 4px;
    }
    .status-box small {
      color: var(--text-secondary);
      font-size: 12px;
    }
    .sub {
      font-size: 13px;
      color: var(--text-secondary);
      line-height: 1.6;
    }
    .divider {
      height: 1px;
      background: var(--border);
      margin: 24px 0;
    }
    .footer {
      font-size: 11px;
      color: var(--text-secondary);
    }
    .footer strong { color: var(--accent); }
    @keyframes fadeInUp {
      from { opacity: 0; transform: translateY(20px); }
      to { opacity: 1; transform: translateY(0); }
    }
    @keyframes popIn {
      0% { opacity: 0; transform: scale(0.9); }
      50% { transform: scale(1.05); }
      100% { opacity: 1; transform: scale(1); }
    }
    .card {
      animation: fadeInUp 0.6s cubic-bezier(0.16, 1, 0.3, 1) forwards;
    }
    .logo-wrap {
      animation: popIn 0.8s cubic-bezier(0.16, 1, 0.3, 1) 0.2s forwards;
      opacity: 0;
    }
    .badge {
      animation: fadeInUp 0.5s cubic-bezier(0.16, 1, 0.3, 1) 0.4s forwards;
      opacity: 0;
    }
    h1, .brand {
      animation: fadeInUp 0.5s cubic-bezier(0.16, 1, 0.3, 1) 0.5s forwards;
      opacity: 0;
    }
    .status-box, .sub, .divider, .footer {
      animation: fadeInUp 0.5s cubic-bezier(0.16, 1, 0.3, 1) 0.6s forwards;
      opacity: 0;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo-wrap">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 375 374.999991"><path fill="#004aad" d="M 321.675781 288.375 C 327 293.265625 329.925781 298.53125 329.925781 304.015625 C 329.925781 329.746094 266.15625 350.605469 187.496094 350.605469 C 108.835938 350.605469 45.070312 329.746094 45.070312 304.015625 C 45.070312 298.527344 47.996094 293.265625 53.320312 288.375 C 35.996094 296.796875 25.875 306.941406 25.875 317.859375 C 25.875 347.0625 98.234375 370.734375 187.5 370.734375 C 276.765625 370.734375 349.125 347.0625 349.125 317.859375 C 349.125 306.941406 339.003906 296.800781 321.675781 288.375 Z M 321.675781 288.375 "/><path fill="#004aad" d="M 201.851562 221.105469 C 201.886719 220.691406 201.910156 220.269531 201.910156 219.847656 C 201.910156 211.734375 195.457031 205.15625 187.496094 205.15625 C 179.535156 205.15625 173.082031 211.734375 173.082031 219.847656 C 173.082031 220.265625 173.109375 220.691406 173.144531 221.105469 C 113.484375 226.429688 67.207031 277.613281 67.207031 314.964844 C 67.207031 314.964844 98.882812 336.636719 187.496094 336.636719 C 276.113281 336.636719 307.785156 314.964844 307.785156 314.964844 C 307.789062 277.613281 261.515625 226.429688 201.851562 221.105469 Z M 268.859375 289.617188 C 262.917969 297.105469 244.070312 292.046875 226.75 278.320312 C 209.4375 264.585938 200.210938 247.382812 206.15625 239.890625 C 212.09375 232.402344 230.945312 237.460938 248.261719 251.195312 C 265.574219 264.921875 274.800781 282.125 268.859375 289.617188 Z M 268.859375 289.617188 "/><path fill="#004aad" d="M 154.214844 155.800781 C 151.429688 152.070312 148.984375 148.398438 146.828125 144.71875 C 87.347656 160.734375 41.753906 210.960938 32.574219 272.917969 C 41.359375 267.503906 51.828125 262.566406 63.738281 258.253906 C 77.683594 212.578125 116.273438 177.578125 163.933594 168.765625 C 161.09375 164.488281 157.75 160.289062 154.214844 155.800781 Z M 154.214844 155.800781 "/><path fill="#004aad" d="M 213.675781 141.558594 C 211.761719 150.394531 209.367188 159.6875 205.527344 167.863281 C 255.722656 174.894531 296.773438 210.824219 311.261719 258.253906 C 323.171875 262.566406 333.640625 267.503906 342.425781 272.917969 C 332.511719 206.015625 280.140625 152.792969 213.675781 141.558594 Z M 213.675781 141.558594 "/><path fill="#004aad" d="M 174.148438 198.136719 C 176.023438 192.644531 176.261719 188.839844 177.164062 182.777344 C 179.273438 165.578125 171.320312 154.371094 162 140.53125 C 149.484375 120.878906 145.003906 103.257812 145.972656 79.878906 C 147.90625 49.414062 170.875 24.878906 191.550781 4.269531 C 184.394531 20.636719 180.699219 38.753906 179.570312 56.519531 C 178.3125 76.324219 185.75 95.652344 190.140625 114.796875 C 193.777344 129.804688 198.707031 148.46875 195.171875 164.046875 C 192.339844 176.609375 179.015625 185.703125 174.148438 198.136719 Z M 174.148438 198.136719 "/><path fill="#004aad" d="M 194.953125 32.917969 C 192.082031 44.308594 189.617188 57.824219 191.742188 69.328125 C 195.296875 87.234375 205.910156 105.46875 204.367188 124.097656 C 211.03125 112.269531 218.570312 92.1875 217.449219 79.117188 C 215.59375 60.976562 196.582031 55.210938 194.953125 32.917969 Z M 194.953125 32.917969 "/></svg>
    </div>

    <div class="badge">
      CONEXIÓN ACTIVA
    </div>

    <h1>Agente de Impresión Local</h1>
    <div class="brand">SoftwareRestaurante</div>

    <div class="status-box">
      <p>Certificado SSL configurado con éxito</p>
      <small>Puerto activo: $port · IP: ${getLocalIp()}</small>
    </div>

    <p class="sub">
      Ya puedes cerrar esta pestaña y regresar al sistema de ventas.<br>
      El navegador ahora reconoce esta conexión como segura.
    </p>

    <div class="divider"></div>
    <div class="footer">
      Hecho por <strong>SoftwareRestaurante</strong> &mdash; Agente v2.0
    </div>
  </div>
</body>
</html>''';

    return Response.ok(
      html,
      headers: {
        'Content-Type': 'text/html; charset=utf-8',
        'Access-Control-Allow-Origin': '*',
      },
    );
  }

  // ── GET /info ─────────────────────────────────────────────────────
  Future<Response> _handleInfo(Request req) async {
    try {
      final printers = await printerService.getAllPrinters();
      final devicesList = printers
          .map((p) => {
                'name': p.name,
                'type': p.type.name,
                'address': p.displayAddress,
              })
          .toList();

      final settings = SettingsService.instance;

      // El token solo se expone a peticiones locales (loopback).
      // Así el flujo de "Detectar y Vincular" del mismo equipo sigue funcionando
      // sin filtrar la clave a otros equipos de la red.
      final connInfo =
          req.context['shelf.io.connection_info'] as HttpConnectionInfo?;
      final remote = connInfo?.remoteAddress.address ?? '';
      final isLoopback =
          remote == '127.0.0.1' || remote == '::1' || remote == 'localhost';

      final body = jsonEncode({
        'status': 'success',
        'device_name': settings.deviceName.isNotEmpty
            ? settings.deviceName
            : (Platform.isAndroid ? 'Terminal Sunmi / Android' : 'PC Caja'),
        'device_uuid': settings.deviceUuid,
        if (isLoopback) 'token': settings.apiToken,
        'printers': devicesList,
        'platform': Platform.operatingSystem,
        'version': '2.0.0',
      });
      return Response.ok(body, headers: _corsJson);
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'status': 'error', 'message': e.toString()}),
        headers: _corsJson,
      );
    }
  }

  // ── POST /sync_token ───────────────────────────────────────────────
  Future<Response> _handleSyncToken(Request req) async {
    try {
      final body = await req.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final token = data['token'] as String?;
      final serverUrl = data['server_url'] as String?;
      final deviceName = data['device_name'] as String?;

      final settings = SettingsService.instance;
      if (token != null && token.isNotEmpty) {
        await settings.setApiToken(token);
      }
      if (serverUrl != null && serverUrl.isNotEmpty) {
        await settings.setOdooUrl(serverUrl);
      }
      if (deviceName != null && deviceName.isNotEmpty) {
        await settings.setDeviceName(deviceName);
      }

      // Notificar a la UI (HomePage) para que actualice los campos y se conecte en tiempo real
      SettingsService.onExternalSettingsSync.add({
        if (serverUrl != null && serverUrl.isNotEmpty) 'odoo_url': serverUrl,
        if (token != null && token.isNotEmpty) 'api_token': token,
        if (deviceName != null && deviceName.isNotEmpty)
          'device_name': deviceName,
      });

      return Response.ok(
        jsonEncode({
          'status': 'success',
          'message': 'Configuración sincronizada con éxito en la App.'
        }),
        headers: _corsJson,
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'status': 'error', 'message': e.toString()}),
        headers: _corsJson,
      );
    }
  }

  // ── GET /get_printers ─────────────────────────────────────────────
  Future<Response> _handleGetPrinters(Request req) async {
    try {
      final printers = await printerService.getAllPrinters();

      // Mapeamos las impresoras reales, de red y dispositivos IoT
      final devicesList = printers
          .map((p) => {
                'name': p.name,
                'type': p.type.name, // "local", "network", "bluetooth", etc.
                'address': p.displayAddress,
              })
          .toList();

      final body = jsonEncode({
        'status': 'success',
        'printers': devicesList,
      });
      return Response.ok(body, headers: _corsJson);
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'status': 'error', 'message': e.toString()}),
        headers: _corsJson,
      );
    }
  }

  // ── POST /print_raw ───────────────────────────────────────────────
  Future<Response> _handlePrintRaw(Request req) async {
    try {
      final body = await req.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final printerName = data['printer_name'] as String?;
      final rawB64 = data['raw_data'] as String?;
      final rawType = data['raw_type'] as String?;
      final openCashbox = data['open_cashbox'] == true;
      final jobUuid = data['job_uuid'] as String? ??
          'job-${DateTime.now().microsecondsSinceEpoch}';

      if (printerName == null || rawB64 == null) {
        return Response.badRequest(
          body: jsonEncode({
            'status': 'error',
            'message': 'printer_name y raw_data requeridos'
          }),
          headers: _corsJson,
        );
      }

      Uint8List bytes = base64Decode(rawB64);
      String finalRawType = rawType ?? 'raw';

      // Buscar impresora por nombre en la lista completa (nativas, red, IoT)
      final printers = await printerService.getAllPrinters();
      PrinterModel? target;
      try {
        target = printers.firstWhere(
          (p) =>
              p.name.toLowerCase().contains(printerName.toLowerCase()) ||
              printerName.toLowerCase().contains(p.name.toLowerCase()),
        );
      } catch (_) {
        // Si no se encuentra, crear una local con el nombre dado
        target = PrinterModel(name: printerName, type: PrinterType.local);
      }

      // Verificar que no sea un error JSON de Odoo
      if (bytes.length < 500 &&
          String.fromCharCodes(bytes.take(50)).contains('Odoo Server Error')) {
        return Response.internalServerError(
          body: jsonEncode(
              {'status': 'error', 'message': 'Error del Sistema interceptado'}),
          headers: _corsJson,
        );
      }

      // Encolar asíncronamente en el procesador de colas persistente con Mutex locks
      final job = await PrintQueueService.instance.enqueue(
        uuid: jobUuid,
        printerName: target.name,
        bytes: bytes.toList(),
        rawType: finalRawType,
        openCashbox: openCashbox,
      );

      if (job.status == 'completed') {
        return Response.ok(
          jsonEncode({
            'status': 'success',
            'message': 'Trabajo completado previamente (Idempotente)',
            'job_uuid': job.uuid,
          }),
          headers: _corsJson,
        );
      } else {
        return Response.ok(
          jsonEncode({
            'status': 'queued',
            'message': 'Trabajo recibido y encolado',
            'job_uuid': job.uuid,
            'job_status': job.status,
            'error': job.errorMessage,
          }),
          headers: _corsJson,
        );
      }
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'status': 'error', 'message': e.toString()}),
        headers: _corsJson,
      );
    }
  }

  // ── GET /print_job/status/<uuid> ──────────────────────────────────
  Future<Response> _handlePrintJobStatus(Request req, String uuid) async {
    try {
      final job = PrintQueueService.instance.getJob(uuid);
      if (job == null) {
        return Response.notFound(
          jsonEncode({'status': 'error', 'message': 'Trabajo no encontrado'}),
          headers: _corsJson,
        );
      }
      return Response.ok(
        jsonEncode({
          'status': 'success',
          'job_uuid': job.uuid,
          'job_status': job.status,
          'retry_count': job.retryCount,
          'error': job.errorMessage,
        }),
        headers: _corsJson,
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'status': 'error', 'message': e.toString()}),
        headers: _corsJson,
      );
    }
  }

  // ── CORS headers ──────────────────────────────────────────────────
  static const Map<String, String> _corsJson = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers':
        'Origin, Content-Type, Accept, Authorization, X-Requested-With, Access-Control-Request-Private-Network, Access-Control-Request-Headers',
    'Access-Control-Allow-Private-Network': 'true',
  };
}
