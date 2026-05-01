package ph.gov.bfp.firecheck

import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "ph.gov.bfp.firecheck/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAvailableBytes" -> {
                        val stat = StatFs(Environment.getDataDirectory().path)
                        result.success(stat.availableBlocksLong * stat.blockSizeLong)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
