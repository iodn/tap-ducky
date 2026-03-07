package org.kaijinlab.tap_ducky

import java.util.Locale

object Configfs {
  data class ParsedProfile(
    val id: String,
    val name: String,
    val roleType: String,
    val preferredUdc: String?,
    val manufacturer: String,
    val product: String,
    val serialNumber: String,
    val vendorId: Int,
    val productId: Int,
    val maxPowerMa: Int,
  )

  fun buildCreateAndBindScript(p: ParsedProfile, gadgetDir: String): String {
    val baseSelect = """
      set -e
      CFGBASE="/config/usb_gadget"
      if [ ! -d "${'$'}CFGBASE" ]; then
        CFGBASE="/sys/kernel/config/usb_gadget"
      fi
      if [ ! -d "${'$'}CFGBASE" ]; then
        echo "configfs usb_gadget not found" >&2
        exit 2
      fi
    """.trimIndent()

    val mfg = shEscape(p.manufacturer)
    val prod = shEscape(p.product)
    val sn = shEscape(p.serialNumber)
    val gadget = sanitizeGadgetName(gadgetDir)
    val preferredUdc = p.preferredUdc?.trim()?.takeIf { it.isNotEmpty() } ?: ""
    val preferredUdcQuoted = shEscape(preferredUdc)

    val idVendor = String.format(Locale.US, "0x%04x", p.vendorId and 0xFFFF)
    val idProduct = String.format(Locale.US, "0x%04x", p.productId and 0xFFFF)

    val cfg = "c.1"

    val create = """
      $baseSelect

      PREFERRED_UDC=$preferredUdcQuoted
      UDC_CANDIDATES=""

      append_udc_candidate() {
        c=${'$'}1
        [ -n "${'$'}c" ] || return 0
        for e in ${'$'}UDC_CANDIDATES; do
          [ "${'$'}e" = "${'$'}c" ] && return 0
        done
        UDC_CANDIDATES="${'$'}UDC_CANDIDATES ${'$'}c"
      }

      if [ -n "${'$'}PREFERRED_UDC" ]; then
        append_udc_candidate "${'$'}PREFERRED_UDC"
      fi

      SYS_UDC=${'$'}(getprop sys.usb.controller 2>/dev/null | tr -d '\r')
      append_udc_candidate "${'$'}SYS_UDC"

      for c in ${'$'}(ls /sys/class/udc 2>/dev/null || true); do
        c=${'$'}(echo "${'$'}c" | tr -d '\r')
        append_udc_candidate "${'$'}c"
      done

      if [ -z "${'$'}UDC_CANDIDATES" ]; then
        echo "No UDC found in /sys/class/udc" >&2
        exit 3
      fi

      G="${'$'}CFGBASE/$gadget"
      if [ -d "${'$'}G" ]; then
        echo "Gadget already exists: ${'$'}G" >&2
        (echo "" > "${'$'}G/UDC") 2>/dev/null || true
      else
        mkdir -p "${'$'}G"
      fi

      cd "${'$'}G"

      # Reset previous config links/functions when reusing the same gadget dir.
      # Otherwise switching Mouse <-> Keyboard <-> Composite can leave stale hid.usb*
      # directories and config symlinks behind.
      mkdir -p "configs/$cfg" 2>/dev/null || true
      rm -f "configs/$cfg"/* 2>/dev/null || true
      rm -rf functions/* 2>/dev/null || true

      echo $idVendor > idVendor
      echo $idProduct > idProduct
      echo 0x0200 > bcdUSB
      echo 0x0100 > bcdDevice

      mkdir -p strings/0x409
      echo $mfg > strings/0x409/manufacturer
      echo $prod > strings/0x409/product
      echo $sn > strings/0x409/serialnumber

      mkdir -p configs/$cfg/strings/0x409
      echo "Config 1" > configs/$cfg/strings/0x409/configuration
      echo ${p.maxPowerMa.coerceIn(2, 500)} > configs/$cfg/MaxPower
    """.trimIndent()

    val functions = when (p.roleType.lowercase(Locale.US)) {
      "mouse" -> buildMouseFunctionScript("hid.usb0")
      "keyboard" -> buildKeyboardFunctionScript("hid.usb0")
      else -> buildCompositeFunctionScript()
    }

    val link = """
      # Link functions into config
      for f in ${'$'}(ls -1 functions 2>/dev/null); do
        if [ ! -e "configs/$cfg/${'$'}f" ]; then
          ln -s "functions/${'$'}f" "configs/$cfg/${'$'}f"
        fi
      done
    """.trimIndent()

    val bind = """
      BOUND_UDC=""
      for UDC_NAME in ${'$'}UDC_CANDIDATES; do
        [ -d "/sys/class/udc/${'$'}UDC_NAME" ] || continue

        # Unbind other gadgets bound to the selected UDC (best-effort)
        for U in "${'$'}CFGBASE"/*/UDC; do
          [ -f "${'$'}U" ] || continue
          if [ "${'$'}U" = "${'$'}G/UDC" ]; then
            continue
          fi
          CUR=${'$'}(cat "${'$'}U" 2>/dev/null | tr -d '\r')
          if [ "${'$'}CUR" = "${'$'}UDC_NAME" ]; then
            (echo "" > "${'$'}U") 2>/dev/null || true
          fi
        done

        (echo "" > UDC) 2>/dev/null || true
        (echo "${'$'}UDC_NAME" > UDC) 2>/dev/null || true
        CUR_UDC=${'$'}(cat UDC 2>/dev/null | tr -d '\r')
        if [ "${'$'}CUR_UDC" = "${'$'}UDC_NAME" ]; then
          BOUND_UDC="${'$'}UDC_NAME"
          break
        fi
      done

      if [ -z "${'$'}BOUND_UDC" ]; then
        echo "Failed to bind gadget to any UDC candidate: ${'$'}UDC_CANDIDATES" >&2
        exit 4
      fi

      echo "Bound to UDC: ${'$'}BOUND_UDC"
    """.trimIndent()

    return listOf(create, functions, link, bind).joinToString("\n\n") + "\n"
  }

  fun buildUnbindAndCleanupScript(gadgetDir: String): String {
    val gadget = sanitizeGadgetName(gadgetDir)
    return """
      set -e
      CFGBASE="/config/usb_gadget"
      if [ ! -d "${'$'}CFGBASE" ]; then
        CFGBASE="/sys/kernel/config/usb_gadget"
      fi
      G="${'$'}CFGBASE/$gadget"
      if [ ! -d "${'$'}G" ]; then
        exit 0
      fi
      (echo "" > "${'$'}G/UDC") 2>/dev/null || true
      rm -f "${'$'}G/configs/c.1"/* 2>/dev/null || true
      rm -rf "${'$'}G" 2>/dev/null || true
    """.trimIndent() + "\n"
  }

  fun buildPanicStopScript(): String {
    return """
      set -e
      CFGBASE="/config/usb_gadget"
      if [ ! -d "${'$'}CFGBASE" ]; then
        CFGBASE="/sys/kernel/config/usb_gadget"
      fi
      if [ -d "${'$'}CFGBASE" ]; then
        find "${'$'}CFGBASE" -maxdepth 2 -name UDC -type f -exec sh -c 'echo "" > "${'$'}1" 2>/dev/null || true' _ {} \;
      fi
    """.trimIndent() + "\n"
  }

  private fun buildMouseFunctionScript(fn: String): String {
    val desc = bytesToPrintfB(HidSpec.MOUSE_REPORT_DESC)
    return """
      mkdir -p functions/$fn
      echo 2 > functions/$fn/protocol
      echo 1 > functions/$fn/subclass
      echo 4 > functions/$fn/report_length
      printf '%b' '$desc' > functions/$fn/report_desc
    """.trimIndent()
  }

  private fun buildKeyboardFunctionScript(fn: String): String {
    val desc = bytesToPrintfB(HidSpec.KEYBOARD_REPORT_DESC)
    return """
      mkdir -p functions/$fn
      echo 1 > functions/$fn/protocol
      echo 1 > functions/$fn/subclass
      echo 8 > functions/$fn/report_length
      printf '%b' '$desc' > functions/$fn/report_desc
    """.trimIndent()
  }

  private fun buildCompositeFunctionScript(): String {
    return listOf(
      buildKeyboardFunctionScript("hid.usb0"),
      buildMouseFunctionScript("hid.usb1")
    ).joinToString("\n\n")
  }

  private fun bytesToPrintfB(bytes: ByteArray): String {
    val sb = StringBuilder()
    for (b in bytes) {
      sb.append(String.format(Locale.US, "\\x%02x", b.toInt() and 0xFF))
    }
    return sb.toString()
  }

  internal fun shEscape(s: String): String {
    return "'" + s.replace("'", "'\"'\"'") + "'"
  }

  private fun sanitizeGadgetName(name: String): String {
    val cleaned = name.trim().ifEmpty { "gadgetfs" }
    return cleaned.replace(Regex("[^a-zA-Z0-9._-]"), "_")
  }
}
