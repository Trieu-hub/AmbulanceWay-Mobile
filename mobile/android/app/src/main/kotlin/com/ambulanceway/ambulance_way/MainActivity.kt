package com.ambulanceway.ambulance_way

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // App cần biết máy ảo hay điện thoại thật: 10.0.2.2 chỉ trỏ tới máy tính khi chạy trong máy ảo,
        // còn trên điện thoại thật phải nhập IP Wi-Fi của máy tính (xem lib/core/device_info.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ambulance_way/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "isEmulator") result.success(isEmulator()) else result.notImplemented()
            }
    }

    /** Dấu hiệu của máy ảo Android Studio (goldfish/ranchu, ảnh hệ thống sdk_gphone...). */
    private fun isEmulator(): Boolean =
        Build.FINGERPRINT.startsWith("generic") ||
            Build.FINGERPRINT.contains("emulator") ||
            Build.HARDWARE == "goldfish" ||
            Build.HARDWARE == "ranchu" ||
            Build.MODEL.contains("Emulator") ||
            Build.MODEL.contains("Android SDK built for") ||
            Build.PRODUCT.contains("sdk_gphone") ||
            Build.PRODUCT == "sdk" ||
            Build.PRODUCT == "google_sdk" ||
            Build.PRODUCT.contains("emulator")
}
