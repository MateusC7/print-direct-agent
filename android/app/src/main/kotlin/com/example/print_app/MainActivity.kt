package com.example.print_app

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.UUID
import com.sunmi.peripheral.printer.InnerPrinterCallback
import com.sunmi.peripheral.printer.InnerPrinterManager
import com.sunmi.peripheral.printer.SunmiPrinterService
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat


class MainActivity : FlutterActivity() {

    private val BT_CHANNEL = "com.softwarerestaurante.print/bluetooth"
    private val SUNMI_CHANNEL = "com.softwarerestaurante.print/sunmi"
    private val SUNMI_SERVICE_PACKAGE = "woyou.aidlservice.jiuiv5"

    // UUID estándar para SPP (Serial Port Profile)
    private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    @Volatile
    private var sunmiPrinterService: SunmiPrinterService? = null

    private val innerPrinterCallback = object : InnerPrinterCallback() {
        override fun onConnected(service: SunmiPrinterService?) {
            sunmiPrinterService = service
        }
        override fun onDisconnected() {
            sunmiPrinterService = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            InnerPrinterManager.getInstance().bindService(this, innerPrinterCallback)
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        // Iniciar el Foreground Service para mantener vivo el servidor HTTP local
        try {
            val serviceIntent = Intent(this, PrintServerService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            if (sunmiPrinterService != null) {
                InnerPrinterManager.getInstance().unBindService(this, innerPrinterCallback)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Canal Bluetooth ─────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPairedDevices" -> getPairedDevices(result)
                    "discoverDevices" -> discoverBluetoothDevices(result)
                    "printSystem" -> {
                        val data = call.argument<ByteArray>("data")
                        val jobName = call.argument<String>("jobName") ?: "Print Job"
                        if (data == null) {
                            result.error("INVALID_ARGS", "data es requerido", null)
                        } else {
                            printSystemPdf(data, jobName, result)
                        }
                    }
                    "printRaw" -> {
                        val address = call.argument<String>("address")
                        val data = call.argument<ByteArray>("data")
                        if (address == null || data == null) {
                            result.error("INVALID_ARGS", "address y data son requeridos", null)
                        } else {
                            printViaBluetooth(address, data, result)
                        }
                    }
                    "openPrintSettings" -> {
                        openPrintSettings(result)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Canal Sunmi ─────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SUNMI_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(isSunmiDevice())
                    "printRaw" -> {
                        val data = call.argument<ByteArray>("data")
                        if (data == null) {
                            result.error("INVALID_ARGS", "data es requerido", null)
                        } else {
                            printViaSunmi(data, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── Listar dispositivos BT enlazados (Filtrado para Impresoras y evitar Parlantes/Auriculares) ──
    private fun getPairedDevices(result: MethodChannel.Result) {
        if (!hasBluetoothPermission()) {
            result.error("NO_PERMISSION", "Permiso Bluetooth no concedido", null)
            return
        }
        try {
            val adapter = BluetoothAdapter.getDefaultAdapter()
            if (adapter == null) {
                result.success(emptyList<Map<String, String>>())
                return
            }
            val devices: List<Map<String, String>> = adapter.bondedDevices
                .filter { device ->
                    val btClass = device.bluetoothClass
                    val major = btClass?.majorDeviceClass ?: 0
                    val name = (device.name ?: "").lowercase()
                    
                    // Descartar Audio/Video (parlantes, auriculares, radio auto) a menos que su nombre indique impresora
                    val isAudio = major == android.bluetooth.BluetoothClass.Device.Major.AUDIO_VIDEO
                    val isPhone = major == android.bluetooth.BluetoothClass.Device.Major.PHONE
                    val isWearable = major == android.bluetooth.BluetoothClass.Device.Major.WEARABLE
                    val isToy = major == android.bluetooth.BluetoothClass.Device.Major.TOY
                    
                    val isPrinterKeyword = name.contains("print") || 
                                           name.contains("pos") || 
                                           name.contains("receipt") || 
                                           name.contains("mpt") || 
                                           name.contains("rpp") || 
                                           name.contains("bt-") || 
                                           name.contains("thermal") ||
                                           name.contains("epson") ||
                                           name.contains("bixolon") ||
                                           name.contains("star") ||
                                           name.contains("xprinter") ||
                                           name.contains("zijiang") ||
                                           name.contains("inner")
                    
                    if ((isAudio || isPhone || isWearable || isToy) && !isPrinterKeyword) {
                        false
                    } else {
                        true
                    }
                }
                .map { device ->
                    mapOf(
                        "name" to (device.name ?: "Unknown"),
                        "address" to device.address
                    )
                }
            result.success(devices)
        } catch (e: Exception) {
            result.error("BT_ERROR", e.message, null)
        }
    }

    // ── Conexión RFCOMM con respaldo inseguro (sin emparejar, sin diálogos) ──
    // Primero el socket seguro (impresoras ya emparejadas); si falla, el
    // inseguro, que funciona con la mayoría de impresoras térmicas sin PIN y
    // no dispara el diálogo de emparejamiento de Android.
    private fun connectRfcomm(device: BluetoothDevice): BluetoothSocket {
        var lastError: Exception? = null
        val attempts = listOf(true, false, true)
        for (secure in attempts) {
            var socket: BluetoothSocket? = null
            try {
                socket = if (secure) {
                    device.createRfcommSocketToServiceRecord(SPP_UUID)
                } else {
                    device.createInsecureRfcommSocketToServiceRecord(SPP_UUID)
                }
                socket.connect()
                return socket
            } catch (e: Exception) {
                lastError = e
                try { socket?.close() } catch (_: Exception) {}
                try { Thread.sleep(300) } catch (_: InterruptedException) {}
            }
        }
        throw lastError ?: java.io.IOException("No se pudo conectar por Bluetooth")
    }

    // ── Descubrir impresoras Bluetooth cercanas (emparejadas o no) ──────
    private fun hasBluetoothScanPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(
                this, android.Manifest.permission.BLUETOOTH_SCAN
            ) == PackageManager.PERMISSION_GRANTED && hasBluetoothPermission()
        } else {
            ContextCompat.checkSelfPermission(
                this, android.Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun looksLikePrinter(device: BluetoothDevice): Boolean {
        val major = device.bluetoothClass?.majorDeviceClass ?: 0
        val name = (device.name ?: "").lowercase()
        val nonPrinterClass = major == android.bluetooth.BluetoothClass.Device.Major.AUDIO_VIDEO ||
            major == android.bluetooth.BluetoothClass.Device.Major.PHONE ||
            major == android.bluetooth.BluetoothClass.Device.Major.WEARABLE ||
            major == android.bluetooth.BluetoothClass.Device.Major.TOY
        val keywords = listOf(
            "print", "pos", "receipt", "mpt", "rpp", "bt-", "thermal", "epson",
            "bixolon", "star", "xprinter", "zijiang", "inner", "mtp", "sunmi", "tm-"
        )
        return !nonPrinterClass || keywords.any { name.contains(it) }
    }

    private fun discoverBluetoothDevices(result: MethodChannel.Result) {
        if (!hasBluetoothScanPermission()) {
            result.error("NO_PERMISSION", "Permiso de búsqueda Bluetooth no concedido", null)
            return
        }
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter == null || !adapter.isEnabled) {
            result.success(emptyList<Map<String, Any>>())
            return
        }
        val found = LinkedHashMap<String, Map<String, Any>>()
        fun remember(device: BluetoothDevice) {
            if (!looksLikePrinter(device)) return
            found[device.address] = mapOf(
                "name" to (device.name ?: "Unknown"),
                "address" to device.address,
                "bonded" to (device.bondState == BluetoothDevice.BOND_BONDED)
            )
        }
        try {
            adapter.bondedDevices.forEach { remember(it) }
        } catch (_: SecurityException) {}

        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        var finished = false
        lateinit var receiver: android.content.BroadcastReceiver
        fun finish() {
            if (finished) return
            finished = true
            try { adapter.cancelDiscovery() } catch (_: SecurityException) {}
            try { unregisterReceiver(receiver) } catch (_: Exception) {}
            result.success(found.values.toList())
        }
        receiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: android.content.Context?, intent: Intent?) {
                when (intent?.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        val device: BluetoothDevice? =
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                            } else {
                                @Suppress("DEPRECATION")
                                intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                            }
                        if (device != null) remember(device)
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> finish()
                }
            }
        }
        try {
            val filter = android.content.IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_FOUND)
                addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            }
            registerReceiver(receiver, filter)
            if (!adapter.startDiscovery()) {
                finish()
                return
            }
            handler.postDelayed({ finish() }, 12000)
        } catch (e: Exception) {
            finish()
        }
    }

    // ── Imprimir via Bluetooth SPP ──────────────────────────────────────
    private fun printViaBluetooth(address: String, data: ByteArray, result: MethodChannel.Result) {
        if (!hasBluetoothPermission()) {
            result.error("NO_PERMISSION", "Permiso Bluetooth no concedido", null)
            return
        }
        Thread {
            var socket: BluetoothSocket? = null
            try {
                val adapter = BluetoothAdapter.getDefaultAdapter()
                val device: BluetoothDevice = adapter.getRemoteDevice(address)
                adapter.cancelDiscovery()
                socket = connectRfcomm(device)
                val outputStream: OutputStream = socket.outputStream
                outputStream.write(data)
                outputStream.flush()
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("BT_PRINT_ERROR", e.message, null)
                }
            } finally {
                try { socket?.close() } catch (_: Exception) {}
            }
        }.start()
    }

    // ── Detección de hardware Sunmi ─────────────────────────────────────
    private fun isSunmiDevice(): Boolean {
        val brand = Build.BRAND?.lowercase() ?: ""
        val manufacturer = Build.MANUFACTURER?.lowercase() ?: ""
        if (brand.contains("sunmi") || manufacturer.contains("sunmi")) return true
        // Rebranded or OEM terminals still ship Sunmi's inner printer service
        return try {
            packageManager.getPackageInfo(SUNMI_SERVICE_PACKAGE, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    // ── Impresión Sunmi (via inner printer service) ─────────────────────
    private fun printViaSunmi(data: ByteArray, result: MethodChannel.Result) {
        Thread {
            var service = sunmiPrinterService
            if (service == null) {
                // Servicio desconectado: reconectar bajo demanda y esperar hasta 3 s
                try {
                    InnerPrinterManager.getInstance().bindService(this, innerPrinterCallback)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
                var waited = 0
                while (sunmiPrinterService == null && waited < 3000) {
                    Thread.sleep(200)
                    waited += 200
                }
                service = sunmiPrinterService
            }
            if (service == null) {
                runOnUiThread {
                    result.error("SUNMI_NOT_CONNECTED", "El servicio de impresora Sunmi no está conectado o disponible", null)
                }
                return@Thread
            }
            try {
                // Trozos de 64 KB: evita TransactionTooLargeException en el binder con tickets largos
                val chunkSize = 64 * 1024
                var offset = 0
                while (offset < data.size) {
                    val end = minOf(offset + chunkSize, data.size)
                    service.sendRAWData(data.copyOfRange(offset, end), null)
                    offset = end
                }
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("SUNMI_PRINT_ERROR", e.message, null)
                }
            }
        }.start()
    }


    // ── Verificar permisos ──────────────────────────────────────────────
    private fun hasBluetoothPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(
                this, android.Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(
                this, android.Manifest.permission.BLUETOOTH
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun openPrintSettings(result: MethodChannel.Result) {
        try {
            val intent = android.content.Intent(android.provider.Settings.ACTION_PRINT_SETTINGS)
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("INTENT_ERROR", e.message, null)
        }
    }

    private fun printSystemPdf(pdfBytes: ByteArray, jobName: String, result: MethodChannel.Result) {
        try {
            val printManager = getSystemService(android.content.Context.PRINT_SERVICE) as android.print.PrintManager
            val printAdapter = object : android.print.PrintDocumentAdapter() {
                override fun onWrite(
                    pages: Array<out android.print.PageRange>?,
                    destination: android.os.ParcelFileDescriptor?,
                    cancellationSignal: android.os.CancellationSignal?,
                    callback: WriteResultCallback?
                ) {
                    try {
                        val output = java.io.FileOutputStream(destination?.fileDescriptor)
                        output.write(pdfBytes)
                        output.flush()
                        output.close()
                        callback?.onWriteFinished(arrayOf(android.print.PageRange.ALL_PAGES))
                    } catch (e: Exception) {
                        callback?.onWriteFailed(e.message)
                    }
                }

                override fun onLayout(
                    oldAttributes: android.print.PrintAttributes?,
                    newAttributes: android.print.PrintAttributes?,
                    cancellationSignal: android.os.CancellationSignal?,
                    callback: LayoutResultCallback?,
                    extras: Bundle?
                ) {
                    if (cancellationSignal?.isCanceled == true) {
                        callback?.onLayoutCancelled()
                        return
                    }
                    val info = android.print.PrintDocumentInfo.Builder(jobName)
                        .setContentType(android.print.PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                        .build()
                    callback?.onLayoutFinished(info, true)
                }
            }
            runOnUiThread {
                printManager.print(jobName, printAdapter, android.print.PrintAttributes.Builder().build())
                result.success(true)
            }
        } catch (e: Exception) {
            result.error("PRINT_SYSTEM_ERROR", e.message, null)
        }
    }
}

// ── Foreground Service para mantener el Servidor HTTP levantado ──
class PrintServerService : Service() {
    private val CHANNEL_ID = "com.softwarerestaurante.print.foreground"
    private val NOTIFICATION_ID = 9182
    private var wakeLock: android.os.PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        try {
            val powerManager = getSystemService(android.content.Context.POWER_SERVICE) as? android.os.PowerManager
            wakeLock = powerManager?.newWakeLock(
                android.os.PowerManager.PARTIAL_WAKE_LOCK,
                "SoftwareRestaurante:PrintServerWakeLock"
            )
            wakeLock?.acquire()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Software Restaurant")
            .setContentText("Agente de impresion local activo")
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()

        startForeground(NOTIFICATION_ID, notification)
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Canal Agente de Impresión",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
        }
    }
}
