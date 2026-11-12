package com.gphotos.gphotos

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Matrix
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import android.media.ExifInterface
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * FlutterFragmentActivity is required by local_auth (biometric prompt).
 * Channel "gphotos/region":
 *  - info(path)  -> {width, height} after EXIF rotation
 *  - region(path, left, top, right, bottom, sample) -> JPEG bytes of that region (display coordinates)
 *  - secure(on)  -> FLAG_SECURE (vault content hidden from Recents / screenshots)
 */
class MainActivity : FlutterFragmentActivity() {
    private val pool = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())
    private val decoders = object : LinkedHashMap<String, BitmapRegionDecoder>(4, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, BitmapRegionDecoder>?): Boolean {
            if (size > 3) {
                eldest?.value?.recycle()
                return true
            }
            return false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gphotos/region").setMethodCallHandler { call, result ->
            when (call.method) {
                "secure" -> {
                    if (call.argument<Boolean>("on") == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                "info" -> {
                    val path = call.argument<String>("path")!!
                    pool.execute {
                        try {
                            val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                            BitmapFactory.decodeFile(path, o)
                            if (o.outWidth <= 0) throw IllegalStateException("cannot read")
                            val rot = rotation(path)
                            val swap = rot == 90 || rot == 270
                            val w = if (swap) o.outHeight else o.outWidth
                            val h = if (swap) o.outWidth else o.outHeight
                            main.post { result.success(mapOf("width" to w, "height" to h)) }
                        } catch (e: Exception) {
                            main.post { result.error("info", e.message, null) }
                        }
                    }
                }
                "region" -> {
                    val path = call.argument<String>("path")!!
                    val l = call.argument<Int>("left")!!
                    val t = call.argument<Int>("top")!!
                    val r = call.argument<Int>("right")!!
                    val b = call.argument<Int>("bottom")!!
                    val sample = call.argument<Int>("sample") ?: 1
                    pool.execute {
                        try {
                            val bytes = decodeRegion(path, l, t, r, b, sample)
                            main.post { result.success(bytes) }
                        } catch (e: Exception) {
                            main.post { result.error("region", e.message, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun rotation(path: String): Int = try {
        when (ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90
            ExifInterface.ORIENTATION_ROTATE_180 -> 180
            ExifInterface.ORIENTATION_ROTATE_270 -> 270
            else -> 0
        }
    } catch (e: Exception) {
        0
    }

    @Synchronized
    private fun decoder(path: String): BitmapRegionDecoder {
        decoders[path]?.let { return it }
        val d = if (Build.VERSION.SDK_INT >= 31) BitmapRegionDecoder.newInstance(path) else @Suppress("DEPRECATION") BitmapRegionDecoder.newInstance(path, false)
        decoders[path] = d!!
        return d
    }

    private fun decodeRegion(path: String, l: Int, t: Int, r: Int, b: Int, sample: Int): ByteArray {
        val d = decoder(path)
        val rw = d.width
        val rh = d.height
        val rot = rotation(path)
        // display rect -> raw (unrotated) rect
        val raw = when (rot) {
            90 -> Rect(t, rh - r, b, rh - l)
            180 -> Rect(rw - r, rh - b, rw - l, rh - t)
            270 -> Rect(rw - b, l, rw - t, r)
            else -> Rect(l, t, r, b)
        }
        raw.intersect(0, 0, rw, rh)
        val opts = BitmapFactory.Options().apply { inSampleSize = sample.coerceAtLeast(1) }
        val bmp: Bitmap = synchronized(d) { d.decodeRegion(raw, opts) } ?: throw IllegalStateException("decode failed")
        val out = if (rot != 0) {
            val m = Matrix().apply { postRotate(rot.toFloat()) }
            val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
            if (rotated != bmp) bmp.recycle()
            rotated
        } else bmp
        val bos = ByteArrayOutputStream()
        out.compress(Bitmap.CompressFormat.JPEG, 92, bos)
        out.recycle()
        return bos.toByteArray()
    }

    override fun onDestroy() {
        synchronized(this) {
            decoders.values.forEach { it.recycle() }
            decoders.clear()
        }
        pool.shutdown()
        super.onDestroy()
    }
}
