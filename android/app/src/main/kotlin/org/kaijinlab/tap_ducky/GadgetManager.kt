package org.kaijinlab.tap_ducky

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.util.ArrayList
import java.util.LinkedHashMap
import java.util.Locale
import java.util.concurrent.atomic.AtomicReference
import java.text.Normalizer
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class GadgetManager(
  private val context: Context,
  private val log: LogBus,
) {
  private val main = Handler(Looper.getMainLooper())
  private val root = RootShell(log)
  private val hostOsObserver = UsbHostOsObserver(root, log)
  private val prefs = Prefs(context)
  private val usbDataMarker = java.io.File(context.filesDir, "resume-usb-data")
  private val udcNameRegex = Regex("^[A-Za-z0-9._-]+$")

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
  private val PREPARED_LAYOUT_VERSION = 2
  private var keyboardMapper: KeyboardMapper = KeyboardMapper(KeyboardLayout.LAYOUT_US)

  private var polling = false
  private var hostConfigurationRequestCount: Int = 0

  private val execSinkRef = AtomicReference<EventChannel.EventSink?>(null)
  private val executionLock = Any()
  private var activeExecutionId: String? = null
  private var cancelledExecutionId: String? = null
  private var buttonPrompt: DuckyButtonPrompt? = null
  private var activeKeyboardMarker: File? = null
  private val keyboardMarkerForWorker = ThreadLocal<File>()

  private var hidActiveGraceMs: Long = 1500
  private var unicodeFallbackMode: String = "warn"
  @Volatile private var cachedUsleepSupport: Boolean? = null
  @Volatile private var calibratedDelayFloorUs: Int? = null

  private var consecutiveWriteFailures = 0
  private var lastWriteFailureAtMs: Long? = null
  private var keyboardMayBeHeld = false
  private var mouseButtonsMayBeHeld = false

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
    val hostConfigurationRequestCount: Int,
    val activeRoleType: String? = null,
    val desiredArmed: Boolean = false,
    val gadgetBound: Boolean = false,
    val prepared: Boolean = false,
    val pcConnected: Boolean = false,
    val inferredHostOs: String? = null,
    val hostOsDetectionAvailable: Boolean = false,
    val hostOsDetecting: Boolean = false,
    val scriptVid: Int? = null,
    val scriptPid: Int? = null,
    val scriptAttackMode: Int? = null,
  ) {
    val isActive: Boolean get() = desiredArmed
    fun toMap(): Map<String, Any?> = mapOf(
      "rootAvailable" to rootAvailable,
      "supportAvailable" to supportAvailable,
      "udcList" to udcList,
      "state" to state,
      "isActive" to isActive,
      "desiredArmed" to desiredArmed,
      "gadgetBound" to gadgetBound,
      "prepared" to prepared,
      "activeProfileId" to activeProfileId,
      "activeRoleType" to activeRoleType,
      "message" to message,
      "keyboardWriterReady" to keyboardWriterReady,
      "mouseWriterReady" to mouseWriterReady,
      "deviceConnected" to deviceConnected,
      "pcConnected" to pcConnected,
      "inferredHostOs" to inferredHostOs,
      "hostOsDetectionAvailable" to hostOsDetectionAvailable,
      "hostOsDetecting" to hostOsDetecting,
      "udcState" to udcState,
      "hostConfigurationRequestCount" to hostConfigurationRequestCount,
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
      hostConfigurationRequestCount = 0,
    )
  )

  @Volatile private var prepareAttempted = false
  @Volatile private var deferredPreparationUdc: String? = null
  @Volatile private var preparing = false
  @Volatile private var desiredProfile: Configfs.ParsedProfile? = null
  private var restoreAttempted = false
  private var restoreDeferred = false
  private val lifecycleExecutor = java.util.concurrent.Executors.newSingleThreadScheduledExecutor()

  private val sinkRef = AtomicReference<EventChannel.EventSink?>(null)

  init {
    lifecycleExecutor.execute { refreshAndEmitStatus() }
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
    requestExecutionCancellation(executionId?.takeUnless { it == "*" })
    emitExec(
      mapOf(
        "type" to "cancel_requested",
        "executionId" to (executionId ?: "*"),
        "timestampMs" to System.currentTimeMillis(),
      )
    )
  }

  internal fun beginButtonPrompt(executionId: String, waitMs: Long): DuckyButtonPrompt = synchronized(executionLock) {
    check(activeExecutionId == executionId && buttonPrompt == null)
    DuckyButtonPrompt(
      executionId,
      java.util.UUID.randomUUID().toString(),
      android.os.SystemClock.elapsedRealtime() + waitMs,
    ).also { buttonPrompt = it }
  }

  fun confirmButtonPrompt(executionId: String, promptId: String): Boolean = synchronized(executionLock) {
    if (activeExecutionId != executionId || cancelledExecutionId == executionId) return@synchronized false
    buttonPrompt?.confirm(executionId, promptId, android.os.SystemClock.elapsedRealtime()) == true
  }

  internal fun buttonPromptConfirmedAt(promptId: String): Long? = synchronized(executionLock) {
    buttonPrompt?.takeIf { it.id == promptId }?.confirmedAtMs
  }

  internal fun endButtonPrompt(promptId: String) = synchronized(executionLock) {
    if (buttonPrompt?.id == promptId) {
      buttonPrompt = null
    }
  }

  private fun requestExecutionCancellation(executionId: String? = null) {
    synchronized(executionLock) {
      val active = activeExecutionId
      if (active == null || executionId == null || executionId == active) {
        cancelledExecutionId = executionId ?: active
        activeKeyboardMarker?.let { marker ->
          if (!marker.delete() && marker.exists()) {
            log.logError("kbd", "Could not cancel the active keyboard batch")
          }
        }
      }
    }
  }

  fun getStatusSnapshot(): Status {
    return refreshAndEmitStatus()
  }

  @Synchronized
  fun refreshAndEmitStatus(): Status {
    val current = statusRef.get()
    val rootOk = checkRoot()
    if (rootOk) resumeUsbDataIfNeeded()
    val configfsOk = rootOk && ensureConfigfsAvailable()
    val udcs = if (rootOk) listUdcs() else emptyList()
    val supportOk = rootOk && configfsOk && udcs.isNotEmpty()

    if (prefs.armed && supportOk) {
      hostOsObserver.start(udcs.filterNot { it.startsWith("dummy") }.singleOrNull())
    } else {
      hostOsObserver.stop()
    }
    val next = readPhysicalStatus(current.copy(
      rootAvailable = rootOk,
      supportAvailable = supportOk,
      udcList = udcs,
    ))
    statusRef.set(next)
    emit(next)
    if (supportOk && !polling) startUdcPolling()
    return next
  }

  private fun readPhysicalStatus(current: Status): Status {
    val dir = prefs.pendingGadgetDir.takeIf { prefs.pendingSharedGadget }
      ?: prefs.activeGadgetDir.takeIf { prefs.preparedVersion == PREPARED_LAYOUT_VERSION }
    val session = when {
      current.supportAvailable && dir != null -> probeSavedSession(dir)
      dir == null && !prefs.armed && !prefs.pendingSharedGadget -> SessionProbe.Unbound
      else -> SessionProbe.Unknown
    }
    val probe = session as? SessionProbe.Bound
    val udcState = probe?.udcState ?: if (current.supportAvailable) pollUdcState() else null
    val connected = probe?.udcState == "configured" && probe.devicesReady
    val pcConnected = when (udcState) {
      "default", "addressed", "configured", "suspended" -> true
      "not attached" -> false
      else -> context.registerReceiver(null, IntentFilter("android.hardware.usb.action.USB_STATE"))
        ?.getBooleanExtra("connected", false) == true
    }
    if (probe != null && dir != null && (prefs.activeGadgetDir != dir ||
      prefs.activeRoleType != probe.role || prefs.activeKeyboardDev != probe.keyboard ||
      prefs.activeMouseDev != probe.mouse || prefs.activeMediaDev != probe.media)
    ) {
      prefs.setActive(
        prefs.activeProfileId.takeIf { prefs.activeGadgetDir == dir }
          ?: prefs.pendingProfileId ?: "recovered:$dir", probe.role, dir,
        probe.keyboard, probe.mouse, probe.media,
      )
    }
    if (connected && !current.deviceConnected) {
      hostConfigurationRequestCount += 1
      if (!prefs.armed) releaseHeldInputBestEffort()
      log.log("udc", "TapDucky configured by host (cfgReq=$hostConfigurationRequestCount)")
    } else if (!connected && current.deviceConnected) {
      log.log("udc", "TapDucky no longer configured (state=${udcState ?: "unknown"})")
    }
    if (probe == null || udcState == "not attached") {
      keyboardMayBeHeld = false
      mouseButtonsMayBeHeld = false
    }
    if (current.gadgetBound && probe == null) prepareAttempted = false

    val armed = prefs.armed
    val fingerprint = if (armed && connected) hostOsObserver.read() else null
    val error = armed && probe == null && current.state == "ERROR"
    val state = when {
      !armed && prefs.pendingSharedGadget -> "RESTORING"
      !armed -> "IDLE"
      error -> "ERROR"
      probe != null -> "ACTIVE"
      else -> "ARMING"
    }
    return current.copy(
      state = state,
      activeProfileId = prefs.activeProfileId.takeIf { probe != null },
      message = current.message.takeIf {
        error || (armed && probe == null) || (!armed && prefs.pendingSharedGadget)
      },
      keyboardWriterReady = armed && connected && probe?.keyboard != null,
      mouseWriterReady = armed && connected && probe?.mouse != null,
      deviceConnected = connected,
      pcConnected = pcConnected,
      inferredHostOs = fingerprint?.os,
      hostOsDetectionAvailable = armed && hostOsObserver.available,
      hostOsDetecting = fingerprint?.detecting == true,
      scriptVid = probe?.vid,
      scriptPid = probe?.pid,
      scriptAttackMode = session.scriptAttackMode,
      udcState = udcState,
      hostConfigurationRequestCount = hostConfigurationRequestCount,
      activeRoleType = probe?.role,
      desiredArmed = armed,
      gadgetBound = probe != null,
      prepared = probe != null,
    )
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

  @Synchronized
  fun activate(profileMap: Map<*, *>) {
    val profile = parseProfile(profileMap)
    desiredProfile = profile
    prefs.armed = true
    prefs.desiredRole = profile.roleType
    prepareAttempted = false

    if (!checkRoot()) {
      setError("Root not available (su denied).")
      return
    }
    if (!checkSupport()) {
      setError("USB gadget support not detected (configfs/UDC missing).")
      return
    }

    val refreshed = refreshAndEmitStatus()
    if (refreshed.gadgetBound) {
      setState("ACTIVE", prefs.activeProfileId ?: profile.id, null)
      startForeground("TapDucky USB ready")
      log.log("gadget", "Armed logical session; prepared USB gadget stays bound")
      return
    }

    prepareStock(profile, allowConnected = true)
  }

  private fun setArming(message: String?) {
    val current = statusRef.get()
    val next = current.copy(
      state = "ARMING",
      message = message,
      desiredArmed = true,
      gadgetBound = current.gadgetBound,
      prepared = current.prepared,
    )
    statusRef.set(next)
    emit(next)
  }

  private fun defaultProfile(roleRaw: String?): Configfs.ParsedProfile {
    val role = roleRaw?.trim()?.lowercase(Locale.US)?.takeIf {
      it == "keyboard" || it == "mouse" || it == "composite"
    } ?: "composite"
    val product = when (role) {
      "keyboard" -> "TapDucky Keyboard"
      "mouse" -> "TapDucky Mouse"
      else -> "TapDucky Composite"
    }
    return Configfs.ParsedProfile(
      id = "deferred_${role}_${System.currentTimeMillis()}",
      name = product,
      roleType = role,
      preferredUdc = null,
      manufacturer = "TapDucky",
      product = product,
      serialNumber = "TD-${System.currentTimeMillis()}",
      vendorId = 0x1d6b,
      productId = 0x0104,
      maxPowerMa = 250,
    )
  }

  @Synchronized
  private fun prepareStock(profile: Configfs.ParsedProfile, allowConnected: Boolean = false) {
    if (preparing || !prefs.armed) return
    setArming(null)
    preparing = true
    prepareAttempted = true
    deferredPreparationUdc = null
    try {
      if (!checkRoot()) {
        setError("Root not available (su denied).")
        return
      }
      if (!checkSupport()) {
        setError("USB gadget support not detected (configfs/UDC missing).")
        return
      }

      val inventory = root.exec(Configfs.buildStockInventoryScript(), timeoutSec = 8)
      if (!inventory.ok) {
        setError("Could not read Android's USB gadget layout.")
        return
      }
      val pendingDir = prefs.pendingGadgetDir.takeIf { prefs.pendingSharedGadget }
      val (stockDir, stockUdc, currentUdc) = try {
        StockUsbDiscovery.select(inventory.stdout, profile.preferredUdc, pendingDir, prefs.sharedController)
      } catch (e: IllegalArgumentException) {
        setError(e.message ?: "Could not identify Android's USB gadget.")
        return
      }
      val originalUdc = prefs.originalStockUdc.takeIf { pendingDir != null } ?: currentUdc
      val stockLayout = prefs.originalStockLayout.takeIf { pendingDir != null } ?: run {
        val snapshot = root.exec(Configfs.buildReadStockLayoutScript(stockDir), timeoutSec = 8)
        if (!snapshot.ok || !snapshot.stdout.startsWith("mode=") ||
          snapshot.stdout.lineSequence().none { it == "UDC=$currentUdc" }
        ) {
          setError("Could not save Android's current USB layout.")
          return
        }
        snapshot.stdout.trimEnd('\n')
      }
      log.log("usb", "Preparing HID interfaces on stock gadget $stockDir")
      if (!prefs.setSharedGadgetDir(stockDir, profile.id, stockUdc, originalUdc, stockLayout)) {
        setError("Could not save USB preparation state.")
        return
      }
      val r = changeStockUsb(stockUdc, Configfs.buildAttachToStockScript(
        profile, stockDir, stockUdc, currentUdc, usbDataMarker.path.takeIf { allowConnected },
      ))
      if (pendingDir == null && r.exitCode == Configfs.STOCK_BINDING_CHANGED) {
        prefs.clearSessionArtifacts()
      }
      if (r.exitCode == Configfs.HOST_ATTACHED_REFUSED || r.exitCode == Configfs.SETUP_NOT_STARTED) {
        deferredPreparationUdc = stockUdc
        setArming("USB interface setup will start after you unplug the cable.")
        log.log("usb", "USB preparation deferred: ${r.stderr.trim()}")
        return
      }
      if (r.exitCode == Configfs.USB_DATA_RESTORE_FAILED) {
        setError("Android did not resume USB data. Reopen TapDucky to retry restoring it.")
        return
      }
      if (!r.ok) {
        val detail = r.stderr.trim().ifEmpty { r.stdout.trim() }
        setError("USB preparation failed (exit=${r.exitCode}). $detail")
        return
      }

      val firstHid = resolveHidDevice(r.stdout, "hid.usb0")
      val role = profile.roleType.lowercase(Locale.US)
      val kbdDev = firstHid.takeUnless { role == "mouse" }
      val mouseDev = when (role) {
        "mouse" -> firstHid
        "keyboard" -> null
        else -> resolveHidDevice(r.stdout, "hid.usb1")
      }
      val mediaDev = when (role) {
        "keyboard" -> null
        else -> mouseDev
      }

      prefs.setActive(profile.id, profile.roleType, stockDir, kbdDev, mouseDev, mediaDev)
      prefs.preparedVersion = PREPARED_LAYOUT_VERSION
      refreshAndEmitStatus()
      startForeground("TapDucky USB ready")
      log.log("gadget", "Prepared HID profile ${profile.id} (${profile.roleType})")
    } finally {
      preparing = false
    }
  }

  private fun prepareFromPoll() {
    if (preparing || !prefs.armed) return
    if (statusRef.get().gadgetBound) return
    val profile = desiredProfile ?: defaultProfile(prefs.desiredRole)
    desiredProfile = profile
    log.log("usb", "Preparing the armed USB session")
    prepareStock(profile)
  }

  private fun resolveHidDevice(stdout: String, function: String): String? {
    val dev = stdout.lineSequence()
      .firstOrNull { it.startsWith("$function=") }
      ?.substringAfter('=')?.trim()
    return hidDevicePath(dev)
  }

  private fun hidDevicePath(dev: String?): String? =
    dev?.takeIf { it.matches(Regex("[0-9]+:[0-9]+")) }
      ?.substringAfter(':')?.toIntOrNull()?.let { "/dev/hidg$it" }

  fun retryOpenHidWriters() {
    refreshAndEmitStatus()
  }

  @Synchronized
  fun deactivate() {
    prefs.armed = false
    requestExecutionCancellation()
    val current = statusRef.get()
    val restoring = prefs.pendingSharedGadget
    val next = current.copy(
      desiredArmed = false,
      keyboardWriterReady = false,
      mouseWriterReady = false,
      inferredHostOs = null,
      hostOsDetectionAvailable = false,
      hostOsDetecting = false,
      state = if (restoring) "RESTORING" else "IDLE",
      message = if (restoring) "Restoring the original USB configuration…" else null,
    )
    statusRef.set(next)
    emit(next)
    releaseHeldInputBestEffort()
    try {
      restoreStockUsb()
    } finally {
      hostOsObserver.stop()
    }
  }

  private fun changeStockUsb(udc: String, operation: String): RootShell.ExecResult = root.exec(
    Configfs.buildStockUsbTransaction(udc, operation), timeoutSec = 45,
  )

  private fun resumeUsbDataIfNeeded() {
    if (usbDataMarker.exists()) {
      val result = root.exec(Configfs.buildResumeUsbDataScript(usbDataMarker.path), timeoutSec = 15)
      if (!result.ok) log.logError("usb", "Could not resume Android USB data: ${result.stderr.trim()}")
    }
  }

  private fun restoreStockUsb() {
    val dir = prefs.pendingGadgetDir?.takeIf { prefs.pendingSharedGadget } ?: return
    if (prefs.armed) return
    restoreAttempted = true
    restoreDeferred = false
    val udc = prefs.sharedController ?: readActiveUdcName() ?: readAnyUdcName()
    val result = udc?.let {
      val original = prefs.originalStockUdc ?: it
      val restored = changeStockUsb(it, Configfs.buildRestoreStockScript(dir, original, usbDataMarker.path))
      val layout = prefs.originalStockLayout
      if (restored.ok && layout != null) {
        changeStockUsb(udc, Configfs.buildVerifyStockLayoutScript(dir, layout, usbDataMarker.path))
      } else {
        restored
      }
    }
    if (result?.ok == true) {
      prefs.clearSessionArtifacts()
      stopForeground()
      log.log("usb", "Restored the original stock USB configuration")
    } else {
      restoreDeferred = result == null || result.exitCode == Configfs.HOST_ATTACHED_REFUSED
      val detail = if (restoreDeferred) {
        "USB restoration will finish after you unplug the cable."
      } else {
        "USB restoration incomplete (exit=${result?.exitCode}). ${result?.stderr?.trim().orEmpty()}"
      }
      setState("RESTORING", null, detail)
      log.logError("usb", detail)
    }
    refreshAndEmitStatus()
  }

  fun panicStop() {
    // Emergency brake for reports only. It must never touch the UDC or the
    // stock USB configuration; the session stays armed until the user disarms.
    requestExecutionCancellation()
    releaseHeldInputBestEffort()
    log.log("usb", "Panic stop requested")
  }

  private fun readActiveUdcName(): String? {
    val dir = prefs.activeGadgetDir ?: prefs.pendingGadgetDir ?: return null
    if (!dir.matches(Regex("[A-Za-z0-9._-]+"))) return null
    for (base in listOf("/config/usb_gadget", "/sys/kernel/config/usb_gadget")) {
      val name = root.exec(
        "cat $base/$dir/UDC 2>/dev/null || true",
        timeoutSec = 3,
      ).stdout.lineSequence().firstOrNull()?.trim()?.trim('\r') ?: continue
      if (name.isNotBlank() && udcNameRegex.matches(name)) return name
    }
    return null
  }

  private fun readAnyUdcName(): String? {
    val prop = root.exec("getprop sys.usb.controller 2>/dev/null || true", timeoutSec = 3)
      .stdout.lineSequence().firstOrNull()?.trim()?.trim('\r')
    val list = root.exec("ls -1 /sys/class/udc 2>/dev/null || true", timeoutSec = 3).stdout
    val controllers = list.lineSequence()
      .map { it.trim().trim('\r') }
      .filter { udcNameRegex.matches(it) && !it.startsWith("dummy_udc") }
      .toList()
    return controllers.firstOrNull { it == prop } ?: controllers.firstOrNull()
  }

  /**
   * null means "cannot prove the host is detached". Callers must treat null
   * as unsafe and avoid touching the UDC or USB properties.
   */
  private fun hostAttachedNow(udcState: String? = pollUdcState()): Boolean? {
    val usb = context.registerReceiver(null, IntentFilter("android.hardware.usb.action.USB_STATE"))
    if (usb?.getBooleanExtra("connected", false) == true) return true
    val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
    if ((battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) and
      BatteryManager.BATTERY_PLUGGED_USB != 0
    ) return true
    return udcState?.let { it != "not attached" }
  }

  fun testMouseMove(dx: Int, dy: Int, wheel: Int, buttons: Int) {
    sendMouseReport(buttons, dx, dy, wheel)
    log.log("test", "Mouse report dx=$dx dy=$dy wheel=$wheel buttons=$buttons")
  }

  internal fun sendMouseReport(buttons: Int, dx: Int, dy: Int, wheel: Int) {
    requireReportsAllowed()
    val path = prefs.activeMouseDev ?: throw IllegalStateException("Mouse HID device not available")
    val report = byteArrayOf(
      0x01,
      (buttons and 0xFF).toByte(),
      (dx.coerceIn(-127, 127) and 0xFF).toByte(),
      (dy.coerceIn(-127, 127) and 0xFF).toByte(),
      (wheel.coerceIn(-127, 127) and 0xFF).toByte(),
    )
    writeMouseReport(path, report)
  }

  fun testKeyboardKey(keyLabel: String) {
    requireReportsAllowed()
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
    log.log("test", "Keyboard test sent (${trimmed.length} chars)")
  }

  fun typeString(
    text: String,
    delayMs: Int = 0,
    extraModifiers: Int = 0,
    extraKeys: List<Int> = emptyList(),
    shouldCancel: (() -> Boolean)? = null,
  ) {
    requireReportsAllowed()
    val path = prefs.activeKeyboardDev ?: throw IllegalStateException("Keyboard HID device not available")
    if (delayMs > 0) {
      typeTextWithDelay(path, text, delayMs, extraModifiers, extraKeys, shouldCancel)
    } else {
      typeText(path, text, extraModifiers, extraKeys, shouldCancel)
    }
    log.log("type", "String sent (len=${text.length}, delay=${delayMs}ms per char)")
  }

  private fun typeTextWithDelay(
    path: String,
    text: String,
    delayMs: Int,
    extraModifiers: Int,
    extraKeys: List<Int>,
    shouldCancel: (() -> Boolean)?,
  ) {
    val interUs = scaledInterKeyDelayUs()
    val downUs = scaledDownHoldUs(baseKeyDownHoldUs)
    for (ch in text) {
      if (shouldCancel?.invoke() == true) return
      val stroke = keyboardMapper.getStrokeForChar(ch)
      if (stroke != null) {
        val reports = ArrayList<ByteArray>(5)
        reports.add(keyboardReport(extraModifiers, extraKeys))
        addStrokeReports(reports, stroke, extraModifiers, extraKeys)
        writeKeyboardReportsWithDelays(
          path,
          reports = reports,
          delaysUs = strokeDelays(reports.size, interUs, downUs)
        )
        if (delayMs > 0 && !sleepCancellable(delayMs.toLong(), shouldCancel)) return
      } else {
        handleUnsupportedChar(
          path,
          ch,
          delayMs,
          withPerCharDelay = true,
          extraModifiers = extraModifiers,
          extraKeys = extraKeys,
          shouldCancel = shouldCancel,
        )
      }
    }
  }

  fun writeKeyboardTapWithMods(
    mods: Int,
    key: Int,
    heldModifiers: Int = 0,
    extraKeys: List<Int> = emptyList(),
  ) {
    requireReportsAllowed()
    val path = prefs.activeKeyboardDev ?: throw IllegalStateException("Keyboard HID device not available")
    writeKeyboardTap(
      path,
      mods = mods,
      key = key,
      downHoldUs = scaledDownHoldUs(baseKeyDownHoldUs),
      heldModifiers = heldModifiers,
      extraKeys = extraKeys,
    )
    log.log("test", "Keyboard mods=0x${Integer.toHexString(mods)} key=0x${Integer.toHexString(key)}")
  }

  fun testCtrlAltDel() {
    requireReportsAllowed()
    val path = prefs.activeKeyboardDev ?: throw IllegalStateException("Keyboard HID device not available")
    val mods = 0x01 or 0x04
    val del = HidSpec.keyCodeFor("DELETE") ?: 0x4C
    writeKeyboardTap(path, mods = mods, key = del, downHoldUs = scaledDownHoldUs(12000))
    log.log("test", "Ctrl+Alt+Del sent")
  }

  fun sendMediaKey(code: String): Boolean {
    if (!prefs.armed || !statusRef.get().gadgetBound) return false
    val usage = mediaUsage(code) ?: return false
    if (!waitForActive(hidActiveGraceMs)) return false
    val path = prefs.activeMediaDev ?: return false
    val press = byteArrayOf(
      0x02,
      (usage and 0xFF).toByte(),
      ((usage shr 8) and 0xFF).toByte(),
    )
    val release = byteArrayOf(0x02, 0x00, 0x00)
    if (!writeHidReport(path, press)) return false
    Thread.sleep(25)
    if (!writeHidReport(path, release)) return false
    log.log("media", "Media key $code sent (usage=0x${Integer.toHexString(usage)})")
    return true
  }

  private fun mediaUsage(code: String): Int? = when (code.uppercase(Locale.US)) {
    "PLAYPAUSE", "MEDIA_PLAYPAUSE" -> 0xCD
    "STOP", "MEDIA_STOP" -> 0xB7
    "PREVIOUSSONG", "MEDIA_PREV" -> 0xB6
    "NEXTSONG", "MEDIA_NEXT" -> 0xB5
    "VOLUMEUP", "MEDIA_VOLUMEUP" -> 0xE9
    "VOLUMEDOWN", "MEDIA_VOLUMEDOWN" -> 0xEA
    "MUTE", "MEDIA_MUTE" -> 0xE2
    else -> null
  }

  private fun writeHidReport(path: String, bytes: ByteArray): Boolean {
    val hexEsc = toPrintfEsc(bytes)
    val quotedPath = shQuote(path)
    val script = "test -c $quotedPath && printf '$hexEsc' > $quotedPath"
    var attempt = 0
    while (attempt < 3) {
      val r = root.exec(script, timeoutSec = 5)
      if (r.ok) {
        recordWriteSuccess()
        return true
      }
      recordWriteFailure()
      if (attempt < 2) {
        Thread.sleep(200L * (1L shl attempt))
        waitForActive(hidActiveGraceMs)
      }
      attempt++
    }
    return false
  }

  fun executeDuckyScript(
    script: String,
    delayMultiplier: Double = 1.0,
    executionId: String? = null,
    canShowButtonPrompt: Boolean = false,
  ) {
    val id = executionId?.takeIf { it.isNotBlank() } ?: "exec_${System.currentTimeMillis()}"
    val startedAt = android.os.SystemClock.elapsedRealtime()
    var terminalSent = false
    var reserved = false
    try {
      synchronized(executionLock) {
        check(activeExecutionId == null) { "Another script is already running" }
        val marker = File.createTempFile("keyboard-run-", ".active", context.cacheDir)
        activeKeyboardMarker = marker
        keyboardMarkerForWorker.set(marker)
        activeExecutionId = id
        if (cancelledExecutionId != id) cancelledExecutionId = null
        reserved = true
      }
      requireReportsAllowed()
      prefs.lastExecutedScript = script
      val executor = DuckyScriptExecutor(
        manager = this,
        log = log,
        delayMultiplier = delayMultiplier,
        executionId = id,
        canShowButtonPrompt = canShowButtonPrompt,
        emitExec = { event ->
          if (event["type"] == "done" || event["type"] == "error") {
            terminalSent = true
            val elapsedMs = android.os.SystemClock.elapsedRealtime() - startedAt
            emitExec(event + ("elapsedMs" to elapsedMs))
          } else {
            emitExec(event)
          }
        },
        shouldCancel = { synchronized(executionLock) { cancelledExecutionId == id } }
      )
      executor.execute(script)
    } catch (e: Exception) {
      if (!terminalSent) {
        emitExec(mapOf(
          "type" to "error",
          "executionId" to id,
          "message" to (e.message ?: "Could not start execution"),
          "lineNumber" to (e as? DuckyExpressionSyntaxException)?.lineNumber,
          "elapsedMs" to (android.os.SystemClock.elapsedRealtime() - startedAt),
        ))
      }
      throw e
    } finally {
      if (reserved) synchronized(executionLock) {
        activeKeyboardMarker?.delete()
        activeKeyboardMarker = null
        keyboardMarkerForWorker.remove()
        activeExecutionId = null
        cancelledExecutionId = null
        buttonPrompt = null
      }
    }
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
      internalVariables = DuckyScriptVariables(::readScriptUsbVariable, ::scriptKeyStroke),
      estimateTextDuration = ::estimateTypeStringDurationMs,
      estimateKeyTapDuration = ::estimateKeyTapDurationMs,
      delayMultiplier = delayMultiplier,
      onDelayClamp = { log.log("ducky", it) },
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
    val pendingController = prefs.sharedController.takeIf { prefs.pendingSharedGadget }
    val knownController = pendingController ?: deferredPreparationUdc.takeIf { prefs.armed }
    val gadgetDir = prefs.pendingGadgetDir.takeIf { prefs.pendingSharedGadget } ?: prefs.activeGadgetDir
    val script = """
      UDC_NAME=${shQuote(knownController?.takeIf { udcNameRegex.matches(it) }.orEmpty())}
      GADGET=${shQuote(gadgetDir?.takeIf { it.matches(Regex("[A-Za-z0-9._-]+")) }.orEmpty())}
      if [ -z "${'$'}UDC_NAME" ] && [ -n "${'$'}GADGET" ]; then
        for base in /config/usb_gadget /sys/kernel/config/usb_gadget; do
          UDC_NAME=${'$'}(cat "${'$'}base/${'$'}GADGET/UDC" 2>/dev/null)
          [ -z "${'$'}UDC_NAME" ] || break
        done
      fi
      if [ -n "${'$'}UDC_NAME" ]; then
        case "${'$'}UDC_NAME" in *[!A-Za-z0-9._-]*) exit 1 ;; esac
        cat "/sys/class/udc/${'$'}UDC_NAME/state" 2>/dev/null
        exit ${'$'}?
      fi
      SYS_UDC=${'$'}(getprop sys.usb.controller 2>/dev/null)
      case "${'$'}SYS_UDC" in *[!A-Za-z0-9._-]*) SYS_UDC="" ;; esac
      for candidate in "/sys/class/udc/${'$'}SYS_UDC" /sys/class/udc/*; do
        case "${'$'}{candidate##*/}" in dummy_udc*) continue ;; esac
        [ -f "${'$'}candidate/state" ] || continue
        cat "${'$'}candidate/state" 2>/dev/null
        exit ${'$'}?
      done
      exit 1
    """.trimIndent()
    val r = root.exec(script, timeoutSec = 3)
    return if (r.ok) r.stdout.trim().lowercase(Locale.US).ifEmpty { null } else null
  }

  private fun startUdcPolling() {
    polling = true
    scheduleUdcPoll(0)
  }

  private fun scheduleUdcPoll(delayMs: Long) {
    lifecycleExecutor.schedule({
      try {
        pollUsbSession()
      } catch (t: Throwable) {
        log.logError("udc", "Polling failed: ${t.message}")
      } finally {
        scheduleUdcPoll(if (statusRef.get().hostOsDetecting) 350L else 2000L)
      }
    }, delayMs, java.util.concurrent.TimeUnit.MILLISECONDS)
  }

  @Synchronized
  private fun pollUsbSession() {
    val current = statusRef.get()
    val next = readPhysicalStatus(current)
    if (next != current) {
      statusRef.set(next)
      emit(next)
    }
    if (next.supportAvailable && next.desiredArmed && !current.gadgetBound && !next.gadgetBound &&
      (!prepareAttempted || (deferredPreparationUdc != null && hostAttachedNow(next.udcState) == false))
    ) {
      prepareFromPoll()
    } else if (next.supportAvailable && !next.desiredArmed && prefs.pendingSharedGadget &&
      (!restoreAttempted || (restoreDeferred && hostAttachedNow(next.udcState) == false))
    ) {
      restoreStockUsb()
    }
  }

  private fun parseProfile(map: Map<*, *>): Configfs.ParsedProfile {
    val id = (map["id"] ?: "").toString().ifBlank { throw IllegalArgumentException("Profile id missing") }
    val name = (map["name"] ?: "Profile").toString()
    val roleType = (map["roleType"] ?: "mouse").toString()
    val tunables = (map["tunables"] as? Map<*, *>)
    val preferredUdcRaw = (tunables?.get("preferredUdc") ?: map["preferredUdc"])?.toString()?.trim()

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
    val preferredUdc = preferredUdcRaw?.takeIf { it.isNotBlank() && udcNameRegex.matches(it) }

    return Configfs.ParsedProfile(
      id = id,
      name = name,
      roleType = roleType,
      preferredUdc = preferredUdc,
      manufacturer = manufacturer,
      product = product,
      serialNumber = serial,
      vendorId = vendorId,
      productId = productId,
      maxPowerMa = maxPower,
    )
  }

  fun writeKeyboardReport(mods: Int, keys: List<Int>) {
    requireReportsAllowed()
    if (!waitForActive(hidActiveGraceMs)) {
      throw HidWriteException("HID_NOT_ACTIVE", "Gadget is not active")
    }
    val path = prefs.activeKeyboardDev ?: throw IllegalStateException("Keyboard HID device not available")
    val report = keyboardReport(mods, keys)
    writeKeyboardReportsWithDelays(path, reports = listOf(report), delaysUs = emptyList())
  }

  private fun sleepCancellable(ms: Long, shouldCancel: (() -> Boolean)?): Boolean {
    if (ms <= 0) return shouldCancel?.invoke() != true
    if (shouldCancel == null) {
      Thread.sleep(ms)
      return true
    }
    val end = android.os.SystemClock.elapsedRealtime() + ms
    while (android.os.SystemClock.elapsedRealtime() < end) {
      if (shouldCancel()) return false
      val remaining = end - android.os.SystemClock.elapsedRealtime()
      Thread.sleep(min(remaining, 50L).coerceAtLeast(1L))
    }
    return !shouldCancel()
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
    return statusRef.get().deviceConnected
  }

  internal fun readScriptUsbVariable(name: String): Int? {
    val status = statusRef.get()
    return when (name) {
      DuckyScriptHostOs.variable -> DuckyScriptHostOs.encode(
        status.inferredHostOs.takeIf { status.desiredArmed && status.deviceConnected },
      )
      "\$_CURRENT_ATTACKMODE" -> status.scriptAttackMode
      "\$_CURRENT_VID" -> status.scriptVid
      "\$_CURRENT_PID" -> status.scriptPid
      else -> null
    }
  }

  internal fun scriptKeyStroke(character: Char): KeyStroke? = keyboardMapper.getStrokeForChar(character)

  internal fun isScriptHostOsPending(): Boolean {
    val status = statusRef.get()
    return status.desiredArmed && status.hostOsDetectionAvailable &&
      (!status.deviceConnected || status.hostOsDetecting)
  }

  /**
   * Authoritative precondition for changing the USB configuration. Unknown
   * state is reported as attached so callers never touch the UDC blindly.
   */
  fun isHostAttached(): Boolean = hostAttachedNow() != false

  fun isUdcConfigured(): Boolean {
    return statusRef.get().deviceConnected
  }

  fun isKeyboardWriterReady(): Boolean = statusRef.get().keyboardWriterReady

  fun isMouseWriterReady(): Boolean = statusRef.get().mouseWriterReady

  fun isActive(): Boolean = statusRef.get().gadgetBound

  private fun requireReportsAllowed() {
    if (!prefs.armed) {
      throw HidWriteException("SESSION_DISARMED", "Session is not armed")
    }
    val status = statusRef.get()
    if (!status.gadgetBound) {
      throw HidWriteException("HID_NOT_READY", status.message ?: "USB HID is still being prepared")
    }
  }

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

  @Synchronized
  internal fun releaseHeldInputBestEffort() {
    if (!keyboardMayBeHeld && !mouseButtonsMayBeHeld) return
    try {
      val dir = prefs.activeGadgetDir ?: return
      val probe = probeSavedSession(dir) as? SessionProbe.Bound ?: return
      if (probe.udcState != "configured" || !probe.devicesReady) return
      val udc = readActiveUdcName() ?: return
      if (keyboardMayBeHeld) {
        keyboardMayBeHeld = !sendReleaseReport(udc, probe.keyboard, keyboardReport(0, emptyList()))
      }
      if (mouseButtonsMayBeHeld) {
        mouseButtonsMayBeHeld = !sendReleaseReport(udc, probe.mouse, byteArrayOf(1, 0, 0, 0, 0))
      }
      if (keyboardMayBeHeld || mouseButtonsMayBeHeld) {
        log.logError("hid", "Could not send all release reports")
      }
    } catch (t: Exception) {
      log.logError("hid", "Could not release held input: ${t.message}")
    }
  }

  private fun sendReleaseReport(udc: String, path: String?, bytes: ByteArray): Boolean {
    if (path == null) return true
    val quotedPath = shQuote(path)
    return root.exec(
      "[ \"\$(cat /sys/class/udc/$udc/state)\" = configured ] && [ -c $quotedPath ] && " +
        "printf '${toPrintfEsc(bytes)}' | dd of=$quotedPath conv=nocreat,notrunc status=none",
      timeoutSec = 2,
    ).ok
  }

  private fun writeKeyboardTap(
    path: String,
    mods: Int,
    key: Int,
    downHoldUs: Int,
    heldModifiers: Int = 0,
    extraKeys: List<Int> = emptyList(),
  ) {
    val baseline = keyboardReport(heldModifiers, extraKeys)
    val down = keyboardPressReport(mods, key, extraKeys)
    writeKeyboardReportsWithDelays(
      path,
      reports = listOf(baseline, down, baseline),
      delaysUs = listOf(scaledInterKeyDelayUs(), downHoldUs)
    )
  }

  private fun typeText(
    path: String,
    text: String,
    extraModifiers: Int = 0,
    extraKeys: List<Int> = emptyList(),
    shouldCancel: (() -> Boolean)? = null,
  ) {
    var idx = 0
    var charsSinceFlush = 0
    while (idx < text.length) {
      if (shouldCancel?.invoke() == true) return
      val end = min(text.length, idx + maxTypedCharsPerBatch)
      val chunk = text.substring(idx, end)
      typeTextChunk(path, chunk, extraModifiers, extraKeys)
      charsSinceFlush += chunk.length
      if (charsSinceFlush >= flushEveryChars) {
        if (!sleepCancellable(flushDelayMs.toLong(), shouldCancel)) return
        charsSinceFlush = 0
      }
      idx = end
    }
  }

  private fun typeTextChunk(
    path: String,
    chunk: String,
    extraModifiers: Int,
    extraKeys: List<Int>,
  ) {
    val strokes = ArrayList<KeyStroke>(chunk.length)
    for (ch in chunk) {
      val s = keyboardMapper.getStrokeForChar(ch)
      if (s != null) {
        strokes.add(s)
      } else if (addComposedUnicodeStrokes(ch, strokes)) {
        // Handled as a layout-specific dead-key accent followed by the base character.
      } else {
        addFallbackStrokes(ch, strokes)
      }
    }
    if (strokes.isEmpty()) return

    val interUs = scaledInterKeyDelayUs()
    val downUs = scaledDownHoldUs(baseKeyDownHoldUs)

    val reports = ArrayList<ByteArray>(1 + strokes.size * 4)
    reports.add(keyboardReport(extraModifiers, extraKeys))
    for (stroke in strokes) {
      addStrokeReports(reports, stroke, extraModifiers, extraKeys)
    }
    writeKeyboardReportsWithDelays(path, reports, strokeDelays(reports.size, interUs, downUs))
  }

  private fun addStrokeReports(
    reports: MutableList<ByteArray>,
    stroke: KeyStroke,
    extraModifiers: Int = 0,
    extraKeys: List<Int> = emptyList(),
  ) {
    val mods = stroke.modifiers or extraModifiers
    val baseline = keyboardReport(extraModifiers, extraKeys)
    reports.add(keyboardPressReport(mods, stroke.keyCode, extraKeys))
    reports.add(baseline)
    stroke.terminatorKeyCode?.let { key ->
      reports.add(keyboardPressReport(extraModifiers, key, extraKeys))
      reports.add(baseline)
    }
  }

  private fun strokeDelays(reportCount: Int, interUs: Int, downUs: Int): List<Int> {
    val delays = ArrayList<Int>(max(0, reportCount - 1))
    for (i in 0 until (reportCount - 1)) {
      val isDownReport = (i % 2 == 1)
      delays.add(if (isDownReport) downUs else interUs)
    }
    return delays
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

  private fun addComposedUnicodeStrokes(ch: Char, strokes: MutableList<KeyStroke>): Boolean {
    val normalized = Normalizer.normalize(ch.toString(), Normalizer.Form.NFD)
    if (normalized.length < 2) return false

    val base = normalized[0]
    val accent = combiningAccentToDeadKey(normalized.substring(1)) ?: return false
    val accentStroke = keyboardMapper.getStrokeForChar(accent) ?: return false
    val baseStroke = keyboardMapper.getStrokeForChar(base) ?: return false

    strokes.add(KeyStroke(accentStroke.modifiers, accentStroke.keyCode))
    strokes.add(baseStroke)
    return true
  }

  private fun combiningAccentToDeadKey(combiningMarks: String): Char? {
    if (combiningMarks.length != 1) return null
    return when (combiningMarks[0]) {
      '\u0300' -> '`'
      '\u0301' -> '´'
      '\u0302' -> '^'
      '\u0303' -> '~'
      '\u0306' -> '˘'
      '\u0307' -> '˙'
      '\u0308' -> '¨'
      '\u030A' -> '°'
      '\u030B' -> '˝'
      '\u030C' -> 'ˇ'
      '\u0327' -> '¸'
      '\u0328' -> '˛'
      else -> null
    }
  }

  private fun countFallbackChars(ch: Char): Int {
    return when (unicodeFallbackMode) {
      "skip", "warn" -> 0
      "ascii" -> {
        val strokes = ArrayList<KeyStroke>(2)
        if (addComposedUnicodeStrokes(ch, strokes)) {
          return strokes.size
        }

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

  private fun handleUnsupportedChar(
    path: String,
    ch: Char,
    delayMs: Int,
    withPerCharDelay: Boolean,
    extraModifiers: Int = 0,
    extraKeys: List<Int> = emptyList(),
    shouldCancel: (() -> Boolean)? = null,
  ) {
    if (shouldCancel?.invoke() == true) return
    val composedStrokes = ArrayList<KeyStroke>(2)
    if (addComposedUnicodeStrokes(ch, composedStrokes)) {
      val reports = ArrayList<ByteArray>(1 + composedStrokes.size * 4)
      reports.add(keyboardReport(extraModifiers, extraKeys))
      for (stroke in composedStrokes) {
        addStrokeReports(reports, stroke, extraModifiers, extraKeys)
      }
      writeKeyboardReportsWithDelays(
        path,
        reports = reports,
        delaysUs = strokeDelays(reports.size, scaledInterKeyDelayUs(), scaledDownHoldUs(baseKeyDownHoldUs))
      )
      if (withPerCharDelay && delayMs > 0 &&
        !sleepCancellable(delayMs.toLong(), shouldCancel)) return
      return
    }

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
          if (shouldCancel?.invoke() == true) return
          val stroke = keyboardMapper.getStrokeForChar(c)
          if (stroke != null) {
            val reports = ArrayList<ByteArray>(5)
            reports.add(keyboardReport(extraModifiers, extraKeys))
            addStrokeReports(reports, stroke, extraModifiers, extraKeys)
            writeKeyboardReportsWithDelays(
              path,
              reports = reports,
              delaysUs = strokeDelays(reports.size, scaledInterKeyDelayUs(), scaledDownHoldUs(baseKeyDownHoldUs))
            )
            if (withPerCharDelay && delayMs > 0 &&
              !sleepCancellable(delayMs.toLong(), shouldCancel)) return
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

  @Synchronized
  private fun writeKeyboardReportsWithDelays(
    path: String,
    reports: List<ByteArray>,
    delaysUs: List<Int>
  ) {
    if (reports.isEmpty()) return
    requireReportsAllowed()
    if (reports.any { report -> report.any { it != 0.toByte() } }) keyboardMayBeHeld = true
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

    val marker = keyboardMarkerForWorker.get()
    val writes = buildKeyboardBatchWrites(reports, delaysUs, marker)
    val watchdog = marker?.let(::keyboardBatchWatchdog).orEmpty()

    val script = """
      set -e
      P=${shQuote(path)}
      [ -c "${'$'}P" ]
      $usleepSnippet
      exec 3> "${'$'}P"
      $watchdog
      $writes

    """.trimIndent()

    // A failed batch can already have sent a prefix of its reports to the host.
    val result = root.exec(script, timeoutSec = 8)
    if (result.ok) {
      keyboardMayBeHeld = reports.last().any { it != 0.toByte() }
      recordWriteSuccess()
      return
    }
    if (marker != null && (result.exitCode == KEYBOARD_BATCH_CANCELLED || result.exitCode == KEYBOARD_BATCH_KILLED)) {
      val stopRequested = synchronized(executionLock) { cancelledExecutionId == activeExecutionId }
      if (stopRequested) return
    }
    recordWriteFailure()
    val detail = result.stderr.trim().ifEmpty { result.stdout.trim() }
    throw HidWriteException(
      "HID_WRITE_FAILED",
      "Failed to write keyboard reports to $path. $detail"
    )
  }

  @Synchronized
  private fun writeMouseReport(path: String, bytes: ByteArray) {
    requireReportsAllowed()
    val buttonsHeld = bytes[1] != 0.toByte()
    if (buttonsHeld) mouseButtonsMayBeHeld = true
    val hexEsc = toPrintfEsc(bytes)
    val quotedPath = shQuote(path)
    val script = "test -c $quotedPath && printf '$hexEsc' > $quotedPath"
    // Replaying a relative movement or scroll report would apply it twice.
    val result = root.exec(script, timeoutSec = 5)
    if (result.ok) {
      mouseButtonsMayBeHeld = buttonsHeld
      recordWriteSuccess()
      return
    }
    recordWriteFailure()
    val detail = result.stderr.trim().ifEmpty { result.stdout.trim() }
    throw HidWriteException(
      "HID_MOUSE_WRITE_FAILED",
      "Failed to write HID report to $path. $detail"
    )
  }


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

  internal sealed interface SessionProbe {
    val scriptAttackMode: Int?
      get() = when (this) {
        is Bound -> if (storage) 3 else 1
        Unbound -> 0
        Unknown -> null
      }

    data class Bound(
      val role: String,
      val keyboard: String?,
      val mouse: String?,
      val media: String?,
      val udcState: String?,
      val devicesReady: Boolean,
      val vid: Int? = null,
      val pid: Int? = null,
      val storage: Boolean = false,
    ) : SessionProbe
    data object Unbound : SessionProbe
    data object Unknown : SessionProbe
  }

  private fun probeSavedSession(gadgetDir: String): SessionProbe {
    val shared = prefs.pendingSharedGadget && gadgetDir == prefs.pendingGadgetDir
    if (!gadgetDir.matches(Regex("[A-Za-z0-9._-]+")) ||
      (!shared && !gadgetDir.startsWith("gadgetfs_"))) return SessionProbe.Unknown
    val r = root.exec(Configfs.buildProbeSessionScript(gadgetDir, shared), timeoutSec = 5)
    if (!r.ok) return SessionProbe.Unknown
    val lines = r.stdout.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.toList()
    if (lines == listOf("unbound")) return SessionProbe.Unbound
    if (lines.firstOrNull() != "bound") return SessionProbe.Unknown
    val udcState = lines.getOrNull(1)?.takeIf { it.startsWith("state=") }
      ?.substringAfter('=')?.trim()?.lowercase(Locale.US)?.ifEmpty { null }
    val prefix = if (shared) "hid.tapducky" else "hid.usb"
    val functions = lines.drop(2).associate { line -> line.substringBefore('=') to line.substringAfter('=') }
    val devicesReady = functions["devices_ready"] == "1"
    val first = functions["${prefix}0"] ?: return SessionProbe.Unbound
    val second = functions["${prefix}1"]
    val firstDev = hidDevicePath(first.substringAfter(':')) ?: return SessionProbe.Unknown
    val secondDev = hidDevicePath(second?.substringAfter(':'))
    val thirdDev = hidDevicePath(functions["${prefix}2"]?.substringAfter(':'))
    val binding = when (first.substringBefore(':')) {
      "1" -> if (second == null) {
        SessionProbe.Bound("keyboard", firstDev, null, null, udcState, devicesReady)
      } else {
        if (secondDev == null) return SessionProbe.Unknown
        val media = thirdDev ?: secondDev.takeIf { second.substringBefore(':') == "0" }
        SessionProbe.Bound("composite", firstDev, secondDev, media, udcState, devicesReady)
      }
      "0", "2" -> SessionProbe.Bound("mouse", null, firstDev, firstDev, udcState, devicesReady)
      else -> return SessionProbe.Unknown
    }
    val expectedRole = prefs.activeRoleType.takeIf { prefs.activeGadgetDir == gadgetDir }
      ?: prefs.desiredRole.takeIf { shared }
    return if (expectedRole == null || binding.role == expectedRole.lowercase(Locale.US)) {
      binding.copy(
        vid = hak5UsbId(functions["vid"]),
        pid = hak5UsbId(functions["pid"]),
        storage = functions["storage"] == "1",
      )
    } else SessionProbe.Unknown
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
      activeRoleType = current.activeRoleType ?: prefs.activeRoleType,
      message = message,
      hostConfigurationRequestCount = hostConfigurationRequestCount,
      desiredArmed = prefs.armed,
      gadgetBound = current.gadgetBound,
      prepared = current.prepared,
    )
    statusRef.set(next)
    emit(next)
  }

  private fun setError(message: String) {
    val current = statusRef.get()
    val next = current.copy(
      state = "ERROR",
      message = message,
      hostConfigurationRequestCount = hostConfigurationRequestCount,
      desiredArmed = prefs.armed,
      gadgetBound = current.gadgetBound,
      prepared = current.prepared,
    )
    statusRef.set(next)
    emit(next)
    log.logError("gadget", message)
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

  private fun collectActiveHidReportDiagnostics(): Map<String, Any?> {
    return collectHidReportDiagnostics(prefs.activeGadgetDir)
  }

  private fun collectHidReportDiagnostics(gadgetDirRaw: String?): Map<String, Any?> {
    val gadgetDir = gadgetDirRaw?.replace("\"", "")?.replace("'", "") ?: return mapOf("status" to "no_active_gadget")
    val quotedGadgetDir = shQuote(gadgetDir)
    val shared = prefs.pendingSharedGadget && gadgetDir == prefs.pendingGadgetDir
    val script = buildHidReportDiagnosticsScript(quotedGadgetDir, shared)
    val r = root.exec(script, timeoutSec = 4)
    if (!r.ok) {
      return mapOf(
        "status" to "collect_failed",
        "exitCode" to r.exitCode,
        "stderr" to r.stderr.trim(),
      )
    }

    val result = LinkedHashMap<String, Any?>()
    for (raw in r.stdout.lineSequence()) {
      val line = raw.trim()
      if (line.isEmpty()) continue
      if (line == "status=no_gadget_dir") {
        result["status"] = "no_gadget_dir"
        continue
      }
      if (line.startsWith("status=")) {
        result["status"] = line.substringAfter("status=")
        continue
      }
      val parts = line.split("|")
      if (parts.size != 3) continue
      val fn = parts[0]
      result["$fn.len"] = parts[1].removePrefix("LEN=")
      result["$fn.headHex"] = parts[2].removePrefix("HEAD=")
    }
    if (result.isEmpty()) result["status"] = "missing_report_desc"
    else if (!result.containsKey("status")) result["status"] = "ok"
    return result
  }

  private fun buildHidReportDiagnosticsScript(quotedGadgetDir: String, shared: Boolean): String {
    return """
      GADGET_DIR=$quotedGadgetDir
      FOUND=0
      for CFGBASE in /config/usb_gadget /sys/kernel/config/usb_gadget; do
        G="${'$'}CFGBASE/${'$'}GADGET_DIR"
        if [ ! -d "${'$'}G" ]; then
          continue
        fi
        FOUND=1
        for FN in hid.usb0 hid.usb1 hid.usb2; do
          INSTANCE="${'$'}FN"
          if [ "$shared" = "true" ]; then
            INSTANCE="hid.tapducky${'$'}{FN#hid.usb}"
          fi
          RD="${'$'}G/functions/${'$'}INSTANCE/report_desc"
          [ -f "${'$'}RD" ] || continue
          LEN=0
          HEX=
          if command -v xxd >/dev/null 2>&1; then
            HEX=$(xxd -p "${'$'}RD" 2>/dev/null | tr -cd '0-9a-fA-F' | tr 'A-F' 'a-f')
          elif command -v od >/dev/null 2>&1; then
            HEX=$(od -An -v -tx1 "${'$'}RD" 2>/dev/null | tr -cd '0-9a-fA-F' | tr 'A-F' 'a-f')
          fi
          LEN=$(( ${'$'}{#HEX} / 2 ))
          echo "${'$'}CFGBASE:${'$'}FN|LEN=${'$'}LEN|HEAD=${'$'}HEX"
        done
      done
      if [ "${'$'}FOUND" = "0" ]; then
        echo "status=no_gadget_dir"
      fi
    """.trimIndent()
  }

  private fun expectedHidDescriptorLengths(roleType: String): Map<String, Int> {
    return when (roleType.lowercase(Locale.US)) {
      "mouse" -> mapOf("hid.usb0" to HidSpec.AUX_REPORT_DESC.size)
      "keyboard" -> mapOf("hid.usb0" to HidSpec.KEYBOARD_REPORT_DESC.size)
      else -> mapOf(
        "hid.usb0" to HidSpec.KEYBOARD_REPORT_DESC.size,
        "hid.usb1" to HidSpec.AUX_REPORT_DESC.size,
      )
    }
  }

  private fun expectedHidDescriptorHex(roleType: String): Map<String, String> {
    return when (roleType.lowercase(Locale.US)) {
      "mouse" -> mapOf("hid.usb0" to bytesToHex(HidSpec.AUX_REPORT_DESC))
      "keyboard" -> mapOf("hid.usb0" to bytesToHex(HidSpec.KEYBOARD_REPORT_DESC))
      else -> mapOf(
        "hid.usb0" to bytesToHex(HidSpec.KEYBOARD_REPORT_DESC),
        "hid.usb1" to bytesToHex(HidSpec.AUX_REPORT_DESC),
      )
    }
  }

  private fun parseDescriptorLengthFromDiagnostics(diag: Map<String, Any?>, functionName: String): Int? {
    val key = diag.keys.firstOrNull { it.endsWith("$functionName.len") } ?: return null
    return diag[key]?.toString()?.trim()?.toIntOrNull()
  }

  private fun parseDescriptorHeadFromDiagnostics(diag: Map<String, Any?>, functionName: String): String? {
    val key = diag.keys.firstOrNull { it.endsWith("$functionName.headHex") } ?: return null
    return diag[key]?.toString()?.trim()?.lowercase(Locale.US)
  }

  private fun bytesToHex(bytes: ByteArray): String {
    val sb = StringBuilder(bytes.size * 2)
    for (b in bytes) {
      sb.append(String.format(java.util.Locale.US, "%02x", b.toInt() and 0xFF))
    }
    return sb.toString()
  }

  private fun validateActiveHidReportDescriptors(profile: Configfs.ParsedProfile, gadgetDir: String): String? {
    val expected = expectedHidDescriptorLengths(profile.roleType)
    val expectedHex = expectedHidDescriptorHex(profile.roleType)
    val diag = collectHidReportDiagnostics(gadgetDir)
    val status = diag["status"]?.toString()
    if (status == "collect_failed") {
      return "Could not collect HID report descriptor metadata from gadget"
    }
    if (status == "no_active_gadget" || status == "no_gadget_dir") {
      return "No active HID gadget directory found while validating descriptors"
    }

    val errors = ArrayList<String>()
    for ((fn, expectedLen) in expected) {
      val actual = parseDescriptorLengthFromDiagnostics(diag, fn)
      if (actual == null) {
        errors.add("$fn: descriptor missing")
      } else if (actual != expectedLen) {
        errors.add("$fn: len=$actual expected=$expectedLen")
      } else {
        val expectedHexValue = expectedHex[fn]
        val actualHead = parseDescriptorHeadFromDiagnostics(diag, fn)
        if (expectedHexValue != null) {
          if (actualHead.isNullOrEmpty()) {
            errors.add("$fn: descriptor readback unavailable")
          } else if (actualHead != expectedHexValue) {
            val actualPrefix = actualHead.take(expectedHexValue.length)
            errors.add("$fn: descriptor mismatch; first bytes $actualPrefix expected $expectedHexValue")
          }
        }
      }
    }
    return if (errors.isEmpty()) null else errors.joinToString("; ")
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
      out["activeHidReportDescriptor"] = collectActiveHidReportDiagnostics()
    } catch (t: Throwable) {
      out["activeHidReportDescriptorError"] = t.toString()
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
      val gadgets = ArrayList<String>()
      val basesForList = listOf("/config/usb_gadget", "/sys/kernel/config/usb_gadget")
      for (b in basesForList) {
        val list = root.exec("ls -1 $b 2>/dev/null || true").stdout
          .split("\n")
          .map { it.trim() }
          .filter { it.isNotEmpty() }
        for (g in list) {
          gadgets.add("$b/$g")
        }
      }
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
    val ok = root.exec(script, timeoutSec = 3).ok
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
    val r = root.exec(script, timeoutSec = 6)
    val elapsedMs = (System.currentTimeMillis() - started).coerceAtLeast(1L)
    if (!r.ok) return 10_000
    val perIterMs = elapsedMs.toDouble() / iterations.toDouble()
    val floorUs = (perIterMs * 1000.0).roundToInt()
    val clamped = floorUs.coerceIn(1000, 50_000)
    log.log("kbd", "Estimated delay floor ${clamped}us (per-iter ${"%.2f".format(perIterMs)}ms)")
    return clamped
  }
}
