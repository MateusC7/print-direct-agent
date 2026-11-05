import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Utilidades de firma para autenticar peticiones al Servidor de Odoo.
///
/// El servidor valida (cuando `print_direct.require_signature` está activo):
///   X-Timestamp: epoch en segundos
///   X-Signature: hex(HMAC_SHA256(token, "timestamp.cuerpo_json_exacto"))
class RelayCrypto {
  RelayCrypto._();

  /// Firma un cuerpo JSON crudo usando el token como clave.
  static String signBody(String token, String rawBody, String timestamp) {
    final message = '$timestamp.$rawBody';
    final hmac = Hmac(sha256, utf8.encode(token));
    return hmac.convert(utf8.encode(message)).toString();
  }
}
