package org.kaijinlab.tap_ducky

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class LogBus(
    private val maxLines: Int = 2000,
) {
    private val main = Handler(Looper.getMainLooper())
    private val sdf = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    private val lines = ArrayDeque<String>(maxLines)

    @Volatile
    private var sink: EventChannel.EventSink? = null

    fun attach(events: EventChannel.EventSink) {
        sink = events
        val snapshot = synchronized(lines) { lines.toList() }
        main.post {
            snapshot.forEach { events.success(it) }
        }
    }

    fun detach() {
        sink = null
    }

    fun log(tag: String, msg: String) {
        val line = "${sdf.format(Date())} [$tag] $msg"
        synchronized(lines) {
            lines.addLast(line)
            while (lines.size > maxLines) {
                lines.removeFirst()
            }
        }
        main.post {
            sink?.success(line)
        }
    }

    fun logError(tag: String, msg: String) {
        log("$tag/ERR", msg)
    }

    fun sleep(ms: Long) {
        try {
            Thread.sleep(ms)
        } catch (_: InterruptedException) {
        }
    }
}
