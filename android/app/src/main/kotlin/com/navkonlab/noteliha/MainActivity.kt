package com.navkonlab.noteliha

import android.content.ClipboardManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.noteliha/clipboard"
        ).setMethodCallHandler { call, result ->
            if (call.method == "getHtmlText") {
                val cm = getSystemService(Context.CLIPBOARD_SERVICE)
                            as? ClipboardManager
                val html = cm?.primaryClip
                             ?.takeIf { it.itemCount > 0 }
                             ?.getItemAt(0)
                             ?.htmlText  // null when only plain text is present
                result.success(html)
            } else {
                result.notImplemented()
            }
        }
    }
}
