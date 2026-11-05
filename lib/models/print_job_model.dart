import 'dart:convert';
import 'dart:typed_data';

/// Representa un trabajo de impresión en la cola persistente del Agente.
class PrintJobModel {
  final String uuid;
  final String printerName;
  final Uint8List bytes;
  final String rawType;
  final bool openCashbox;
  final DateTime timestamp;
  String status; // 'pending' | 'printing' | 'completed' | 'failed'
  String? errorMessage;
  int retryCount;

  PrintJobModel({
    required this.uuid,
    required this.printerName,
    required this.bytes,
    required this.rawType,
    this.openCashbox = false,
    required this.timestamp,
    this.status = 'pending',
    this.errorMessage,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'printerName': printerName,
        'bytes': base64Encode(bytes),
        'rawType': rawType,
        'openCashbox': openCashbox,
        'timestamp': timestamp.toIso8601String(),
        'status': status,
        'errorMessage': errorMessage,
        'retryCount': retryCount,
      };

  factory PrintJobModel.fromJson(Map<String, dynamic> json) {
    return PrintJobModel(
      uuid: json['uuid'] as String,
      printerName: json['printerName'] as String,
      bytes: base64Decode(json['bytes'] as String),
      rawType: json['rawType'] as String,
      openCashbox: json['openCashbox'] as bool? ?? false,
      timestamp: DateTime.parse(json['timestamp'] as String),
      status: json['status'] as String,
      errorMessage: json['errorMessage'] as String?,
      retryCount: json['retryCount'] as int? ?? 0,
    );
  }

  PrintJobModel copyWith({
    String? status,
    String? errorMessage,
    int? retryCount,
    bool? openCashbox,
  }) {
    return PrintJobModel(
      uuid: uuid,
      printerName: printerName,
      bytes: bytes,
      rawType: rawType,
      openCashbox: openCashbox ?? this.openCashbox,
      timestamp: timestamp,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}
