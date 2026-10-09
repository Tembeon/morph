package dev.tembeon.morph_example

import android.os.Build
import android.os.Bundle
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // The device audits write their reports to the app's external files
        // directory, which only exists once the app has asked for it.
        getExternalFilesDir(null)
        super.onCreate(savedInstanceState)
        // Benchmark launches pass morph-max-refresh to run at the panel's
        // highest refresh rate: without a touch the system may hold an app
        // that votes for no rate at 60 Hz on a 120 Hz panel.
        if (intent?.getBooleanExtra("morph-max-refresh", false) == true) {
            preferRefreshRate(Float.MAX_VALUE)
        }
        // Benchmark launches may pass morph-frame-rate (for example 60) to
        // ask for the display mode closest to that rate instead, and vote
        // it for the Flutter surface.
        val rate = intent?.getFloatExtra("morph-frame-rate", 0f) ?: 0f
        if (rate > 0f) preferRefreshRate(rate)
    }

    private fun preferRefreshRate(target: Float) {
        @Suppress("DEPRECATION")
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            windowManager.defaultDisplay
        } ?: return
        val current = display.mode
        val best = display.supportedModes
            .filter {
                it.physicalWidth == current.physicalWidth &&
                    it.physicalHeight == current.physicalHeight
            }
            .minByOrNull { Math.abs(it.refreshRate - target) } ?: return
        val attributes = window.attributes
        attributes.preferredDisplayModeId = best.modeId
        attributes.preferredRefreshRate = best.refreshRate
        window.attributes = attributes
        maxRefreshRate = best.refreshRate
    }

    private var maxRefreshRate = 0f

    override fun onPostResume() {
        super.onPostResume()
        if (maxRefreshRate > 0 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            findSurfaceView(window.decorView)?.let { view ->
                voteFrameRate(view.holder)
                view.holder.addCallback(object : SurfaceHolder.Callback {
                    override fun surfaceCreated(holder: SurfaceHolder) =
                        voteFrameRate(holder)

                    override fun surfaceChanged(
                        holder: SurfaceHolder,
                        format: Int,
                        width: Int,
                        height: Int,
                    ) = voteFrameRate(holder)

                    override fun surfaceDestroyed(holder: SurfaceHolder) {}
                })
            }
        }
    }

    private fun voteFrameRate(holder: SurfaceHolder) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val surface = holder.surface ?: return
        if (!surface.isValid) return
        surface.setFrameRate(
            maxRefreshRate,
            Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
        )
    }

    private fun findSurfaceView(view: View): SurfaceView? {
        if (view is SurfaceView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                findSurfaceView(view.getChildAt(i))?.let { return it }
            }
        }
        return null
    }
}
