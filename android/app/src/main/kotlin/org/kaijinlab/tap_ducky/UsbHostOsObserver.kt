package org.kaijinlab.tap_ducky

import android.os.SystemClock

/** Diagnostic-only observer of USB enumeration in an app-owned tracefs instance. */
internal class UsbHostOsObserver(private val root: RootShell, private val log: LogBus) {
  private var attemptedController: String? = null
  private var instance: String? = null

  val available: Boolean get() = instance != null

  fun start(controller: String?) {
    if (controller == null || !controller.matches(Regex("[A-Za-z0-9._-]+"))) {
      stop()
      return
    }
    if (controller == attemptedController) return
    stop()
    attemptedController = controller
    val result = exec(buildStartScript(controller))
    instance = result?.takeIf { it.ok }?.stdout?.trim()?.takeIf { path ->
      path == "/sys/kernel/tracing/instances/$instanceName" ||
        path == "/sys/kernel/debug/tracing/instances/$instanceName"
    }
    log.log("host-os", if (available) "Passive USB capture enabled" else "Passive USB capture unavailable")
  }

  fun read(): UsbHostFingerprint {
    val path = instance ?: return UsbHostFingerprint()
    val trace = exec("tail -n 256 ${shQuote("$path/trace")}")?.takeIf { it.ok }
      ?: return UsbHostFingerprint()
    return classifyUsbHostTrace(trace.stdout, SystemClock.uptimeMillis())
  }

  fun stop() {
    attemptedController = null
    val path = instance ?: return
    instance = null
    exec("rmdir ${shQuote(path)}")
  }

  private fun exec(script: String): RootShell.ExecResult? = try {
    root.exec(script, timeoutSec = 2, logOutput = false)
  } catch (e: Exception) {
    log.logError("host-os", "USB capture command failed: ${e.javaClass.simpleName}")
    null
  }

  companion object {
    private const val instanceName = "tapducky_host_os"

    internal fun buildStartScript(controller: String): String = """
      set -e
      controller=${shQuote(controller)}
      real_udc=""
      for d in /sys/class/udc/*; do
        [ -d "${'$'}d" ] || continue
        case "${'$'}{d##*/}" in dummy*) continue ;; esac
        [ -z "${'$'}real_udc" ] || exit 1
        real_udc="${'$'}{d##*/}"
      done
      [ "${'$'}real_udc" = "${'$'}controller" ] || exit 1
      driver=${'$'}(readlink "/sys/class/udc/${'$'}controller/device/driver")
      case "${'$'}{driver##*/}" in
        mtu3) setup=mtu3/mtu3_handle_setup ;;
        dwc3|dwc3-gadget) setup=dwc3/dwc3_ctrl_req ;;
        *) exit 1 ;;
      esac
      for base in /sys/kernel/tracing /sys/kernel/debug/tracing; do
        if [ -d "${'$'}base/instances" ] && [ -f "${'$'}base/events/${'$'}setup/format" ]; then break; fi
      done
      [ -f "${'$'}base/events/${'$'}setup/format" ] || exit 1
      dir="${'$'}base/instances/$instanceName"
      if [ -d "${'$'}dir" ]; then rmdir "${'$'}dir"; fi
      mkdir "${'$'}dir"
      trap 'rmdir "${'$'}dir"' EXIT
      echo 0 > "${'$'}dir/tracing_on"
      echo 16 > "${'$'}dir/buffer_size_kb"
      echo mono > "${'$'}dir/trace_clock"
      state=gadget/usb_gadget_set_state
      echo 'state == 0 || state == 6 || state == 7' > "${'$'}dir/events/${'$'}state/filter"
      echo '(bRequestType == 0 && bRequest == 5) ||
        (bRequestType == 128 && bRequest == 6 &&
          ((wValue >= 512 && wValue < 1024 && wValue != 1006) || (wValue == 1006 && wIndex == 0))) ||
        (bRequestType == 33 && (bRequest == 10 || bRequest == 11)) ||
        (bRequestType == 192 && wValue == 0 && wIndex == 4 && wLength >= 16)' |
        tr '\n' ' ' > "${'$'}dir/events/${'$'}setup/filter"
      echo 1 > "${'$'}dir/events/${'$'}state/enable"
      echo 1 > "${'$'}dir/events/${'$'}setup/enable"
      echo 1 > "${'$'}dir/tracing_on"
      printf '%s\n' "${'$'}dir"
      trap - EXIT
    """.trimIndent()
  }
}
