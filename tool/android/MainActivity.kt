package br.com.gazire.gazmap

import android.annotation.SuppressLint
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.Uri
import android.provider.OpenableColumns
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Funções nativas do GAZMAP (POWERED BY GAZIRE):
 * SMS automático (SOS), lanterna, vibração e bipe de resgate.
 */
class MainActivity : FlutterActivity() {
    private var tone: ToneGenerator? = null
    private var pickResult: MethodChannel.Result? = null
    private val pickCode = 4242
    private var headingSink: EventChannel.EventSink? = null
    private var headingListener: SensorEventListener? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Bússola: direção para onde o celular aponta (graus, norte magnético).
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "gazmap/heading")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    headingSink = sink
                    startHeading()
                }

                override fun onCancel(args: Any?) {
                    stopHeading()
                    headingSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gazmap/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendSms" -> {
                        val phone = call.argument<String>("phone")
                        val text = call.argument<String>("text")
                        if (phone.isNullOrBlank() || text.isNullOrBlank()) {
                            result.error("ARGS", "phone/text vazios", null)
                        } else {
                            sendSms(phone, text, result)
                        }
                    }
                    "torch" -> {
                        result.success(torch(call.argument<Boolean>("on") ?: false))
                    }
                    "vibrate" -> {
                        vibrate(call.argument<List<Int>>("pattern") ?: listOf(0, 400))
                        result.success(true)
                    }
                    "beep" -> {
                        beep(call.argument<Int>("ms") ?: 200)
                        result.success(true)
                    }
                    "pickFiles" -> {
                        if (pickResult != null) {
                            result.error("BUSY", "seleção em andamento", null)
                        } else {
                            pickResult = result
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "*/*"
                                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                            }
                            startActivityForResult(intent, pickCode)
                        }
                    }
                    "declination" -> {
                        val lat = call.argument<Double>("lat") ?: 0.0
                        val lon = call.argument<Double>("lon") ?: 0.0
                        val alt = call.argument<Double>("alt") ?: 0.0
                        val f = GeomagneticField(lat.toFloat(), lon.toFloat(), alt.toFloat(), System.currentTimeMillis())
                        result.success(f.declination.toDouble())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    private fun sendSms(phone: String, text: String, result: MethodChannel.Result) {
        try {
            val sms: SmsManager = if (Build.VERSION.SDK_INT >= 31) {
                getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            val parts = sms.divideMessage(text)
            val action = "br.com.gazire.gazmap.SMS_SENT." + System.nanoTime()
            var pending = parts.size
            var ok = true
            var done = false
            val handler = Handler(Looper.getMainLooper())

            val receiver = object : BroadcastReceiver() {
                override fun onReceive(c: Context?, i: Intent?) {
                    if (resultCode != Activity.RESULT_OK) ok = false
                    pending--
                    if (pending <= 0 && !done) {
                        done = true
                        try { unregisterReceiver(this) } catch (_: Exception) {}
                        result.success(ok)
                    }
                }
            }
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(receiver, IntentFilter(action), Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(receiver, IntentFilter(action))
            }

            val intents = ArrayList<PendingIntent>()
            for (k in parts.indices) {
                val intent = Intent(action).setPackage(packageName)
                intents.add(
                    PendingIntent.getBroadcast(
                        this, (System.nanoTime() % 100000).toInt() + k, intent,
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    )
                )
            }
            sms.sendMultipartTextMessage(phone, null, parts, intents, null)

            // Sem confirmação em 45 s: considera falha (fica na fila para nova tentativa).
            handler.postDelayed({
                if (!done) {
                    done = true
                    try { unregisterReceiver(receiver) } catch (_: Exception) {}
                    result.success(false)
                }
            }, 45000)
        } catch (e: Exception) {
            result.error("SMS", e.message, null)
        }
    }

    private fun startHeading() {
        val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val sensor = sm.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR) ?: return
        val r = FloatArray(9)
        val o = FloatArray(3)
        var last = -1000.0
        var lastAt = 0L
        val l = object : SensorEventListener {
            override fun onSensorChanged(e: SensorEvent) {
                SensorManager.getRotationMatrixFromVector(r, e.values)
                SensorManager.getOrientation(r, o)
                var deg = Math.toDegrees(o[0].toDouble())
                if (deg < 0) deg += 360.0
                val now = System.currentTimeMillis()
                var diff = Math.abs(deg - last)
                if (diff > 180) diff = 360 - diff
                if (diff >= 1.0 && now - lastAt >= 60) {
                    last = deg
                    lastAt = now
                    headingSink?.success(deg)
                }
            }

            override fun onAccuracyChanged(s: Sensor?, a: Int) {}
        }
        headingListener = l
        sm.registerListener(l, sensor, SensorManager.SENSOR_DELAY_UI)
    }

    private fun stopHeading() {
        val l = headingListener ?: return
        (getSystemService(Context.SENSOR_SERVICE) as SensorManager).unregisterListener(l)
        headingListener = null
    }

    private fun torch(on: Boolean): Boolean {
        return try {
            val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val id = cm.cameraIdList.firstOrNull {
                cm.getCameraCharacteristics(it)
                    .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            } ?: return false
            cm.setTorchMode(id, on)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun vibrate(pattern: List<Int>) {
        try {
            val v: Vibrator = if (Build.VERSION.SDK_INT >= 31) {
                getSystemService(VibratorManager::class.java).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            val arr = pattern.map { it.toLong() }.toLongArray()
            if (Build.VERSION.SDK_INT >= 26) {
                v.vibrate(VibrationEffect.createWaveform(arr, -1))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(arr, -1)
            }
        } catch (_: Exception) {}
    }

    private fun beep(ms: Int) {
        try {
            if (tone == null) tone = ToneGenerator(AudioManager.STREAM_ALARM, 100)
            tone?.startTone(ToneGenerator.TONE_DTMF_D, ms)
        } catch (_: Exception) {}
    }

    @Deprecated("API do FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickCode) return
        val res = pickResult ?: return
        pickResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            res.success(emptyList<Map<String, Any>>())
            return
        }
        val uris = ArrayList<Uri>()
        val clip = data.clipData
        if (clip != null) {
            for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
        } else {
            data.data?.let { uris.add(it) }
        }
        val out = ArrayList<Map<String, Any>>()
        for (uri in uris) {
            try {
                var name = "arquivo"
                contentResolver.query(uri, null, null, null, null)?.use { c ->
                    val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0 && c.moveToFirst()) name = c.getString(idx)
                }
                val bytes = contentResolver.openInputStream(uri)?.use {
                    it.readBytes()
                } ?: continue
                if (bytes.size > 40_000_000) continue
                out.add(mapOf("name" to name, "bytes" to bytes))
            } catch (_: Exception) {}
        }
        res.success(out)
    }

    override fun onDestroy() {
        stopHeading()
        tone?.release()
        tone = null
        super.onDestroy()
    }
}
