package org.kaijinlab.tap_ducky

import android.util.Base64
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
    return buildHidFunctionScript(
      fn = fn,
      protocol = 2,
      subclass = 1,
      reportLength = 4,
      descriptor = HidSpec.MOUSE_REPORT_DESC,
    )
  }

  private fun buildKeyboardFunctionScript(fn: String): String {
    return buildHidFunctionScript(
      fn = fn,
      protocol = 1,
      subclass = 1,
      reportLength = 8,
      descriptor = HidSpec.KEYBOARD_REPORT_DESC,
    )
  }

  private fun buildHidFunctionScript(
    fn: String,
    protocol: Int,
    subclass: Int,
    reportLength: Int,
    descriptor: ByteArray
  ): String {
    val desc = bytesToPrintfB(descriptor)
    val descEsc = bytesToPrintfHex(descriptor)
    val fallbackDescB64 = bytesToBase64(descriptor)
    val expectedLen = descriptor.size
    val expectedHex = bytesToHex(descriptor)
    val descHex = expectedHex
    val expectedHexLen = expectedHex.length
    return """
      mkdir -p functions/$fn
      echo $protocol > functions/$fn/protocol
      echo $subclass > functions/$fn/subclass
      echo $reportLength > functions/$fn/report_length
      EXPECTED_LEN=$expectedLen
      EXPECTED_HEX=$expectedHex
      EXPECTED_HEX_LEN=$expectedHexLen
      CURRENT_HEX=
      CURRENT_LEN=
      verify_desc() {
        CURRENT_HEX=
        if command -v od >/dev/null 2>&1; then
          CURRENT_HEX=$(od -An -tx1 -N ${'$'}EXPECTED_LEN functions/$fn/report_desc 2>/dev/null | tr -d ' \n\r' | tr -d ' ' | tr 'A-F' 'a-f')
        elif command -v xxd >/dev/null 2>&1; then
          CURRENT_HEX=$(xxd -p -l ${'$'}EXPECTED_LEN functions/$fn/report_desc 2>/dev/null | tr -d '\n\r' | tr 'A-F' 'a-f')
        elif command -v busybox >/dev/null 2>&1; then
          CURRENT_HEX=$(busybox od -An -tx1 -N ${'$'}EXPECTED_LEN functions/$fn/report_desc 2>/dev/null | tr -d ' \n\r' | tr -d ' ' | tr 'A-F' 'a-f')
          if [ -z "${'$'}CURRENT_HEX" ]; then
            CURRENT_HEX=$(busybox xxd -p -l ${'$'}EXPECTED_LEN functions/$fn/report_desc 2>/dev/null | tr -d '\n\r' | tr 'A-F' 'a-f')
          fi
          if [ -z "${'$'}CURRENT_HEX" ]; then
            CURRENT_HEX=$(busybox hexdump -v -e '1/1 "%02x"' -n ${'$'}EXPECTED_LEN functions/$fn/report_desc 2>/dev/null | tr -d ' \n\r')
          fi
        else
          echo "No report descriptor verifier available in this shell (od/xxd/busybox missing)." >&2
          return 1
        fi
        if [ -z "${'$'}CURRENT_HEX" ]; then
          return 1
        fi
        CURRENT_LEN=$(echo "${'$'}CURRENT_HEX" | wc -c | tr -d ' \n\r')
        [ "${'$'}CURRENT_LEN" -eq "${'$'}EXPECTED_HEX_LEN" ] || return 1
        [ "${'$'}CURRENT_HEX" = "${'$'}EXPECTED_HEX" ] || return 1
        return 0
      }
      if printf '$descEsc' > functions/$fn/report_desc 2>/dev/null; then
        :
      elif command -v base64 >/dev/null 2>&1; then
        if ! printf '%s' '$fallbackDescB64' | base64 -d > functions/$fn/report_desc 2>/dev/null && ! printf '%s' '$fallbackDescB64' | base64 --decode > functions/$fn/report_desc 2>/dev/null; then
          echo "Failed to write HID report descriptor for ${fn} and no supported descriptor writer was available" >&2
          exit 11
        fi
      elif command -v xxd >/dev/null 2>&1; then
        if ! printf '%s' '$descHex' | xxd -r -p > functions/$fn/report_desc 2>/dev/null; then
          echo "Failed to write HID report descriptor for ${fn} and no supported descriptor writer was available" >&2
          exit 11
        fi
      elif command -v busybox >/dev/null 2>&1; then
        # busybox xxd may not be available on all builds, so this is a best-effort fallback.
        if ! printf '%s' '$descHex' | busybox xxd -r -p > functions/$fn/report_desc 2>/dev/null; then
          echo "Failed to write HID report descriptor for ${fn} and no supported descriptor writer was available" >&2
          exit 11
        fi
      elif ! printf '$desc' > functions/$fn/report_desc 2>/dev/null; then
        echo "Failed to write HID report descriptor for ${fn} and no supported descriptor writer was available" >&2
        exit 11
      fi

      DESC_TMP_LEN=$(wc -c < functions/$fn/report_desc 2>/dev/null | tr -d ' \n\r')
      if [ "${'$'}DESC_TMP_LEN" = "0" ]; then
        echo "Unexpected HID report descriptor byte length for ${fn}: ${'$'}DESC_TMP_LEN (expected ${'$'}expectedLen)" >&2
        exit 11
      fi
      if ! verify_desc; then
        echo "Invalid HID report descriptor for ${fn} (hex_len=${'$'}CURRENT_LEN, expected_len=${'$'}EXPECTED_HEX_LEN, hex=${'$'}CURRENT_HEX, expected=${'$'}EXPECTED_HEX)" >&2
        exit 11
      fi
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
      sb.append(String.format(Locale.US, "\\%03o", b.toInt() and 0xFF))
    }
    return sb.toString()
  }

  private fun bytesToPrintfHex(bytes: ByteArray): String {
    val sb = StringBuilder()
    for (b in bytes) {
      sb.append(String.format(Locale.US, "\\x%02x", b.toInt() and 0xFF))
    }
    return sb.toString()
  }

  private fun bytesToBase64(bytes: ByteArray): String {
    return Base64.encodeToString(bytes, Base64.NO_WRAP)
  }

  private fun bytesToHex(bytes: ByteArray): String {
    val sb = StringBuilder(bytes.size * 2)
    for (b in bytes) {
      sb.append(String.format(Locale.US, "%02x", b.toInt() and 0xFF))
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
