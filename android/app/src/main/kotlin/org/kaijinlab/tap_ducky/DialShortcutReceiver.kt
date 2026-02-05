package org.kaijinlab.tap_ducky

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject
class DialShortcutReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != "android.provider.Telephony.SECRET_CODE") return
    val host = intent.data?.host ?: return
    val prefs = Prefs(context)
    val bindings = prefs.getDialShortcutBindings()
    val binding = bindings.firstOrNull { it.code == host && it.enabled } ?: return
    val script = when (binding.mode) {
      "payload" -> binding.script
      else -> prefs.lastExecutedScript
    }
    if (script.isNullOrBlank()) return

    val delayMultiplier = readDelayMultiplier(context)
    val svcIntent = Intent(context, GadgetForegroundService::class.java).apply {
      action = GadgetForegroundService.ACTION_EXECUTE_SCRIPT
      putExtra(GadgetForegroundService.EXTRA_SCRIPT, script)
      putExtra(GadgetForegroundService.EXTRA_DELAY_MULTIPLIER, delayMultiplier)
      putExtra(GadgetForegroundService.EXTRA_TITLE, "Dial shortcut running")
    }

    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
      context.startForegroundService(svcIntent)
    } else {
      context.startService(svcIntent)
    }
  }

  private fun readDelayMultiplier(context: Context): Double {
    return try {
      val sp = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
      val raw = sp.getString("flutter.tapducky.settings.v1", null) ?: return 1.0
      val json = JSONObject(raw)
      val value = if (json.has("delayMultiplier")) json.optDouble("delayMultiplier", 1.0) else 1.0
      if (value.isFinite() && value > 0) value else 1.0
    } catch (_: Throwable) {
      1.0
    }
  }

  companion object {
  }
}
