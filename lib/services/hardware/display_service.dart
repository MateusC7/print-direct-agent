import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Servicio para emitir los datos del carrito (pantalla de cliente) a pantallas externas.
/// Odoo envía HTML o comandos JSON. Los almacenamos aquí y luego el servidor
/// HTTP los puede servir a una página web local (ej. http://localhost:18069/display)
class DisplayService extends ChangeNotifier {
  static final DisplayService instance = DisplayService._internal();
  DisplayService._internal();

  String _currentHtml = '<html><body style="background:#000;color:#fff;display:flex;align-items:center;justify-content:center;height:100vh;font-family:sans-serif;"><h1>Esperando orden...</h1></body></html>';
  Map<String, dynamic> _lastCartData = {};

  String get currentHtml => _currentHtml;
  Map<String, dynamic> get lastCartData => _lastCartData;

  /// Actualiza la pantalla. Odoo puede enviar HTML directo o JSON con info del carrito.
  void updateDisplay(String html, {Map<String, dynamic>? data}) {
    if (html.isNotEmpty) {
      _currentHtml = html;
    }
    if (data != null) {
      _lastCartData = data;
    }
    notifyListeners();
  }
}
