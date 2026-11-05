import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../printer/printer_service.dart';
import '../hardware/scale_service.dart';
import '../hardware/scanner_service.dart';
import '../hardware/display_service.dart';
import '../settings_service.dart';
import '../../models/xml_escpos_compiler.dart';

/// Manejador que emula el comportamiento de una Caja IoT (IoT Box) nativa de Odoo.
/// Responde a las llamadas JSON-RPC que Odoo hace internamente.
class IotBoxHandler {
  final PrinterService printerService;

  IotBoxHandler({required this.printerService});

  Router get router {
    final r = Router();

    // Endpoints básicos de Odoo IoT
    r.get('/hw_proxy/hello', _handleHello);
    r.post('/hw_proxy/handshake', _handleHandshake);
    r.post('/hw_proxy/status_json', _handleStatusJson);
    
    // Impresión ESC/POS y Cajón (Nativo Odoo)
    r.post('/hw_proxy/print_xml_receipt', _handlePrintXmlReceipt);
    r.post('/hw_proxy/default_printer_action', _handlePrintXmlReceipt); // Odoo 18 suele usar este

    // TODO: Básculas y Lectores de Códigos de Barras
    r.post('/hw_proxy/scale_read', _handleScaleRead);
    r.post('/hw_proxy/scanner', _handleScanner);
    r.post('/hw_proxy/customer_facing_display', _handleCustomerFacingDisplay);
    
    // Vista web del display para pantallas inalámbricas
    r.get('/display', _handleDisplayView);

    return r;
  }

  // ── Respuestas JSON-RPC ──
  Response _rpcResponse(Map<String, dynamic> body, {dynamic result}) {
    final id = body['id'];
    return Response.ok(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
      }),
      headers: {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
    );
  }

  // 1. Ping de estado
  Response _handleHello(Request req) {
    return Response.ok('ping', headers: {'Access-Control-Allow-Origin': '*'});
  }

  // 2. Handshake
  Future<Response> _handleHandshake(Request req) async {
    final bodyStr = await req.readAsString();
    final body = jsonDecode(bodyStr);
    return _rpcResponse(body, result: true);
  }

  // 3. Estado de dispositivos conectados
  Future<Response> _handleStatusJson(Request req) async {
    final bodyStr = await req.readAsString();
    final body = jsonDecode(bodyStr);
    
    final printers = await printerService.getAllPrinters();
    final hasPrinters = printers.isNotEmpty;

    String printerStatus = 'connected';
    List<String> messages = [];
    if (hasPrinters) {
      final status = await printerService.getPrinterStatus(printers.first.name);
      if (status == 'paper_out') {
        printerStatus = 'error';
        messages.add('Impresora ${printers.first.name}: Sin papel.');
      } else if (status == 'offline') {
        printerStatus = 'disconnected';
        messages.add('Impresora ${printers.first.name}: Desconectada.');
      } else if (status == 'paused') {
        printerStatus = 'error';
        messages.add('Impresora ${printers.first.name}: Pausada.');
      }
    } else {
      printerStatus = 'disconnected';
      messages.add('No se detectaron impresoras locales.');
    }

    final drivers = {
      'escpos': {
        'status': printerStatus,
        'messages': messages,
      },
      'scale': {
        'status': ScaleService.instance.isConnected ? 'connected' : 'disconnected',
        'messages': [],
      },
      'display': {
        'status': 'connected',
        'messages': [],
      },
      'scanner': {
        'status': ScannerService.instance.isConnected ? 'connected' : 'disconnected',
        'messages': [],
      }
    };

    final status = {
      'status': 'connected',
      'messages': [],
      'drivers': drivers,
    };
    return _rpcResponse(body, result: status);
  }

  // 4. Impresión Nativa (Odoo envía recibo ESC/POS o comando xml)
  Future<Response> _handlePrintXmlReceipt(Request req) async {
    final bodyStr = await req.readAsString();
    final body = jsonDecode(bodyStr);
    final params = body['params'] ?? {};
    
    final receipt = params['receipt'] as String?;
    
    print("[IOT EMULATOR] El Sistema solicita imprimir un ticket XML nativo.");
    
    if (receipt != null && receipt.isNotEmpty) {
      try {
        final bytes = XmlEscposCompiler.compile(receipt);
        final printers = await printerService.getAllPrinters();
        if (printers.isNotEmpty) {
          // Usamos la primera impresora conectada como predeterminada para el emulador nativo
          final target = printers.first;
          await printerService.printRaw(
            printer: target,
            bytes: bytes,
            rawType: 'raw',
          );
          print("[IOT EMULATOR] Ticket XML impreso con éxito en: ${target.name}");
        } else {
          print("[IOT EMULATOR] Advertencia: No hay impresoras disponibles para imprimir XML.");
        }
      } catch (e) {
        print("[IOT EMULATOR] Error procesando XML receipt: $e");
      }
    }
    
    return _rpcResponse(body, result: true);
  }

  // 5. Lectura de Báscula (Real)
  Future<Response> _handleScaleRead(Request req) async {
    final bodyStr = await req.readAsString();
    final body = jsonDecode(bodyStr);
    
    // Obtenemos el peso real del ScaleService
    final weight = ScaleService.instance.currentWeight;
    final unit = ScaleService.instance.unit;
    
    return _rpcResponse(body, result: {
      'weight': weight,
      'unit': unit,
      'info': 'ok'
    });
  }

  // 6. Lector de Códigos (Real)
  Future<Response> _handleScanner(Request req) async {
    final bodyStr = await req.readAsString();
    final body = jsonDecode(bodyStr);
    
    // Consumir el último código escaneado (si lo hay)
    final barcode = ScannerService.instance.consumeBarcode();
    
    return _rpcResponse(body, result: barcode);
  }

  // 7. Pantalla de Cliente (Customer Facing Display)
  Future<Response> _handleCustomerFacingDisplay(Request req) async {
    final bodyStr = await req.readAsString();
    final body = jsonDecode(bodyStr);
    final params = body['params'] ?? {};
    final action = params['action'] ?? '';
    
    if (action == 'open') {
      final port = SettingsService.instance.port;
      final uri = Uri.parse('http://localhost:$port/display');
      try {
        launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        print("[IOT EMULATOR] Error launching customer display: $e");
      }
      return _rpcResponse(body, result: {'status': 'ok'});
    }
    
    if (action == 'get') {
      final currentHtml = DisplayService.instance.currentHtml;
      return _rpcResponse(body, result: {
        'data': {
          'html': currentHtml,
          'rendered_html': currentHtml,
        }
      });
    }
    
    final html = params['html'] ?? '';
    if (html.isNotEmpty) {
      DisplayService.instance.updateDisplay(html);
    }
    
    return _rpcResponse(body, result: {'status': 'ok'});
  }

  // 8. Visualizador Web del Display
  Response _handleDisplayView(Request req) {
    // Retorna el HTML actual guardado para que un SmartTV/Tablet lo muestre
    final html = DisplayService.instance.currentHtml;
    
    // Si queremos que se auto-actualice, podríamos inyectar un script de auto-reload,
    // o el frontend (pantalla) podría hacer long-polling. Por simplicidad, agregamos un meta refresh
    // para que la pantalla inalámbrica recargue el contenido cada 2 segundos.
    final autoRefreshHtml = html.replaceFirst(
      '<head>', 
      '<head><meta http-equiv="refresh" content="2">'
    );

    return Response.ok(
      autoRefreshHtml.contains('<head>') ? autoRefreshHtml : html,
      headers: {'Content-Type': 'text/html; charset=utf-8'},
    );
  }
}
