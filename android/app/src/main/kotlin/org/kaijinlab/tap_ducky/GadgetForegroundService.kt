package org.kaijinlab.tap_ducky

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import org.json.JSONObject
import java.util.concurrent.Executors

/**
 * Foreground service to keep the USB gadget active while the app is backgrounded.
 *
 * This service intentionally avoids referencing app resources (R.string / R.drawable)
 * to prevent build breaks when resource merging changes. UI strings remain in Flutter.
 */
class GadgetForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIF_ID, buildNotification(DEFAULT_TITLE))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: DEFAULT_TITLE
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIF_ID, buildNotification(title))
        if (intent?.action == ACTION_EXECUTE_SCRIPT) {
            val script = intent.getStringExtra(EXTRA_SCRIPT) ?: ""
            val delayMultiplier = intent.getDoubleExtra(EXTRA_DELAY_MULTIPLIER, 1.0)
            if (script.isNotBlank()) {
                execExecutor.execute {
                    try {
                        val prefs = Prefs(applicationContext)
                        val backend = BackendProvider.get(applicationContext)
                        ensureArmed(backend.manager, prefs)
                        backend.manager.executeDuckyScript(
                            script = script,
                            delayMultiplier = delayMultiplier,
                            executionId = "dial_${System.currentTimeMillis()}"
                        )
                    } catch (t: Throwable) {
                        BackendProvider.get(applicationContext).logBus
                            .logError("dial", "Dial shortcut failed: ${t.message ?: t}")
                    }
                }
            }
        }
        return START_STICKY
    }

    private fun ensureArmed(manager: GadgetManager, prefs: Prefs) {
        val status = manager.getStatusSnapshot()
        if (status.isActive) return

        val roleType = prefs.activeRoleType?.takeIf { it.isNotBlank() }
            ?: readLastProfileType()
            ?: "composite"

        val (vid, pid) = readDefaultVidPid()
        val profile = mapOf(
            "id" to "${roleType}_${System.currentTimeMillis()}",
            "name" to "TapDucky ${roleType.replaceFirstChar { it.uppercase() }}",
            "roleType" to roleType,
            "vendorId" to vid,
            "productId" to pid,
            "manufacturer" to "KaijinLab",
            "product" to "TapDucky",
        )
        manager.activate(profile)
    }

    private fun readDefaultVidPid(): Pair<Int, Int> {
        return try {
            val sp = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = sp.getString("flutter.tapducky.advanced_settings.v1", null) ?: return 0x1d6b to 0x0104
            val json = JSONObject(raw)
            val vidStr = json.optString("defaultVid", "0x1D6B")
            val pidStr = json.optString("defaultPid", "0x0104")
            parseHexOrDec(vidStr, 0x1d6b) to parseHexOrDec(pidStr, 0x0104)
        } catch (_: Throwable) {
            0x1d6b to 0x0104
        }
    }

    private fun readLastProfileType(): String? {
        return try {
            val sp = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = sp.getString("flutter.tapducky.settings.v1", null) ?: return null
            val json = JSONObject(raw)
            json.optString("lastProfileType", "").takeIf { it.isNotBlank() }
        } catch (_: Throwable) {
            null
        }
    }

    private fun parseHexOrDec(raw: String, fallback: Int): Int {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return fallback
        return try {
            if (trimmed.startsWith("0x", ignoreCase = true)) trimmed.substring(2).toInt(16) else trimmed.toInt()
        } catch (_: Throwable) {
            fallback
        }
    }

    private fun buildNotification(title: String): Notification {
        val channelId = ensureChannel()

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = if (launchIntent != null) {
            PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
            )
        } else {
            null
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText("USB gadget is active. Tap to open TapDucky.")
            .setOngoing(true)
            .setOnlyAlertOnce(true)

        if (pendingIntent != null) {
            builder.setContentIntent(pendingIntent)
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
            builder.build()
        } else {
            @Suppress("DEPRECATION")
            builder.notification
        }
    }

    private fun ensureChannel(): String {
        val channelId = CHANNEL_ID
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val existing = manager.getNotificationChannel(channelId)
            if (existing == null) {
                val channel = NotificationChannel(
                    channelId,
                    "GadgetFS",
                    NotificationManager.IMPORTANCE_LOW
                )
                channel.description = "Keeps the USB gadget active while running in the background."
                manager.createNotificationChannel(channel)
            }
        }
        return channelId
    }

    companion object {
        const val NOTIF_ID = 1001
        const val EXTRA_TITLE = "title"
        const val ACTION_EXECUTE_SCRIPT = "org.kaijinlab.tap_ducky.EXECUTE_SCRIPT"
        const val EXTRA_SCRIPT = "script"
        const val EXTRA_DELAY_MULTIPLIER = "delayMultiplier"

        private const val CHANNEL_ID = "gadgetfs_active"
        private const val DEFAULT_TITLE = "USB gadget active"
        private val execExecutor = Executors.newSingleThreadExecutor()
    }
}
