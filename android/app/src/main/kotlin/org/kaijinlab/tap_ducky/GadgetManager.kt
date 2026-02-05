package org.kaijinlab.tap_ducky

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import java.util.ArrayList
import java.util.LinkedHashMap
import java.util.Locale
import java.util.concurrent.atomic.AtomicReference
import java.text.Normalizer
import kotlin.math.min
import kotlin.math.roundToInt

class GadgetManager(
  private val context: Context,
  private val log: LogBus,
) {
  private val main = Handler(Looper.getMainLooper())
  private val root = RootShell(log)
  private val prefs = Prefs(context)
  private val udcNameRegex = Regex("^[A-Za-z0-9._-]+$")
  private val HID_KBD_FD = 3
  private val HID_MOUSE_FD = 4

  private val baseKeyDownHoldUs: Int = 4000
  private val baseInterKeyDelayUs: Int = 600
  private var minKeyDownHoldUs: Int = 1500
  private var minInterKeyDelayUs: Int = 180
  private val maxKeyDownHoldUs: Int = 150000
  private val maxInterKeyDelayUs: Int = 50000
  private val minTypingSpeedFactor: Double = 0.1
  private val maxTypingSpeedFactor: Double = 10.0

  @Volatile private var typingSpeedFactor: Double = normalizeTypingSpeedFactor(prefs.typingSpeedFactor.toDouble())

  private val maxTypedCharsPerBatch: Int = 60
  private val flushEveryChars: Int = 120
  private val flushDelayMs: Long = 12
  private var keyboardMapper: KeyboardMapper = KeyboardMapper(KeyboardLayout.LAYOUT_US)

  private val udcStatePoller = Handler(Looper.getMainLooper())
  private var pollingRunnable: Runnable? = null
  private var lastUdcState: String? = null

  private val execSinkRef = AtomicReference<EventChannel.EventSink?>(null)
  private val cancelExecRef = AtomicReference<String?>(null)

  private var hidActiveGraceMs: Long = 1500
  private var unicodeFallbackMode: String = "warn"
  @Volatile private var cachedUsleepSupport: Boolean? = null
  @Volatile private var calibratedDelayFloorUs: Int? = null

  private var consecutiveWriteFailures = 0
  private var lastWriteFailureAtMs: Long? = null

  class HidWriteException(
    val errorCode: String,
    message: String
  ) : RuntimeException(message)

  data class Status(
    val rootAvailable: Boolean,
    val supportAvailable: Boolean,
    val udcList: List<String>,
    val state: String,
    val activeProfileId: String?,
    val message: String?,
    val keyboardWriterReady: Boolean,
    val mouseWriterReady: Boolean,
    val deviceConnected: Boolean,
    val udcState: String?,
  ) {
    val isActive: Boolean get() = state == "ACTIVE" || state == "ACTIVATING"
    fun toMap(): Map<String, Any?> = mapOf(
      "rootAvailable" to rootAvailable,
      "supportAvailable" to supportAvailable,
      "udcList" to udcList,
      "state" to state,
      "isActive" to isActive,
      "activeProfileId" to activeProfileId,
      "message" to message,
      "keyboardWriterReady" to keyboardWriterReady,
      "mouseWriterReady" to mouseWriterReady,
      "deviceConnected" to deviceConnected,
      "udcState" to udcState,
    )
  }

  private val statusRef = AtomicReference(
    Status(
      rootAvailable = false,
      supportAvailable = false,
      udcList = emptyList(),
      state = "IDLE",
      activeProfileId = null,
      message = null,
      keyboardWriterReady = false,
      mouseWriterReady = false,
      deviceConnected = false,
      udcState = null,
    )
  )

  private val sinkRef = AtomicReference<EventChannel.EventSink?>(null)

  init {
    refreshAndEmitStatus(restoreFromPrefs = true)
    setRiskyFastMode(prefs.riskyFastMode)
  }

  fun attachStatusSink(sink: EventChannel.EventSink) {
    sinkRef.set(sink)
    val snap = statusRef.get().toMap()
    main.post {
      try {
        sink.success(snap)
      } catch (_: Throwable) {
      }
    }
  }

  fun detachStatusSink() {
    sinkRef.set(null)
  }

  fun attachExecSink(sink: EventChannel.EventSink) {
    execSinkRef.set(sink)
  }

  fun detachExecSink() {
    execSinkRef.set(null)
  }

  fun cancelExecution(executionId: String?) {
    cancelExecRef.set(executionId ?: "*")
    emitExec(
      mapOf(
        "type" to "cancel_requested",
        "executionId" to (executionId ?: "*"),
        "timestampMs" to System.currentTimeMillis(),
      )
    )
  }

  private fun isCancelRequested(executionId: String): Boolean {
    val v = cancelExecRef.get() ?: return false
    return v == "*" || v == executionId
  }

  fun getStatusSnapshot(): Status {
    return refreshAndEmitStatus(restoreFromPrefs = false)
  }

  fun refreshAndEmitStatus(restoreFromPrefs: Boolean): Status {
    val current = statusRef.get()
    val rootOk = checkRoot()
    val configfsOk = rootOk && ensureConfigfsAvailable()
    val udcs = if (rootOk) listUdcs() else emptyList()
    val supportOk = rootOk && configfsOk && udcs.isNotEmpty()

    var state = current.state
    var activeId = current.activeProfileId
    var msg = current.message
    var deviceConnected = current.deviceConnected
    var udcState = current.udcState

    if (restoreFromPrefs && state != "ACTIVE") {
      val savedId = prefs.activeProfileId
      val savedDir = prefs.activeGadgetDir
      if (!savedId.isNullOrBlank() && !savedDir.isNullOrBlank() && rootOk) {
        val stillActive = isGadgetDirBound(savedDir)
        if (stillActive) {
          state = "ACTIVE"
          activeId = savedId
          msg = null
          log.log("gadget", "Restored active state for profile=$savedId")
          reopenHidWritersFromPrefsBestEffort()
          startUdcPolling()
        } else {
          prefs.clearActive()
        }
      }
    }

    val next = Status(
      rootAvailable = rootOk,
      supportAvailable = supportOk,
      udcList = udcs,
      state = state,
      activeProfileId = activeId,
      message = msg,
      keyboardWriterReady = root.isKeyboardWriterReady(),
      mouseWriterReady = root.isMouseWriterReady(),
      deviceConnected = deviceConnected,
      udcState = udcState,
    )
    statusRef.set(next)
    emit(next)
    return next
  }

  fun checkRoot(): Boolean = root.hasRoot()

  fun checkSupport(): Boolean {
    if (!checkRoot()) return false
    if (!ensureConfigfsAvailable()) return false
    return listUdcs().isNotEmpty()
  }

  fun listUdcs(): List<String> {
    val r = root.exec("ls -1 /sys/class/udc 2>/dev/null || true")
    val items = r.stdout
      .lineSequence()
      .map { it.trim().trim('\r') }
      .filter { it.isNotBlank() }
      .filter { udcNameRegex.matches(it) }
      .toList()
    if (items.isNotEmpty()) return items

    val p = root.exec("getprop sys.usb.controller 2>/dev/null || true")
    val lines = p.stdout
      .lineSequence()
      .map { it.trim().trim('\r') }
      .filter { it.isNotBlank() }
      .toList()
    val direct = lines.firstOrNull { udcNameRegex.matches(it) }
    if (!direct.isNullOrBlank()) return listOf(direct)

    val dumpLine = lines.firstOrNull { it.startsWith("[sys.usb.controller]") }
    if (!dumpLine.isNullOrBlank()) {
      val m = Regex("\\[sys\\.usb\\.controller\\]: \\[(.*)]").find(dumpLine)
      val v = m?.groupValues?.getOrNull(1)?.trim()
      if (!v.isNullOrBlank() && udcNameRegex.matches(v)) return listOf(v)
    }
    return emptyList()
  }

  fun setKeyboardLayout(layout: Int) {
    keyboardMapper = KeyboardMapper(layout)
    log.log("keyboard", "Layout changed to: ${KeyboardLayout.getLayoutName(layout)}")
  }

  fun getTypingSpeedFactor(): Double {
    return normalizeTypingSpeedFactor(typingSpeedFactor)
  }

  fun setTypingSpeedFactor(factor: Double): Double {
    val applied = normalizeTypingSpeedFactor(factor)
    typingSpeedFactor = applied
    prefs.typingSpeedFactor = applied.toFloat()
    log.log("kbd", "Typing speed factor set to $applied")
    return applied
  }

  fun setHidGraceWindowMs(ms: Long): Long {
    val clamped = ms.coerceIn(0L, 5000L)
    hidActiveGraceMs = clamped
    log.log("hid", "Grace window set to ${clamped}ms")
    return clamped
  }

  fun setUnicodeFallbackMode(mode: String): String {
    val normalized = mode.trim().lowercase(Locale.US)
    unicodeFallbackMode = when (normalized) {
      "skip", "warn", "ascii" -> normalized
      else -> "warn"
    }
    log.log("kbd", "Unicode fallback mode set to $unicodeFallbackMode")
    return unicodeFallbackMode
  }

  fun setRiskyFastMode(enabled: Boolean) {
    prefs.riskyFastMode = enabled
    if (enabled) {
      minInterKeyDelayUs = 40
      minKeyDownHoldUs = 300
      log.log("kbd", "Risky fast mode enabled")
    } else {
      minInterKeyDelayUs = 180
      minKeyDownHoldUs = 1500
      log.log("kbd", "Risky fast mode disabled")
    }
  }

  fun estimateKeyTapDurationMs(): Long {
    val interUs = effectiveDelayUsForEstimate(scaledInterKeyDelayUs())
    val downUs = effectiveDelayUsForEstimate(scaledDownHoldUs(baseKeyDownHoldUs))
    val overheadUs = estimateReportOverheadUs() * 3
    val totalUs = interUs + downUs + overheadUs
    return kotlin.math.max(0L, (totalUs / 1000.0).roundToInt().toLong())
  }

  fun estimateTypeStringDurationMs(text: String, perCharDelayMs: Int): Long {
    if (text.isEmpty()) return 0
    val interUs = effectiveDelayUsForEstimate(scaledInterKeyDelayUs())
    val downUs = effectiveDelayUsForEstimate(scaledDownHoldUs(baseKeyDownHoldUs))
    var count = 0
    for (ch in text) {
      if (keyboardMapper.getStrokeForChar(ch) != null) {
        count++
      } else {
        count += countFallbackChars(ch)
      }
    }
    if (count <= 0) return 0
    val baseMs = ((interUs + downUs) * count) / 1000.0
    val delayMs = perCharDelayMs.coerceAtLeast(0) * count.toLong()
    val reportCount = 1L + (count.toLong() * 2L)
    val overheadMs = (reportCount * estimateReportOverheadUs()) / 1000.0
    var extraMs = 0L
    if (perCharDelayMs <= 0 && flushEveryChars > 0 && flushDelayMs > 0) {
      val flushes = text.length / flushEveryChars
      extraMs = flushes * flushDelayMs
    }
    return baseMs.roundToInt().toLong() + delayMs + extraMs + overheadMs.roundToInt().toLong()
  }

  private fun applySessionSlowdown(multiplier: Double) {
    val next = normalizeTypingSpeedFactor(typingSpeedFactor * multiplier)
    if (next == typingSpeedFactor) return
    typingSpeedFactor = next
    log.log("kbd", "Auto-slow typing speed factor to $next")
  }

  private fun recordWriteSuccess() {
    consecutiveWriteFailures = 0
    lastWriteFailureAtMs = null
  }

  private fun recordWriteFailure() {
    val now = System.currentTimeMillis()
    val last = lastWriteFailureAtMs
    consecutiveWriteFailures = if (last != null && now - last <= 10_000L) {
      consecutiveWriteFailures + 1
    } else {
      1
    }
    lastWriteFailureAtMs = now
    if (consecutiveWriteFailures >= 2) {
      applySessionSlowdown(0.85)
    }
  }

  fun activate(profileMap: Map<*, *>) {
    val profile = parseProfile(profileMap)
    if (!checkRoot()) {
      setError("Root not available (su denied).")
      return
    }
    if (!checkSupport()) {
      setError("USB gadget support not detected (configfs/UDC missing).")
      return
    }

    setState("ACTIVATING", profile.id, "Creating gadget…")
    val snap = captureUsbSnapshot()
    prefs.setUsbSnapshot(
      sysUsbConfig = snap.sysUsbConfig,
      sysUsbState = snap.sysUsbState,
      sysUsbConfigfs = snap.sysUsbConfigfs,
      persistSysUsbConfig = snap.persistSysUsbConfig,
      boundGadgets = snap.boundGadgetsRaw,
    )

    val gadgetDir = "gadgetfs_${profile.id.take(12).lowercase(Locale.US)}"
    val script = Configfs.buildCreateAndBindScript(profile, gadgetDir)
    val r = root.exec(script, timeoutSec = 30)
    if (!r.ok) {
      log.logError("gadget", "Activation failed; attempting USB restore")
      restoreUsbSnapshotBestEffort(reason = "activation_failed")
      prefs.clearUsbSnapshot()
      setError("Activation failed (exit=${r.exitCode}). ${r.stderr.trim().ifEmpty { r.stdout.trim() }}")
      return
    }

    val kbdDev = when (profile.roleType.lowercase(Locale.US)) {
      "mouse" -> null
      "keyboard" -> "/dev/hidg0"
      else -> "/dev/hidg0"
    }
    val mouseDev = when (profile.roleType.lowercase(Locale.US)) {
      "mouse" -> "/dev/hidg0"
      "keyboard" -> null
      else -> "/dev/hidg1"
    }

    prefs.setActive(profile.id, profile.roleType, gadgetDir, kbdDev, mouseDev)
    startForeground("USB gadget active: ${profile.name}")
    openHidWritersBestEffort(kbdDev, mouseDev)
    setState("ACTIVE", profile.id, null)
    log.log("gadget", "Active profile: ${profile.id} (${profile.roleType})")
    startUdcPolling()
  }

  fun retryOpenHidWriters() {
    val kbdDev = prefs.activeKeyboardDev
    val mouseDev = prefs.activeMouseDev
    if (kbdDev.isNullOrBlank() && mouseDev.isNullOrBlank()) {
      log.logError("hid", "Cannot retry: no active HID devices in prefs")
      return
    }
    log.log("hid", "Retrying HID writer open (user-requested)")
    openHidWritersBestEffort(kbdDev, mouseDev)
    refreshAndEmitStatus(restoreFromPrefs = false)
  }

  fun deactivate() {
    val current = statusRef.get()
    if (current.state == "IDLE") return
    if (current.state == "ACTIVATING") return

    setState("ACTIVATING", current.activeProfileId, "Deactivating…")
    stopUdcPolling()
    try {
      releaseAllKeysBestEffort()
    } catch (_: Throwable) {
    }
    closeHidWritersBestEffort()
    val gadgetDir = prefs.activeGadgetDir
    if (!gadgetDir.isNullOrBlank()) {
      root.exec(Configfs.buildUnbindAndCleanupScript(gadgetDir), timeoutSec = 20)
    } else {
      root.exec(Configfs.buildPanicStopScript(), timeoutSec = 20)
    }
    stopForeground()
    restoreUsbSnapshotBestEffort(reason = "deactivate")
    prefs.clearActive()
    prefs.clearUsbSnapshot()
    setState("IDLE", null, null)
    log.log("gadget", "Deactivated")
  }

  fun panicStop() {
    setState("ACTIVATING", null, "Panic stop…")
    stopUdcPolling()
    try {
      releaseAllKeysBestEffort()
    } catch (_: Throwable) {
    }
    closeHidWritersBestEffort()
    val gadgetDir = prefs.activeGadgetDir
    if (!gadgetDir.isNullOrBlank()) {
      root.exec(Configfs.buildUnbindAndCleanupScript(gadgetDir), timeoutSec = 20)
    } else {
      root.exec(Configfs.buildPanicStopScript(), timeoutSec = 20)
    }
    stopForeground()
    restoreUsbSnapshotBestEffort(reason = "panic_stop")
    prefs.clearActive()
    prefs.clearUsbSnapshot()
    setState("IDLE", null, null)
    log.log("gadget", "Panic stop complete")
  }

  fun testMouseMove(dx: Int, dy: Int, wheel: Int, buttons: Int) {
    val current = statusRef.get()
    if (current.state != "ACTIVE") throw IllegalStateException("Gadget is not active")
    val path = prefs.activeMouseDev ?: throw IllegalStateException("Mouse HID device not available")
    val report = byteArrayOf(
      (buttons and 0xFF).toByte(),
      (dx.coerceIn(-127, 127) and 0xFF).toByte(),
      (dy.coerceIn(-127, 127) and 0xFF).toByte(),
      (wheel.coerceIn(-127, 127) and 0xFF).toByte(),
    )
    writeMouseReport(path, report)
    log.log("test", "Mouse report to $path dx=$dx dy=$dy wheel=$wheel buttons=$buttons")
  }

  fun testKeyboardKey(keyLabel: String) {
    val current = statusRef.get()
    if (current.state != "ACTIVE") throw IllegalStateException("Gadget is not active")
    val path = prefs.activeKeyboardDev ?: throw IllegalStateException("Keyboard HID device not available")
    val trimmed = keyLabel.trimEnd('\r')
    if (trimmed.isEmpty()) return
    val code = HidSpec.keyCodeFor(trimmed)
    if (code != null) {
      writeKeyboardTap(path, mods = 0x00, key = code, downHoldUs = scaledDownHoldUs(baseKeyDownHoldUs))
      log.log("test", "Keyboard key=$trimmed code=0x${Integer.toHexString(code)}")
      return
    }
    typeText(path, trimmed)
    val preview = if (trimmed.length <= 18) trimmed else trimmed.take(18) + "…"
    log.log("test", "Keyboard text(len=${trimmed.length}) \"$preview\"")
  }

  fun typeString(text: String, delayMs: Int = 0) {
    val current = statusRef.get()
    if (current.state != "ACTIVE") throw IllegalStateException("Gadget is not active")
    val path = prefs.activeKeyboardDev ?: throw IllegalStateException("Keyboard HID device not available")
    if (delayMs > 0) {
      typeTextWithDelay(path, text, delayMs)
    } else {
      typeText(path, text)
    }
    val preview = if (text.length <= 18) text else text.take(18) + "…"
    log.log("type", "String(len=${text.length}, delay=${delayMs}ms) \"$preview\"")
  }

  private fun typeTextWithDelay(path: String, text: String, delayMs: Int) {
    val interUs = scaledInterKeyDelayUs()
    val downUs = scaledDownHoldUs(baseKeyDownHoldUs)
    for (ch in text) {
      val stroke = keyboardMapper.getStrokeForChar(ch)
      if (stroke != null) {
        val up = keyboardReport(0x00, 0x00)
        val down = keyboardReport(stroke.modifiers, stroke.keyCode)
        writeKeyboardReportsWithDelays(
          path,
          reports = listOf(up, down, up),
          delaysUs = listOf(interUs, downUs)
        )
        if (delayMs > 0) Thread.sleep(delayMs.toLong())
      } else {
        handleUnsupportedChar(path, ch, delayMs, withPerCharDelay = true)
      }
    }
  }

  fun writeKeyboardTapWithMods(mods: Int, key: Int) {
    val current = statusRef.get()
    if (current.state != "ACTIVE") throw IllegalStateException("Gadget is not active")
    val path = prefs.activeKeyboardDev ?: throw IllegalStateException("Keyboard HID device not available")
    writeKeyboardTap(path, mods = mods, key = key, downHoldUs = scaledDownHoldUs(baseKeyDownHoldUs))
    log.log("test", "Keyboard mods=0x${Integer.toHexString(mods)} key=0x${Integer.toHexString(key)}")
  }

  fun testCtrlAltDel() {
    val current = statusRef.get()
    if (current.state != "ACTIVE") throw IllegalStateException("Gadget is not active")
    val path = prefs.activeKeyboardDev ?: throw IllegalStateException("Keyboard HID device not available")
    val mods = 0x01 or 0x04
    val del = HidSpec.keyCodeFor("DELETE") ?: 0x4C
    writeKeyboardTap(path, mods = mods, key = del, downHoldUs = scaledDownHoldUs(12000))
    log.log("test", "Ctrl+Alt+Del sent")
  }

  fun executeDuckyScript(script: String, delayMultiplier: Double = 1.0, executionId: String? = null) {
    val id = executionId?.takeIf { it.isNotBlank() } ?: "exec_${System.currentTimeMillis()}"
    cancelExecRef.set(null)
    prefs.lastExecutedScript = script
    val executor = DuckyScriptExecutor(
      manager = this,
      log = log,
      delayMultiplier = delayMultiplier,
      executionId = id,
      emitExec = { m -> emitExec(m) },
      shouldCancel = { isCancelRequested(id) }
    )
    executor.execute(script)
  }

  fun setDialShortcutConfig(enabled: Boolean, mode: String, script: String?, name: String?) {
    val safeMode = if (mode == "payload" || mode == "last") mode else "last"
    val binding = DialShortcutBinding(
      code = "78259",
      enabled = enabled,
      mode = safeMode,
      script = script?.takeIf { it.isNotBlank() },
      name = name?.takeIf { it.isNotBlank() },
    )
    setDialShortcutBindingsTyped(listOf(binding))
  }

  fun setDialShortcutBindings(bindingsRaw: List<Map<*, *>>) {
    val out = ArrayList<DialShortcutBinding>()
    for (b in bindingsRaw) {
      val code = b["code"]?.toString()?.trim().orEmpty()
      if (code.isEmpty()) continue
      val enabled = (b["enabled"] as? Boolean) ?: false
      val modeRaw = b["mode"]?.toString()?.trim() ?: "last"
      val mode = if (modeRaw == "payload" || modeRaw == "last") modeRaw else "last"
      val script = b["script"]?.toString()?.takeIf { it.isNotBlank() }
      val name = b["name"]?.toString()?.takeIf { it.isNotBlank() }
      out.add(DialShortcutBinding(code, enabled, mode, script, name))
    }
    setDialShortcutBindingsTyped(out)
  }

  fun setDialShortcutBindingsTyped(bindings: List<DialShortcutBinding>) {
    prefs.setDialShortcutBindings(bindings)
    log.log("dial", "Dial shortcuts updated (count=${bindings.size})")
  }

  fun estimateDuckyScriptDurationMs(script: String, delayMultiplier: Double = 1.0): Long {
    val estimator = DuckyScriptEstimator(
      manager = this,
      log = log,
      delayMultiplier = delayMultiplier,
    )
    return estimator.estimate(script)
  }

  private fun emitExec(map: Map<String, Any?>) {
    main.post {
      try {
        execSinkRef.get()?.success(map)
      } catch (_: Throwable) {
      }
    }
  }

  private fun pollUdcState(): String? {
    val current = statusRef.get()
    if (current.state != "ACTIVE") return null
    val gadgetDir = prefs.activeGadgetDir ?: return null
    val script = """
      CFGBASE="/config/usb_gadget"
      [ -d "${'$'}CFGBASE" ] || CFGBASE="/sys/kernel/config/usb_gadget"

      G="${'$'}CFGBASE/${gadgetDir.replace("\"", "").replace("'", "")}"
      if [ ! -f "${'$'}G/UDC" ]; then
        exit 1
      fi

      UDC_NAME=${'$'}(cat "${'$'}G/UDC" 2>/dev/null | tr -d '\r')
      if [ -z "${'$'}UDC_NAME" ]; then
        exit 1
      fi

      if [ -f "/sys/class/udc/${'$'}UDC_NAME/state" ]; then
        cat "/sys/class/udc/${'$'}UDC_NAME/state" 2>/dev/null | tr -d '\r'
      else
        echo "unknown"
      fi
    """.trimIndent()
    val r = root.exec(script, timeoutSec = 3)
    return if (r.ok) r.stdout.trim().takeIf { it.isNotBlank() } else null
  }

  private fun startUdcPolling() {
    stopUdcPolling()
    pollingRunnable = object : Runnable {
      override fun run() {
        try {
          val udcState = pollUdcState()
          val isConnected = udcState == "configured"
          if (udcState != lastUdcState) {
            lastUdcState = udcState
            val current = statusRef.get()
            val next = current.copy(
              deviceConnected = isConnected,
              udcState = udcState,
            )
            statusRef.set(next)
            emit(next)
            if (isConnected) {
              log.log("udc", "Host connected (state: $udcState)")
            } else {
              log.log("udc", "Host disconnected (state: ${udcState ?: "unknown"})")
            }
          }
        } catch (t: Throwable) {
          log.logError("udc", "Polling failed: ${t.message}")
        }
        udcStatePoller.postDelayed(this, 2000)
      }
    }
    udcStatePoller.post(pollingRunnable!!)
    log.log("udc", "Started UDC state polling")
  }

  private fun stopUdcPolling() {
    pollingRunnable?.let { udcStatePoller.removeCallbacks(it) }
    pollingRunnable = null
    lastUdcState = null
  }

  private fun openHidWritersBestEffort(kbdDev: String?, mouseDev: String?) {
    try {
      val rr = root.openHidWriters(kbdDev, mouseDev, timeoutSec = 6)
      if (rr.ok) {
        log.log(
          "hid",
          "Persistent HID writers ready: kbd=${root.isKeyboardWriterReady()} mouse=${root.isMouseWriterReady()}"
        )
      } else {
        log.logError(
          "hid",
          "Failed to open persistent HID writers (exit=${rr.exitCode}). Falling back to per-write opens."
        )
      }
    } catch (t: Throwable) {
      log.logError("hid", "openHidWriters failed: ${t.message}")
    }
  }

  private fun reopenHidWritersFromPrefsBestEffort() {
    val kbdDev = prefs.activeKeyboardDev
    val mouseDev = prefs.activeMouseDev
    if (kbdDev.isNullOrBlank() && mouseDev.isNullOrBlank()) return
    openHidWritersBestEffort(kbdDev, mouseDev)
  }

  private fun closeHidWritersBestEffort() {
    try {
      root.closeHidWriters(timeoutSec = 4)
    } catch (_: Throwable) {
    }
  }

  private fun parseProfile(map: Map<*, *>): Configfs.ParsedProfile {
    val id = (map["id"] ?: "").toString().ifBlank { throw IllegalArgumentException("Profile id missing") }
    val name = (map["name"] ?: "Profile").toString()
    val roleType = (map["roleType"] ?: "mouse").toString()
    val tunables = (map["tunables"] as? Map<*, *>)

    fun str(key: String, fallback: String): String {
      val v = (tunables?.get(key) ?: map[key])?.toString()
      return if (v.isNullOrBlank()) fallback else v
    }

    fun intHexOrDec(key: String, fallback: Int): Int {
      val raw = (tunables?.get(key) ?: map[key])?.toString()?.trim()
      if (raw.isNullOrBlank()) return fallback
      return try {
        if (raw.startsWith("0x", ignoreCase = true)) raw.substring(2).toInt(16) else raw.toInt()
      } catch (_: Throwable) {
        fallback
      }
    }

    val manufacturer = str("manufacturer", "KaijinLab")
    val product = str("product", "GadgetFS")
    val serial = str("serialNumber", "GadgetFS:${id.take(12)}")
    val vendorId = intHexOrDec("vendorId", 0x1d6b)
    val productId = intHexOrDec(
      "productId",
      when (roleType.lowercase(Locale.US)) {
        "keyboard" -> 0x0104
        "mouse" -> 0x0104
        else -> 0x0104
      }
    )
    val maxPower = intHexOrDec("maxPowerMa", 250)

    return Configfs.ParsedProfile(
      id = id,
      name = name,
      roleType = roleType,
      manufacturer = manufacturer,
      product = product,
      serialNumber = serial,
      vendorId = vendorId,
      productId = productId,
      maxPowerMa = maxPower,
    )
  }

  private fun keyboardReport(mods: Int, key: Int): ByteArray {
    return byteArrayOf(
      (mods and 0xFF).toByte(),
      0x00,
      (key and 0xFF).toByte(),
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    )
  }

  private fun keyboardReportMulti(mods: Int, keys: List<Int>): ByteArray {
    val report = ByteArray(8)
    report[0] = (mods and 0xFF).toByte()
    report[1] = 0x00
    val count = min(6, keys.size)
    for (i in 0 until count) {
      report[2 + i] = (keys[i] and 0xFF).toByte()
    }
    return report
  }

  fun writeKeyboardReport(mods: Int, keys: List<Int>) {
    if (!waitForActive(hidActiveGraceMs)) {
      throw HidWriteException("HID_NOT_ACTIVE", "Gadget is not active")
    }
    val path = prefs.activeKeyboardDev ?: throw IllegalStateException("Keyboard HID device not available")
    val report = keyboardReportMulti(mods, keys)
    writeKeyboardReportsWithDelays(path, reports = listOf(report), delaysUs = emptyList())
  }

  private fun waitForActive(graceMs: Long): Boolean {
    val start = System.currentTimeMillis()
    while (System.currentTimeMillis() - start < graceMs) {
      val current = statusRef.get()
      if (current.state == "ACTIVE") return true
      try {
        Thread.sleep(150)
      } catch (_: Throwable) {
      }
    }
    return statusRef.get().state == "ACTIVE"
  }

  fun isHostConnected(): Boolean {
    val current = statusRef.get()
    val udc = current.udcState?.trim()?.lowercase(Locale.US)
    val configured = udc?.contains("configured") == true
    return current.deviceConnected || configured
  }

  fun isUdcConfigured(): Boolean {
    val udc = statusRef.get().udcState?.trim()?.lowercase(Locale.US)
    return udc?.contains("configured") == true
  }

  fun isKeyboardWriterReady(): Boolean = statusRef.get().keyboardWriterReady

  fun isMouseWriterReady(): Boolean = statusRef.get().mouseWriterReady

  fun isActive(): Boolean = statusRef.get().state == "ACTIVE"

  fun waitForHostConnected(timeoutMs: Long): Boolean {
    val start = System.currentTimeMillis()
    while (System.currentTimeMillis() - start < timeoutMs) {
      if (isHostConnected()) return true
      try {
        Thread.sleep(200)
      } catch (_: Throwable) {
      }
    }
    return isHostConnected()
  }

  fun waitForCondition(timeoutMs: Long, predicate: () -> Boolean): Boolean {
    val start = System.currentTimeMillis()
    while (System.currentTimeMillis() - start < timeoutMs) {
      if (predicate()) return true
      try {
        Thread.sleep(200)
      } catch (_: Throwable) {
      }
    }
    return predicate()
  }

  private fun releaseAllKeysBestEffort() {
    val path = prefs.activeKeyboardDev ?: return
    val up = keyboardReport(0x00, 0x00)
    try {
      writeKeyboardReportsWithDelays(
        path,
        reports = listOf(up, up, up),
        delaysUs = listOf(0, 0)
      )
      log.log("kbd", "Sent all-keys-up before teardown")
    } catch (t: Throwable) {
      log.logError("kbd", "Failed to send all-keys-up: ${t.message}")
    }
  }

  private fun writeKeyboardTap(path: String, mods: Int, key: Int, downHoldUs: Int) {
    val up = keyboardReport(0x00, 0x00)
    val down = keyboardReport(mods, key)
    writeKeyboardReportsWithDelays(
      path,
      reports = listOf(up, down, up),
      delaysUs = listOf(scaledInterKeyDelayUs(), downHoldUs)
    )
  }

  private fun typeText(path: String, text: String) {
    var idx = 0
    var charsSinceFlush = 0
    while (idx < text.length) {
      val end = min(text.length, idx + maxTypedCharsPerBatch)
      val chunk = text.substring(idx, end)
      typeTextChunk(path, chunk)
      charsSinceFlush += chunk.length
      if (charsSinceFlush >= flushEveryChars) {
        Thread.sleep(flushDelayMs)
        charsSinceFlush = 0
      }
      idx = end
    }
  }

  private fun typeTextChunk(path: String, chunk: String) {
    val strokes = ArrayList<KeyStroke>(chunk.length)
    for (ch in chunk) {
      val s = keyboardMapper.getStrokeForChar(ch)
      if (s != null) {
        strokes.add(s)
      } else {
        addFallbackStrokes(ch, strokes)
      }
    }
    if (strokes.isEmpty()) return

    val interUs = scaledInterKeyDelayUs()
    val downUs = scaledDownHoldUs(baseKeyDownHoldUs)

    val reports = ArrayList<ByteArray>(1 + strokes.size * 2)
    val delays = ArrayList<Int>(strokes.size * 2)
    reports.add(keyboardReport(0x00, 0x00))
    for (stroke in strokes) {
      reports.add(keyboardReport(stroke.modifiers, stroke.keyCode))
      reports.add(keyboardReport(0x00, 0x00))
    }
    for (i in 0 until (reports.size - 1)) {
      val isDownReport = (i % 2 == 1)
      delays.add(if (isDownReport) downUs else interUs)
    }
    writeKeyboardReportsWithDelays(path, reports, delays)
  }

  private fun addFallbackStrokes(ch: Char, strokes: MutableList<KeyStroke>) {
    when (unicodeFallbackMode) {
      "skip" -> return
      "warn" -> {
        val c = if (ch.code in 32..126) ch.toString() else "U+${ch.code.toString(16)}"
        log.log("kbd", "Skipping unsupported char: $c")
        return
      }
      "ascii" -> {
        val ascii = transliterateToAscii(ch)
        if (ascii.isEmpty()) {
          val fallback = '?'
          keyboardMapper.getStrokeForChar(fallback)?.let { strokes.add(it) }
          log.log("kbd", "Transliterate failed; using '?' for U+${ch.code.toString(16)}")
          return
        }
        for (c in ascii) {
          val s = keyboardMapper.getStrokeForChar(c)
          if (s != null) strokes.add(s)
        }
      }
    }
  }

  private fun countFallbackChars(ch: Char): Int {
    return when (unicodeFallbackMode) {
      "skip", "warn" -> 0
      "ascii" -> {
        val ascii = transliterateToAscii(ch)
        val out = if (ascii.isEmpty()) "?" else ascii
        var count = 0
        for (c in out) {
          if (keyboardMapper.getStrokeForChar(c) != null) {
            count++
          }
        }
        count
      }
      else -> 0
    }
  }

  private fun handleUnsupportedChar(path: String, ch: Char, delayMs: Int, withPerCharDelay: Boolean) {
    when (unicodeFallbackMode) {
      "skip" -> return
      "warn" -> {
        val c = if (ch.code in 32..126) ch.toString() else "U+${ch.code.toString(16)}"
        log.log("kbd", "Skipping unsupported char: $c")
      }
      "ascii" -> {
        val ascii = transliterateToAscii(ch)
        val out = if (ascii.isEmpty()) "?" else ascii
        for (c in out) {
          val stroke = keyboardMapper.getStrokeForChar(c)
          if (stroke != null) {
            val up = keyboardReport(0x00, 0x00)
            val down = keyboardReport(stroke.modifiers, stroke.keyCode)
            writeKeyboardReportsWithDelays(
              path,
              reports = listOf(up, down, up),
              delaysUs = listOf(scaledInterKeyDelayUs(), scaledDownHoldUs(baseKeyDownHoldUs))
            )
            if (withPerCharDelay && delayMs > 0) Thread.sleep(delayMs.toLong())
          }
        }
      }
    }
  }

  private fun transliterateToAscii(ch: Char): String {
    val normalized = Normalizer.normalize(ch.toString(), Normalizer.Form.NFD)
    val sb = StringBuilder()
    for (c in normalized) {
      if (c.code <= 0x7E && c.code >= 0x20) {
        sb.append(c)
      }
    }
    return sb.toString()
  }

  private fun writeKeyboardReportsWithDelays(
    path: String,
    reports: List<ByteArray>,
    delaysUs: List<Int>
  ) {
    if (reports.isEmpty()) return
    val useDirect = root.isKeyboardWriterReady()
    val usleepSnippet = """
      USLP=""
      if command -v toybox >/dev/null 2>&1 && toybox usleep 1 >/dev/null 2>&1; then
        USLP="toybox usleep"
      elif command -v usleep >/dev/null 2>&1; then
        USLP="usleep"
      elif command -v busybox >/dev/null 2>&1 && busybox usleep 1 >/dev/null 2>&1; then
        USLP="busybox usleep"
      fi
    """.trimIndent()

    fun toHexEsc(bytes: ByteArray): String {
      return bytes.joinToString(separator = "") { b ->
        val v = b.toInt() and 0xFF
        String.format(Locale.US, "\\x%02x", v)
      }
    }

    val writes = StringBuilder()
    for (i in reports.indices) {
      val hex = toHexEsc(reports[i])
      writes.append("printf '%b' '").append(hex).append("' >&").append(HID_KBD_FD).append("\n")
      if (i != reports.lastIndex) {
        val d = delaysUs.getOrNull(i) ?: 0
        if (d > 0) {
          writes.append(
            """
              if [ -n "${'$'}USLP" ]; then
                ${'$'}USLP $d
              else
                sleep 0.01
              fi
            """.trimIndent()
          ).append("\n")
        }
      }
    }

    val openLocal = if (useDirect) "" else "exec $HID_KBD_FD> \"${'$'}P\""
    val closeLocal = if (useDirect) "" else "(exec $HID_KBD_FD>&-) 2>/dev/null || true"
    val script = """
      set -e
      P=${shQuote(path)}
      $usleepSnippet
      $openLocal

      $writes

      $closeLocal
    """.trimIndent()

    var attempt = 0
    var lastErr: String? = null
    while (attempt < 3) {
      val r = if (useDirect) root.execDirect(script, timeoutSec = 8) else root.exec(script, timeoutSec = 8)
      if (r.ok) {
        recordWriteSuccess()
        return
      }
      recordWriteFailure()
      lastErr = r.stderr.trim().ifEmpty { r.stdout.trim() }
      if (attempt < 2) {
        val backoffMs = 200L * (1L shl attempt)
        Thread.sleep(backoffMs)
        waitForActive(hidActiveGraceMs)
      }
      attempt++
    }
    val detail = lastErr ?: "no stderr/stdout"
    throw HidWriteException(
      "HID_WRITE_FAILED",
      "Failed to write keyboard reports to $path (retries=3). " +
        detail
    )
  }

  private fun writeMouseReport(path: String, bytes: ByteArray) {
    if (root.isMouseWriterReady()) {
      try {
        root.writeMouseFast(bytes)
        return
      } catch (t: Throwable) {
        log.logError("hid", "Mouse fast-writer failed; fallback to slow path: ${t.message}")
      }
    }
    val hexEsc = bytes.joinToString(separator = "") { b ->
      val v = b.toInt() and 0xFF
      String.format(Locale.US, "\\x%02x", v)
    }
    val script = "printf '%b' '$hexEsc' > ${shQuote(path)}"
    var attempt = 0
    var lastErr: String? = null
    while (attempt < 3) {
      val r = root.exec(script, timeoutSec = 5)
      if (r.ok) {
        recordWriteSuccess()
        return
      }
      recordWriteFailure()
      lastErr = r.stderr.trim().ifEmpty { r.stdout.trim() }
      if (attempt < 2) {
        val backoffMs = 200L * (1L shl attempt)
        Thread.sleep(backoffMs)
        waitForActive(hidActiveGraceMs)
      }
      attempt++
    }
    val detail = lastErr ?: "no stderr/stdout"
    throw HidWriteException(
      "HID_MOUSE_WRITE_FAILED",
      "Failed to write HID report to $path (retries=3). $detail"
    )
  }

  private fun shQuote(s: String): String = "'" + s.replace("'", "'\\''") + "'"

  private fun ensureConfigfsAvailable(): Boolean {
    val fast = root.exec("test -d /config/usb_gadget || test -d /sys/kernel/config/usb_gadget")
    if (fast.ok) return true
    val script = """
      if [ -d /config ] && [ ! -d /config/usb_gadget ]; then
        mount | grep -q " /config " || mount -t configfs none /config 2>/dev/null
      fi
      if [ -d /sys/kernel ] && [ ! -d /sys/kernel/config/usb_gadget ]; then
        mkdir -p /sys/kernel/config 2>/dev/null
        mount | grep -q " /sys/kernel/config " || mount -t configfs none /sys/kernel/config 2>/dev/null
      fi
      test -d /config/usb_gadget || test -d /sys/kernel/config/usb_gadget
    """.trimIndent()
    val mounted = root.exec(script, timeoutSec = 10)
    return mounted.ok
  }

  private fun isGadgetDirBound(gadgetDir: String): Boolean {
    val safe = gadgetDir.replace("\"", "").replace("'", "")
    val script = """
      CFGBASE=/config/usb_gadget
      [ -d "${'$'}CFGBASE" ] || CFGBASE=/sys/kernel/config/usb_gadget
      test -f "${'$'}CFGBASE/$safe/UDC" && test -s "${'$'}CFGBASE/$safe/UDC"
    """.trimIndent()
    val r = root.exec(script, timeoutSec = 5)
    return r.ok
  }

  private fun startForeground(title: String) {
    val intent = Intent(context, GadgetForegroundService::class.java).apply {
      putExtra(GadgetForegroundService.EXTRA_TITLE, title)
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      ContextCompat.startForegroundService(context, intent)
    } else {
      context.startService(intent)
    }
  }

  private fun stopForeground() {
    try {
      context.stopService(Intent(context, GadgetForegroundService::class.java))
    } catch (_: Throwable) {
    }
  }

  private fun setState(state: String, activeProfileId: String?, message: String?) {
    val current = statusRef.get()
    val next = current.copy(
      state = state,
      activeProfileId = activeProfileId,
      message = message,
      keyboardWriterReady = root.isKeyboardWriterReady(),
      mouseWriterReady = root.isMouseWriterReady(),
    )
    statusRef.set(next)
    emit(next)
  }

  private fun setError(message: String) {
    val current = statusRef.get()
    val next = current.copy(
      state = "ERROR",
      message = message,
      keyboardWriterReady = root.isKeyboardWriterReady(),
      mouseWriterReady = root.isMouseWriterReady(),
    )
    statusRef.set(next)
    emit(next)
    log.logError("gadget", message)
  }

  private data class UsbSnapshot(
    val sysUsbConfig: String?,
    val sysUsbState: String?,
    val sysUsbConfigfs: String?,
    val persistSysUsbConfig: String?,
    val boundGadgetsRaw: String?,
  )

  private fun captureUsbSnapshot(): UsbSnapshot {
    fun getProp(name: String): String? {
      val r = root.exec("getprop $name 2>/dev/null || true", timeoutSec = 5)
      val v = r.stdout.lineSequence().firstOrNull()?.trim()?.trim('\r')
      return v?.takeIf { it.isNotBlank() }
    }
    val bound = root.exec(buildListBoundGadgetsScript(), timeoutSec = 8).stdout
      .lineSequence()
      .map { it.trim().trim('\r') }
      .filter { it.isNotBlank() }
      .joinToString("\n")
      .ifBlank { null }
    val snap = UsbSnapshot(
      sysUsbConfig = getProp("sys.usb.config"),
      sysUsbState = getProp("sys.usb.state"),
      sysUsbConfigfs = getProp("sys.usb.configfs"),
      persistSysUsbConfig = getProp("persist.sys.usb.config"),
      boundGadgetsRaw = bound,
    )
    log.log(
      "usb",
      "Snapshot sys.usb.config=${snap.sysUsbConfig ?: "?"} sys.usb.state=${snap.sysUsbState ?: "?"} " +
        "sys.usb.configfs=${snap.sysUsbConfigfs ?: "?"} persist.sys.usb.config=${snap.persistSysUsbConfig ?: "?"} " +
        "bound=${if (snap.boundGadgetsRaw.isNullOrBlank()) "none" else "yes"}"
    )
    return snap
  }

  private fun buildListBoundGadgetsScript(): String {
    return """
      CFGBASE="/config/usb_gadget"
      if [ ! -d "${'$'}CFGBASE" ]; then
        CFGBASE="/sys/kernel/config/usb_gadget"
      fi
      if [ ! -d "${'$'}CFGBASE" ]; then
        exit 0
      fi
      for g in "${'$'}CFGBASE"/*; do
        [ -d "${'$'}g" ] || continue
        if [ -f "${'$'}g/UDC" ]; then
          udc=${'$'}(cat "${'$'}g/UDC" 2>/dev/null | tr -d '\r')
          if [ -n "${'$'}udc" ]; then
            echo "${'$'}(basename "${'$'}g"):${'$'}udc"
          fi
        fi
      done
      exit 0
    """.trimIndent()
  }

  private fun restoreUsbSnapshotBestEffort(reason: String) {
    val prevConfig = prefs.prevSysUsbConfig?.trim()?.takeIf { it.isNotEmpty() }
    val prevConfigfs = prefs.prevSysUsbConfigfs?.trim()?.takeIf { it.isNotEmpty() }
    val prevPersist = prefs.prevPersistSysUsbConfig?.trim()?.takeIf { it.isNotEmpty() }
    val prevBound = prefs.prevBoundGadgets?.trim()?.takeIf { it.isNotEmpty() }
    if (prevConfig == null && prevConfigfs == null && prevPersist == null && prevBound == null) {
      log.log("usb", "No snapshot to restore ($reason)")
      return
    }
    log.log("usb", "Restoring USB snapshot ($reason) prevConfig=${prevConfig ?: "?"}")
    val script = buildRestoreUsbScript(prevConfig, prevConfigfs, prevPersist, prevBound)
    val r = root.exec(script, timeoutSec = 20)
    if (!r.ok) {
      log.logError("usb", "USB restore script returned exit=${r.exitCode}")
    } else {
      log.log("usb", "USB restore script completed")
    }
  }

  private fun buildRestoreUsbScript(
    prevConfig: String?,
    prevConfigfs: String?,
    prevPersist: String?,
    prevBoundRaw: String?
  ): String {
    val cfg = prevConfig ?: ""
    val cfgfs = prevConfigfs ?: ""
    val pcfg = prevPersist ?: ""
    val boundLines = (prevBoundRaw ?: "")
      .lineSequence()
      .map { it.trim() }
      .filter { it.isNotEmpty() }
      .toList()
    val rebindBlock = if (boundLines.isNotEmpty()) {
      val entries = boundLines.joinToString("\n") { it }
      """
        CFGBASE="/config/usb_gadget"
        if [ ! -d "${'$'}CFGBASE" ]; then
          CFGBASE="/sys/kernel/config/usb_gadget"
        fi
        if [ -d "${'$'}CFGBASE" ]; then
          while IFS= read -r line; do
            g=${'$'}(echo "${'$'}line" | cut -d: -f1)
            u=${'$'}(echo "${'$'}line" | cut -d: -f2-)
            if [ -n "${'$'}g" ] && [ -n "${'$'}u" ] && [ -f "${'$'}CFGBASE/${'$'}g/UDC" ]; then
              (echo "${'$'}u" > "${'$'}CFGBASE/${'$'}g/UDC") 2>/dev/null || true
            fi
          done <<'EOF_BOUND'
        $entries
        EOF_BOUND
        fi
      """.trimIndent()
    } else {
      "true"
    }
    return """
      set -e

      PREV_CFG=${shQuote(cfg)}
      PREV_CFGFS=${shQuote(cfgfs)}
      PREV_PERSIST=${shQuote(pcfg)}

      if [ -n "${'$'}PREV_CFGFS" ]; then
        setprop sys.usb.configfs "${'$'}PREV_CFGFS" 2>/dev/null || true
      fi

      if [ -n "${'$'}PREV_PERSIST" ]; then
        setprop persist.sys.usb.config "${'$'}PREV_PERSIST" 2>/dev/null || true
      fi

      if [ -n "${'$'}PREV_CFG" ]; then
        setprop sys.usb.config none 2>/dev/null || true
        sleep 0.1
        setprop sys.usb.config "${'$'}PREV_CFG" 2>/dev/null || true

        i=0
        while [ ${'$'}i -lt 80 ]; do
          cur=${'$'}(getprop sys.usb.state 2>/dev/null | tr -d '\r')
          if [ "${'$'}cur" = "${'$'}PREV_CFG" ]; then
            break
          fi
          sleep 0.1
          i=${'$'}((i+1))
        done
      fi

      $rebindBlock

      exit 0
    """.trimIndent()
  }

  private fun kernelVersionBase(unameR: String): String {
    val trimmed = unameR.trim()
    if (trimmed.isEmpty()) return "Unknown"
    val first = trimmed.split(Regex("[\\s\\-\\+]")).firstOrNull()?.trim()
    return first?.takeIf { it.isNotEmpty() } ?: trimmed
  }

  private fun readKernelUnameR(): String? {
    val r = root.exec("uname -r 2>/dev/null || true", timeoutSec = 5)
    val v = r.stdout.lineSequence().firstOrNull()?.trim()?.trim('\r')
    return v?.takeIf { it.isNotBlank() }
  }

  private fun readKernelConfigConfigfsLines(): String? {
    val script = """
      if [ -r /proc/config.gz ]; then
        ( toybox gzip -dc /proc/config.gz 2>/dev/null \
          || toybox gunzip -c /proc/config.gz 2>/dev/null \
          || gunzip -c /proc/config.gz 2>/dev/null \
          || busybox zcat /proc/config.gz 2>/dev/null \
          || zcat /proc/config.gz 2>/dev/null ) \
        | grep -i configfs \
        | sed 's/^# //; s/ is not set/=NOT_SET/' || true
        exit 0
      fi

      CFG="/boot/config-`uname -r 2>/dev/null`"
      if [ -r "${'$'}CFG" ]; then
        cat "${'$'}CFG" 2>/dev/null \
        | grep -i configfs \
        | sed 's/^# //; s/ is not set/=NOT_SET/' || true
        exit 0
      fi

      echo "__NO_KERNEL_CONFIG__"
    """.trimIndent()
    val r = root.exec(script, timeoutSec = 15)
    val out = r.stdout.trim()
    if (out.isEmpty()) return null
    if (out.contains("__NO_KERNEL_CONFIG__")) return null
    return out
  }

  private fun readKernelConfigFlags(keys: List<String>): Map<String, String> {
    val uniqueKeys = LinkedHashSet(keys)
    val out = LinkedHashMap<String, String>()
    for (k in uniqueKeys) out[k] = "Unknown"
    val raw = readKernelConfigConfigfsLines() ?: return out
    val parsed = HashMap<String, String>(512)
    for (line in raw.lineSequence()) {
      val l = line.trim()
      if (l.isEmpty()) continue
      val idx = l.indexOf('=')
      if (idx <= 0) continue
      val name = l.substring(0, idx).trim()
      val value = l.substring(idx + 1).trim()
      if (name.startsWith("CONFIG_")) parsed[name] = value
    }
    for (k in uniqueKeys) {
      val v = parsed[k] ?: continue
      out[k] = when (v.lowercase(Locale.US)) {
        "y" -> "Yes"
        "m" -> "Module"
        "not_set" -> "Not set"
        "n" -> "No"
        else -> v
      }
    }
    return out
  }

  private fun collectKernelConfigInfo(): Map<String, Any?> {
    val keys = listOf(
      "CONFIG_CONFIGFS_FS",
      "CONFIG_IIO_CONFIGFS",
      "CONFIG_PCI_ENDPOINT_CONFIGFS",
      "CONFIG_USB_CONFIGFS",
      "CONFIG_USB_CONFIGFS_ACM",
      "CONFIG_USB_CONFIGFS_ECM",
      "CONFIG_USB_CONFIGFS_ECM_SUBSET",
      "CONFIG_USB_CONFIGFS_EEM",
      "CONFIG_USB_CONFIGFS_F_ACC",
      "CONFIG_USB_CONFIGFS_F_AUDIO_SRC",
      "CONFIG_USB_CONFIGFS_F_CCID",
      "CONFIG_USB_CONFIGFS_F_CDEV",
      "CONFIG_USB_CONFIGFS_F_DIAG",
      "CONFIG_USB_CONFIGFS_F_EMS",
      "CONFIG_USB_CONFIGFS_F_FS",
      "CONFIG_USB_CONFIGFS_F_GSI",
      "CONFIG_USB_CONFIGFS_F_HID",
      "CONFIG_USB_CONFIGFS_F_LB_SS",
      "CONFIG_USB_CONFIGFS_F_MIDI",
      "CONFIG_USB_CONFIGFS_F_PRINTER",
      "CONFIG_USB_CONFIGFS_F_QDSS",
      "CONFIG_USB_CONFIGFS_F_UAC1",
      "CONFIG_USB_CONFIGFS_F_UAC1_LEGACY",
      "CONFIG_USB_CONFIGFS_F_UAC2",
      "CONFIG_USB_CONFIGFS_F_UVC",
      "CONFIG_USB_CONFIGFS_MASS_STORAGE",
      "CONFIG_USB_CONFIGFS_NCM",
      "CONFIG_USB_CONFIGFS_OBEX",
      "CONFIG_USB_CONFIGFS_RNDIS",
      "CONFIG_USB_CONFIGFS_SERIAL",
      "CONFIG_USB_CONFIGFS_UEVENT",
    )
    val unameR = readKernelUnameR()
    val kver = if (!unameR.isNullOrBlank()) kernelVersionBase(unameR) else "Unknown"
    val flags = if (checkRoot()) readKernelConfigFlags(keys) else keys.associateWith { "Unknown" }
    val out = LinkedHashMap<String, Any?>()
    out["KERNEL_VERSION"] = kver
    for ((k, v) in flags) out[k] = v
    return out
  }

  fun getDiagnostics(): Map<String, Any?> {
    val out = LinkedHashMap<String, Any?>()
    out["timestampMs"] = System.currentTimeMillis()
    out["status"] = getStatusSnapshot().toMap()
    try {
      out["kernelConfig"] = collectKernelConfigInfo()
    } catch (t: Throwable) {
      out["kernelConfigError"] = t.toString()
    }
    try {
      val raw = readKernelConfigConfigfsLines()
      out["kernelConfigRawFirstLines"] = raw?.lineSequence()?.take(60)?.toList() ?: emptyList<String>()
    } catch (t: Throwable) {
      out["kernelConfigRawError"] = t.toString()
    }
    try {
      out["rootId"] = root.exec("id").stdout.trim()
    } catch (t: Throwable) {
      out["rootIdError"] = t.toString()
    }
    try {
      out["sysUsbController"] = root.exec("getprop sys.usb.controller").stdout.trim()
    } catch (t: Throwable) {
      out["sysUsbControllerError"] = t.toString()
    }
    try {
      out["udcList"] = listUdcs()
    } catch (t: Throwable) {
      out["udcListError"] = t.toString()
    }
    try {
      val bases = listOf("/config/usb_gadget", "/sys/kernel/config/usb_gadget")
      val existing = ArrayList<String>()
      for (b in bases) {
        val ec = root.exec("test -d $b").exitCode
        if (ec == 0) existing.add(b)
      }
      out["configfsBases"] = existing
      out["configfsMount"] = root.exec("mount | grep -i configfs || true").stdout.trim()
    } catch (t: Throwable) {
      out["configfsError"] = t.toString()
    }
    try {
      out["paths"] = mapOf(
        "config" to root.exec("ls -ld /config 2>/dev/null || echo MISSING").stdout.trim(),
        "sysKernelConfig" to root.exec("ls -ld /sys/kernel/config 2>/dev/null || echo MISSING").stdout.trim(),
        "sysClassUdc" to root.exec("ls -ld /sys/class/udc 2>/dev/null || echo MISSING").stdout.trim(),
      )
    } catch (t: Throwable) {
      out["pathsError"] = t.toString()
    }
    try {
      val gadgets = root.exec("ls -1 /config/usb_gadget 2>/dev/null || true").stdout
        .split("\n")
        .map { it.trim() }
        .filter { it.isNotEmpty() }
      out["existingGadgetsInConfig"] = gadgets
    } catch (t: Throwable) {
      out["existingGadgetsError"] = t.toString()
    }
    try {
      val current = statusRef.get()
      out["currentUdcState"] = current.udcState ?: "not_polling"
      out["deviceConnected"] = current.deviceConnected
    } catch (t: Throwable) {
      out["udcStateError"] = t.toString()
    }
    return out
  }

  private fun emit(status: Status) {
    val map = status.toMap()
    main.post {
      try {
        sinkRef.get()?.success(map)
      } catch (_: Throwable) {
      }
    }
  }

  private fun normalizeTypingSpeedFactor(value: Double): Double {
    val v = if (value.isFinite()) value else 1.0
    return v.coerceIn(minTypingSpeedFactor, maxTypingSpeedFactor)
  }

  private fun scaledInterKeyDelayUs(): Int {
    val f = normalizeTypingSpeedFactor(typingSpeedFactor)
    val v = (baseInterKeyDelayUs.toDouble() * f).roundToInt()
    return v.coerceIn(minInterKeyDelayUs, maxInterKeyDelayUs)
  }

  private fun scaledDownHoldUs(requestUs: Int): Int {
    val f = normalizeTypingSpeedFactor(typingSpeedFactor)
    val v = (requestUs.toDouble() * f).roundToInt()
    return v.coerceIn(minKeyDownHoldUs, maxKeyDownHoldUs)
  }

  private fun estimateReportOverheadUs(): Int {
    return if (prefs.riskyFastMode) 800 else 1500
  }

  private fun effectiveDelayUsForEstimate(us: Int): Int {
    val floorUs = calibratedDelayFloorUs ?: run {
      val v = calibrateDelayFloorUs()
      calibratedDelayFloorUs = v
      v
    }
    return maxOf(us, floorUs)
  }

  private fun supportsUsleep(): Boolean {
    val cached = cachedUsleepSupport
    if (cached != null) return cached
    val script = """
      if command -v toybox >/dev/null 2>&1 && toybox usleep 1 >/dev/null 2>&1; then
        exit 0
      fi
      if command -v usleep >/dev/null 2>&1; then
        exit 0
      fi
      if command -v busybox >/dev/null 2>&1 && busybox usleep 1 >/dev/null 2>&1; then
        exit 0
      fi
      exit 1
    """.trimIndent()
    val ok = root.execDirect(script, timeoutSec = 3).ok
    cachedUsleepSupport = ok
    return ok
  }

  private fun calibrateDelayFloorUs(): Int {
    val iterations = 100
    val script = """
      USLP=""
      if command -v toybox >/dev/null 2>&1 && toybox usleep 1 >/dev/null 2>&1; then
        USLP="toybox usleep"
      elif command -v usleep >/dev/null 2>&1; then
        USLP="usleep"
      elif command -v busybox >/dev/null 2>&1 && busybox usleep 1 >/dev/null 2>&1; then
        USLP="busybox usleep"
      fi
      i=0
      while [ ${'$'}i -lt $iterations ]; do
        if [ -n "${'$'}USLP" ]; then
          ${'$'}USLP 1000
        else
          sleep 0.01
        fi
        i=${'$'}((i+1))
      done
      echo "USLP=${'$'}USLP"
    """.trimIndent()
    val started = System.currentTimeMillis()
    val r = root.execDirect(script, timeoutSec = 6)
    val elapsedMs = (System.currentTimeMillis() - started).coerceAtLeast(1L)
    if (!r.ok) return 10_000
    val perIterMs = elapsedMs.toDouble() / iterations.toDouble()
    val floorUs = (perIterMs * 1000.0).roundToInt()
    val clamped = floorUs.coerceIn(1000, 50_000)
    log.log("kbd", "Estimated delay floor ${clamped}us (per-iter ${"%.2f".format(perIterMs)}ms)")
    return clamped
  }
}
