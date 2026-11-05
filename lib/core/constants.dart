/// Constantes globales de la aplicación.
class AppConstants {
  AppConstants._();

  static const String appName = 'Software Restaurante';
  static const String appVersion = '2.0.0';
  static const String madeBy = 'Software Restaurante';

  // ── Puerto por defecto ────────────────────────────────
  static const int defaultPort = 18069;
  static const String defaultHost = '0.0.0.0';

  // ── Endpoints ─────────────────────────────────────────
  static const String endpointRoot = '/';
  static const String endpointPrinters = '/get_printers';
  static const String endpointPrintRaw = '/print_raw';

  // ── Certs ─────────────────────────────────────────────
  static const String certFileName = 'localhost.pem';
  static const String keyFileName = 'localhost-key.pem';

  // ── Nombres de assets mkcert ──────────────────────────
  static const String mkcertAssetWindows = 'assets/mkcert/mkcert.exe';
  static const String mkcertAssetMacos   = 'assets/mkcert/mkcert-darwin';
  static const String mkcertAssetLinux   = 'assets/mkcert/mkcert-linux';

  // ── URLs de descarga mkcert (si no está en assets) ───
  static const String mkcertReleaseBase =
      'https://github.com/FiloSottile/mkcert/releases/latest/download';
  static const String mkcertDownloadWindows =
      '$mkcertReleaseBase/mkcert-v1.4.4-windows-amd64.exe';
  static const String mkcertDownloadMacosAmd64 =
      '$mkcertReleaseBase/mkcert-v1.4.4-darwin-amd64';
  static const String mkcertDownloadMacosArm64 =
      '$mkcertReleaseBase/mkcert-v1.4.4-darwin-arm64';
  static const String mkcertDownloadMacos = mkcertDownloadMacosAmd64;
  static const String mkcertDownloadLinux =
      '$mkcertReleaseBase/mkcert-v1.4.4-linux-amd64';

  // ── SharedPreferences keys ────────────────────────────
  static const String prefPort = 'server_port';
  static const String prefTheme = 'theme_mode'; // 'light' | 'dark'
  static const String prefLang = 'language'; // 'es' | 'en' | 'pt'
  static const String prefOdooUrl = 'odoo_url';
  static const String prefAutoLaunchPos = 'auto_launch_pos';
  static const String prefDefaultPrinterId = 'default_printer_id';
  static const String prefOdooUsername = 'odoo_username';
  static const String prefOdooPassword = 'odoo_password';
  static const String prefRememberCredentials = 'remember_credentials';
  static const String prefOdooProtocol = 'odoo_protocol';
  static const String prefApiToken = 'api_token';
  static const String prefScaleProtocol = 'scale_protocol';
  static const String prefDeviceUuid = 'device_uuid';
  static const String prefDeviceName = 'device_name';
  static const String prefAutoStartWindows = 'auto_start_windows';
  static const String prefAutoStartSystem = 'auto_start_system';
  static const String prefEnableCloudRelay = 'enable_cloud_relay';
  static const String prefEnableOdooHeartbeat = 'enable_odoo_heartbeat';
  static const String prefEnableAck = 'enable_print_ack';
  static const String prefEnableSignature = 'enable_print_signature';
  static const String prefPollIntervalMs = 'poll_interval_ms';

  // ── Tipos de impresión raw ────────────────────────────
  static const String rawTypeZpl = 'zpl';
  static const String rawTypePdf = 'pdf';
  static const String rawTypeText = 'text';
  static const String rawTypeImageCut = 'image_cut';
  static const String rawTypeCashbox = 'cashbox';

  // ── Android ───────────────────────────────────────────
  static const String androidBtChannel = 'com.softwarerestaurante.print/bluetooth';
  static const String androidSunmiChannel = 'com.softwarerestaurante.print/sunmi';
  static const int defaultNetworkPort = 9100;
}
