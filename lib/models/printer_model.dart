/// Tipos de dispositivos disponibles en el agente (impresoras e IoT).
enum PrinterType { local, network, bluetooth, sunmi, scale, scanner, display }

/// Modelo de impresora multiplataforma.
class PrinterModel {
  final String name;
  final PrinterType type;
  final String? address; // IP para tipo network, MAC para BT
  final int? port;       // Puerto TCP para network (default 9100)
  final bool isSunmi;

  const PrinterModel({
    required this.name,
    required this.type,
    this.address,
    this.port,
    this.isSunmi = false,
  });

  /// Identificador único para RadioButton
  String get id => switch (type) {
        PrinterType.network => '$name@${address ?? ''}:${port ?? 9100}',
        PrinterType.bluetooth => '$name@BT:${address ?? ''}',
        PrinterType.sunmi => '$name@SUNMI',
        PrinterType.scale => '$name@SCALE:${address ?? ''}',
        PrinterType.scanner => '$name@SCANNER:${address ?? ''}',
        PrinterType.display => '$name@DISPLAY:${address ?? ''}',
        PrinterType.local => name,
      };

  String get displayAddress => switch (type) {
        PrinterType.network => '${address ?? ''}:${port ?? 9100}',
        PrinterType.bluetooth => address ?? '',
        PrinterType.sunmi => 'Sunmi Built-in',
        PrinterType.scale => address ?? 'usb/com',
        PrinterType.scanner => address ?? 'usb/com',
        PrinterType.display => address ?? 'usb/com',
        PrinterType.local => '',
      };

  PrinterModel copyWith({
    String? name,
    PrinterType? type,
    String? address,
    int? port,
    bool? isSunmi,
  }) =>
      PrinterModel(
        name: name ?? this.name,
        type: type ?? this.type,
        address: address ?? this.address,
        port: port ?? this.port,
        isSunmi: isSunmi ?? this.isSunmi,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type.name,
        'address': address,
        'port': port,
        'isSunmi': isSunmi,
      };

  factory PrinterModel.fromJson(Map<String, dynamic> json) => PrinterModel(
        name: json['name'] as String,
        type: PrinterType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => PrinterType.local,
        ),
        address: json['address'] as String?,
        port: json['port'] as int?,
        isSunmi: json['isSunmi'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PrinterModel && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PrinterModel(name: $name, type: ${type.name}, addr: $displayAddress)';
}
