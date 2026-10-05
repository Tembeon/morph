package dev.tembeon.morph_example

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // The device audits write their reports to the app's external files
        // directory, which only exists once the app has asked for it.
        getExternalFilesDir(null)
        super.onCreate(savedInstanceState)
    }
}
