package com.example.townpass

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private var codefestAI: CodefestAI? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        codefestAI = CodefestAI(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"codefest/on_device_ai").setMethodCallHandler(codefestAI)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CodefestAI.permissionCode) codefestAI?.permissionResult(grantResults.firstOrNull() == android.content.pm.PackageManager.PERMISSION_GRANTED)
    }
    override fun onStop() { codefestAI?.background(); super.onStop() }
    override fun onDestroy() { codefestAI?.destroy(); super.onDestroy() }
}
