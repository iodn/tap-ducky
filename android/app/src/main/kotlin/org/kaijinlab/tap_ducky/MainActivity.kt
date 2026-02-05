package org.kaijinlab.tap_ducky

import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
  private val mainHandler = Handler(Looper.getMainLooper())
  private val executor = Executors.newSingleThreadExecutor()
  private val scriptExecutor = Executors.newSingleThreadExecutor()
  private lateinit var logBus: LogBus
  private lateinit var manager: GadgetManager

  @Volatile
  private var keysSink: EventChannel.EventSink? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    val backend = BackendProvider.get(applicationContext)
    logBus = backend.logBus
    manager = backend.manager

    val messenger = flutterEngine.dartExecutor.binaryMessenger

    MethodChannel(messenger, CHANNEL_METHODS).setMethodCallHandler { call, result ->
      when (call.method) {
        "checkRoot" -> runAsync(result) { manager.checkRoot() }
        "checkSupport" -> runAsync(result) { manager.checkSupport() }
        "listUdcs" -> runAsync(result) { manager.listUdcs() }
        "getStatus" -> runAsync(result) { manager.getStatusSnapshot().toMap() }
        "getDiagnostics" -> runAsync(result) { manager.getDiagnostics() }
        "setKeyboardLayout" -> {
          val layout = (call.arguments as? Int) ?: KeyboardLayout.LAYOUT_US
          runAsync(result) { manager.setKeyboardLayout(layout); null }
        }
        "getKeyboardLayouts" -> runAsync(result) {
          KeyboardLayout.getAllLayouts().map { (id, name) -> mapOf("id" to id, "name" to name) }
        }
        "activateProfile" -> {
          val map = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
          runAsync(result) { manager.activate(map); null }
        }
        "deactivate" -> runAsync(result) { manager.deactivate(); null }
        "panicStop" -> runAsync(result) { manager.panicStop(); null }
        "retryOpenHidWriters" -> runAsync(result) { manager.retryOpenHidWriters(); null }
        "cancelExecution" -> {
          val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
          val executionId = args["executionId"]?.toString()
          runAsync(result) { manager.cancelExecution(executionId); null }
        }
        "testMouseMove" -> {
          val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
          val dx = (args["dx"] as? Number)?.toInt() ?: 8
          val dy = (args["dy"] as? Number)?.toInt() ?: 0
          val wheel = (args["wheel"] as? Number)?.toInt() ?: 0
          val buttons = (args["buttons"] as? Number)?.toInt() ?: 0
          runAsync(result) { manager.testMouseMove(dx, dy, wheel, buttons); null }
        }
        "testKeyboardKey" -> {
          val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
          val key = args["label"]?.toString() ?: args["key"]?.toString() ?: "A"
          runAsync(result) { manager.testKeyboardKey(key); null }
        }
        "testCtrlAltDel" -> runAsync(result) { manager.testCtrlAltDel(); null }
        "executeDuckyScript" -> {
          val args = call.arguments as? Map<*, *>
          val script = args?.get("script")?.toString() ?: ""
          val multiplier = (args?.get("delayMultiplier") as? Number)?.toDouble() ?: 1.0
          val executionId = args?.get("executionId")?.toString()

          scriptExecutor.execute {
            try {
              manager.executeDuckyScript(script, multiplier, executionId)
            } catch (t: Throwable) {
              try {
                logBus.logError("exec", "executeDuckyScript failed: ${t.message ?: t.toString()}")
              } catch (_: Throwable) {
              }
            }
          }

          result.success(null)
        }
        "estimateDuckyScriptDuration" -> {
          val args = call.arguments as? Map<*, *>
          val script = args?.get("script")?.toString() ?: ""
          val multiplier = (args?.get("delayMultiplier") as? Number)?.toDouble() ?: 1.0
          runAsync(result) { manager.estimateDuckyScriptDurationMs(script, multiplier) }
        }
        "getTypingSpeedFactor", "getTypingSpeed" -> runAsync(result) { manager.getTypingSpeedFactor() }
        "setTypingSpeedFactor", "setTypingSpeed" -> {
          val factor = when (val a = call.arguments) {
            is Number -> a.toDouble()
            is Map<*, *> -> (a["factor"] as? Number)?.toDouble()
              ?: (a["value"] as? Number)?.toDouble()
              ?: (a["speed"] as? Number)?.toDouble()
              ?: 1.0
            else -> 1.0
          }
          runAsync(result) { manager.setTypingSpeedFactor(factor) }
        }
        "setHidGraceWindowMs", "setHidGraceWindow" -> {
          val ms = when (val a = call.arguments) {
            is Number -> a.toLong()
            is Map<*, *> -> (a["ms"] as? Number)?.toLong()
              ?: (a["value"] as? Number)?.toLong()
              ?: (a["graceMs"] as? Number)?.toLong()
              ?: 1500L
            else -> 1500L
          }
          runAsync(result) { manager.setHidGraceWindowMs(ms) }
        }
        "setUnicodeFallbackMode", "setUnicodeFallback" -> {
          val mode = when (val a = call.arguments) {
            is String -> a
            is Map<*, *> -> (a["mode"] as? String)
              ?: (a["value"] as? String)
              ?: (a["fallback"] as? String)
              ?: "warn"
            else -> "warn"
          }
          runAsync(result) { manager.setUnicodeFallbackMode(mode) }
        }
        "setRiskyFastMode" -> {
          val enabled = when (val a = call.arguments) {
            is Boolean -> a
            is Map<*, *> -> (a["enabled"] as? Boolean) ?: (a["value"] as? Boolean) ?: false
            else -> false
          }
          runAsync(result) { manager.setRiskyFastMode(enabled); null }
        }
        "setDialShortcutConfig" -> {
          val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
          val enabled = (args["enabled"] as? Boolean) ?: false
          val mode = args["mode"]?.toString() ?: "last"
          val script = args["script"]?.toString()
          val name = args["name"]?.toString()
          runAsync(result) { manager.setDialShortcutConfig(enabled, mode, script, name); null }
        }
        "setDialShortcutBindings" -> {
          val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
          val raw = args["bindings"]
          val list = if (raw is List<*>) raw.filterIsInstance<Map<*, *>>() else emptyList()
          runAsync(result) { manager.setDialShortcutBindings(list); null }
        }
        else -> result.notImplemented()
      }
    }

    EventChannel(messenger, CHANNEL_LOGS).setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        logBus.attach(events)
      }

      override fun onCancel(arguments: Any?) {
        logBus.detach()
      }
    })

    EventChannel(messenger, CHANNEL_STATUS).setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        manager.attachStatusSink(events)
      }

      override fun onCancel(arguments: Any?) {
        manager.detachStatusSink()
      }
    })

    EventChannel(messenger, CHANNEL_EXEC).setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        manager.attachExecSink(events)
      }

      override fun onCancel(arguments: Any?) {
        manager.detachExecSink()
      }
    })

    EventChannel(messenger, CHANNEL_KEYS).setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        keysSink = events
      }

      override fun onCancel(arguments: Any?) {
        keysSink = null
      }
    })
  }

  override fun dispatchKeyEvent(event: KeyEvent): Boolean {
    val kc = event.keyCode
    if (kc == KeyEvent.KEYCODE_VOLUME_UP || kc == KeyEvent.KEYCODE_VOLUME_DOWN || kc == KeyEvent.KEYCODE_POWER) {
      val sink = keysSink
      if (sink != null) {
        try {
          sink.success(
            mapOf(
              "keyCode" to kc,
              "action" to event.action,
              "eventTime" to event.eventTime,
              "downTime" to event.downTime,
              "repeatCount" to event.repeatCount,
              "isLongPress" to event.isLongPress,
              "metaState" to event.metaState
            )
          )
        } catch (_: Throwable) {
        }
      }
    }
    return super.dispatchKeyEvent(event)
  }

  private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
    executor.execute {
      try {
        val value = block()
        mainHandler.post { result.success(value) }
      } catch (t: Throwable) {
        mainHandler.post { result.error("ERR", t.message, null) }
      }
    }
  }

  companion object {
    private const val CHANNEL_METHODS = "org.kaijinlab.tap_ducky/gadget"
    private const val CHANNEL_LOGS = "org.kaijinlab.tap_ducky/gadget_logs"
    private const val CHANNEL_STATUS = "org.kaijinlab.tap_ducky/gadget_status"
    private const val CHANNEL_EXEC = "org.kaijinlab.tap_ducky/gadget_exec"
    private const val CHANNEL_KEYS = "org.kaijinlab.tap_ducky/hardware_keys"
  }
}
