package org.kaijinlab.tap_ducky

import android.util.Base64
import java.util.Locale

object Configfs {
  const val HID_ALLOCATION_FAILED = 23
  const val GADGET_CREATION_FAILED = 24

  fun buildProbeSessionScript(gadgetDir: String, shared: Boolean): String {
    val prefix = if (shared) "hid.tapducky" else "hid.usb"
    return """
      NAME=${shEscape(gadgetDir)}
      FOUND=0
      for base in /config/usb_gadget /sys/kernel/config/usb_gadget; do
        [ -d "${'$'}base" ] || continue
        FOUND=1
        G="${'$'}base/${'$'}NAME"
        [ -e "${'$'}G/UDC" ] || continue
        UDC_NAME=${'$'}(cat "${'$'}G/UDC") || exit 2
        [ -n "${'$'}UDC_NAME" ] || continue
        echo bound
        for fn in ${prefix}0 ${prefix}1 ${prefix}2; do
          for link in "${'$'}G"/configs/*/"${'$'}fn"; do
            [ -L "${'$'}link" ] && [ -d "${'$'}link" ] || continue
            target=${'$'}(readlink "${'$'}link") || continue
            [ "${'$'}{target##*/}" = "${'$'}fn" ] || continue
            protocol=${'$'}(cat "${'$'}G/functions/${'$'}fn/protocol") || exit 2
            dev=${'$'}(cat "${'$'}G/functions/${'$'}fn/dev" 2>/dev/null)
            printf '%s=%s:%s\n' "${'$'}fn" "${'$'}protocol" "${'$'}dev"
            break
          done
        done
        exit 0
      done
      [ "${'$'}FOUND" = 1 ] || exit 2
      echo unbound
    """.trimIndent()
  }

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
      CFGBASE_CANDIDATES="/config/usb_gadget /sys/kernel/config/usb_gadget"
      CFGBASE=""

      for b in ${'$'}CFGBASE_CANDIDATES; do
        [ -d "${'$'}b" ] || continue
        CFGBASE="${'$'}b"
        break
      done

      if [ -z "${'$'}CFGBASE" ]; then
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
      for c in "${'$'}SYS_UDC" /sys/class/udc/*; do
        c=${'$'}{c##*/}
        case "${'$'}c" in dummy_udc*) continue ;; esac
        [ -d "/sys/class/udc/${'$'}c" ] && append_udc_candidate "${'$'}c"
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
        mkdir "${'$'}G" || exit $GADGET_CREATION_FAILED
      fi

      cd "${'$'}G"

      # Reset previous config links/functions when reusing the same gadget dir.
      # Otherwise switching Mouse <-> Keyboard <-> Composite can leave stale hid.usb*
      # directories and config symlinks behind.
      mkdir -p "configs/$cfg" 2>/dev/null || true
      for link in configs/$cfg/*; do
        if [ -L "${'$'}link" ]; then rm "${'$'}link"; fi
      done
      for fn in functions/*; do
        if [ -d "${'$'}fn" ]; then rmdir "${'$'}fn"; fi
      done

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
      "keyboard" -> listOf(
        buildKeyboardFunctionScript("hid.usb0"),
        buildConsumerFunctionScript("hid.usb1"),
      ).joinToString("\n\n")
      else -> buildCompositeFunctionScript()
    }

    val link = """
      # Link functions into config using absolute paths to avoid shell context issues.
      for fn in ${expectedFunctionNames(p.roleType).joinToString(" ")}; do
        fn_src="${'$'}G/functions/${'$'}fn"
        fn_dst="${'$'}G/configs/$cfg/${'$'}fn"
        if [ ! -d "${'$'}fn_src" ] && [ ! -f "${'$'}fn_src" ]; then
          echo "Missing function directory/file: ${'$'}fn_src" >&2
          exit 21
        fi

        rm -f "${'$'}fn_dst"
        ln -s "${'$'}fn_src" "${'$'}fn_dst"
      done
    """.trimIndent()

    val bind = """
      BOUND_UDC=""
      for fn in ${expectedFunctionNames(p.roleType).joinToString(" ")}; do
        fn_link="${'$'}G/configs/$cfg/${'$'}fn"
        if [ ! -L "${'$'}fn_link" ]; then
          echo "Missing config link for ${'$'}fn_link" >&2
          exit 22
        fi
      done

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
      for fn in ${expectedFunctionNames(p.roleType).joinToString(" ")}; do
        if [ -r "functions/${'$'}fn/dev" ]; then
          printf '%s=%s\n' "${'$'}fn" "${'$'}(cat "functions/${'$'}fn/dev")"
        fi
      done
    """.trimIndent()

    return listOf(create, functions, link, bind).joinToString("\n\n") + "\n"
  }

  fun buildUnbindAndCleanupScript(gadgetDir: String, shared: Boolean = false): String {
    if (shared) return buildStockCleanupScript(gadgetDir)
    val gadget = sanitizeGadgetName(gadgetDir)
    return """
      set -e
      G=""
      for b in /config/usb_gadget /sys/kernel/config/usb_gadget; do
        if [ -d "${'$'}b/$gadget" ]; then
          G="${'$'}b/$gadget"
          break
        fi
      done
      if [ -z "${'$'}G" ]; then
        exit 0
      fi
      (echo "" > "${'$'}G/UDC") 2>/dev/null || true
      for link in "${'$'}G/configs/c.1"/*; do
        if [ -L "${'$'}link" ]; then rm "${'$'}link"; fi
      done
      for fn in "${'$'}G/functions"/*; do
        if [ -d "${'$'}fn" ]; then rmdir "${'$'}fn"; fi
      done
      for dir in configs/c.1/strings/0x409 configs/c.1 strings/0x409; do
        if [ -d "${'$'}G/${'$'}dir" ]; then rmdir "${'$'}G/${'$'}dir"; fi
      done
      rmdir "${'$'}G"
    """.trimIndent() + "\n"
  }

  fun buildAttachToStockScript(profile: ParsedProfile, gadgetDir: String, udc: String): String {
    val composite = profile.roleType.lowercase(Locale.US) !in listOf("keyboard", "mouse")
    val mouse = profile.roleType.equals("mouse", ignoreCase = true)
    val names = when {
      mouse -> "hid.tapducky0"
      composite -> "hid.tapducky0 hid.tapducky1 hid.tapducky2"
      else -> "hid.tapducky0 hid.tapducky1"
    }
    val functions = when {
      mouse -> buildMouseFunctionScript("hid.tapducky0")
      composite -> listOf(
        buildKeyboardFunctionScript("hid.tapducky0"),
        buildMouseFunctionScript("hid.tapducky1"),
        buildConsumerFunctionScript("hid.tapducky2"),
      ).joinToString("\n\n")
      else -> listOf(
        buildKeyboardFunctionScript("hid.tapducky0"),
        buildConsumerFunctionScript("hid.tapducky1"),
      ).joinToString("\n\n")
    }
    return """
      set -e
      ${stockGadgetLocation(gadgetDir)}
      UDC_NAME=${shEscape(udc)}
      [ "${'$'}(cat UDC)" = "${'$'}UDC_NAME" ] || exit 25
      $requireDetachedStockHost
      set -- configs/*
      if [ "${'$'}#" -ne 1 ] || [ ! -d "${'$'}1" ]; then
        echo "Stock USB gadget must have exactly one configuration" >&2
        exit 25
      fi
      CFG="${'$'}1"
      if [ ! -d functions/ffs.adb ]; then
        echo "Could not identify an Android stock USB gadget to extend" >&2
        exit 25
      fi
      $functions
      printf '\n' > UDC
      for fn in $names; do
        ln -s "${'$'}G/functions/${'$'}fn" "${'$'}CFG/${'$'}fn"
      done
      printf '%s\n' "${'$'}UDC_NAME" > UDC
      [ "${'$'}(cat UDC)" = "${'$'}UDC_NAME" ] || exit 25
      for fn in $names; do
        dev=${'$'}(cat "functions/${'$'}fn/dev")
        printf 'hid.usb%s=%s\n' "${'$'}{fn#hid.tapducky}" "${'$'}dev"
      done
    """.trimIndent() + "\n"
  }

  private fun stockGadgetLocation(gadgetDir: String): String = """
    NAME=${shEscape(sanitizeGadgetName(gadgetDir))}
    G="/config/usb_gadget/${'$'}NAME"
    [ -d "${'$'}G" ] || G="/sys/kernel/config/usb_gadget/${'$'}NAME"
    cd "${'$'}G"
  """.trimIndent()

  private val requireDetachedStockHost = """
    HOST_STATE=${'$'}(cat "/sys/class/udc/${'$'}UDC_NAME/state" 2>/dev/null || true)
    if [ "${'$'}HOST_STATE" != "not attached" ]; then
      echo "Unplug the USB data cable before switching the Android USB configuration, then retry." >&2
      exit 25
    fi
  """.trimIndent()

  private fun buildStockCleanupScript(gadgetDir: String): String = """
    set -e
    ${stockGadgetLocation(gadgetDir)}
    for link in configs/*/hid.tapducky0 configs/*/hid.tapducky1 configs/*/hid.tapducky2; do
      [ -L "${'$'}link" ] || continue
      UDC_NAME=${'$'}(cat UDC)
      if [ -n "${'$'}UDC_NAME" ]; then
        $requireDetachedStockHost
        printf '\n' > UDC
      fi
      rm "${'$'}link"
    done
    for fn in functions/hid.tapducky0 functions/hid.tapducky1 functions/hid.tapducky2; do
      if [ -d "${'$'}fn" ]; then rmdir "${'$'}fn"; fi
    done
  """.trimIndent() + "\n"

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
    val descEsc = bytesToPrintfB(descriptor)
    val descEscHex = bytesToPrintfX(descriptor)
    val descHex = bytesToHex(descriptor)
    val fallbackDescB64 = bytesToBase64(descriptor)
    val expectedLen = descriptor.size
    val expectedHex = bytesToHex(descriptor)
    val expectedHexLen = expectedHex.length
    return """
      if ! mkdir functions/$fn; then
        echo "Cannot allocate USB HID function $fn. If the error is 'No such device', end any other USB HID gadget session and retry. The kernel may have no free HID slots or may lack HID gadget support." >&2
        exit $HID_ALLOCATION_FAILED
      fi
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
        CURRENT_LEN=${'$'}{#CURRENT_HEX}
        [ "${'$'}CURRENT_LEN" -eq "${'$'}EXPECTED_HEX_LEN" ] || return 1
        [ "${'$'}CURRENT_HEX" = "${'$'}EXPECTED_HEX" ] || return 1
        return 0
      }
      verify_written_desc() {
        DESC_TMP_LEN=$(wc -c < functions/$fn/report_desc 2>/dev/null | tr -d ' \n\r')
        if [ "${'$'}DESC_TMP_LEN" = "0" ]; then
          return 1
        fi
        verify_desc || return 1
        return 0
      }

      wrote_desc=0
      if [ "${'$'}wrote_desc" -eq 0 ] && command -v base64 >/dev/null 2>&1; then
        if printf '%s' '$fallbackDescB64' | base64 -d > functions/$fn/report_desc 2>/dev/null; then
          if verify_written_desc; then
            wrote_desc=1
          fi
        elif printf '%s' '$fallbackDescB64' | base64 --decode > functions/$fn/report_desc 2>/dev/null; then
          if verify_written_desc; then
            wrote_desc=1
          fi
        fi
      fi
      if [ "${'$'}wrote_desc" -eq 0 ] && command -v xxd >/dev/null 2>&1; then
        if printf '%s' '$descHex' | xxd -r -p > functions/$fn/report_desc 2>/dev/null; then
          if verify_written_desc; then
            wrote_desc=1
          fi
        fi
      fi
      if [ "${'$'}wrote_desc" -eq 0 ] && command -v busybox >/dev/null 2>&1; then
        # busybox xxd may not be available on all builds, so this is a best-effort fallback.
        if printf '%s' '$descHex' | busybox xxd -r -p > functions/$fn/report_desc 2>/dev/null; then
          if verify_written_desc; then
            wrote_desc=1
          fi
        fi
      fi
      if [ "${'$'}wrote_desc" -eq 0 ] && printf '$descEscHex' > functions/$fn/report_desc 2>/dev/null; then
        if verify_written_desc; then
          wrote_desc=1
        fi
      fi
      if [ "${'$'}wrote_desc" -eq 0 ] && printf '$descEsc' > functions/$fn/report_desc 2>/dev/null; then
        if verify_written_desc; then
          wrote_desc=1
        fi
      fi
      if [ "${'$'}wrote_desc" -eq 0 ]; then
        echo "Could not write and verify HID report descriptor for $fn (hex_len=${'$'}CURRENT_LEN, expected_len=${'$'}EXPECTED_HEX_LEN)" >&2
        exit 11
      fi

      if ! verify_written_desc; then
        echo "Invalid HID report descriptor for ${fn} (hex_len=${'$'}CURRENT_LEN, expected_len=${'$'}EXPECTED_HEX_LEN, hex=${'$'}CURRENT_HEX, expected=${'$'}EXPECTED_HEX)" >&2
        exit 11
      fi
    """.trimIndent()
  }

  private fun buildConsumerFunctionScript(fn: String): String {
    return buildHidFunctionScript(
      fn = fn,
      protocol = 0,
      subclass = 0,
      reportLength = 2,
      descriptor = HidSpec.CONSUMER_REPORT_DESC,
    )
  }

  private fun buildCompositeFunctionScript(): String {
    return listOf(
      buildKeyboardFunctionScript("hid.usb0"),
      buildMouseFunctionScript("hid.usb1"),
      buildConsumerFunctionScript("hid.usb2"),
    ).joinToString("\n\n")
  }

  private fun expectedFunctionNames(roleType: String): List<String> {
    return when (roleType.lowercase(Locale.US)) {
      "mouse" -> listOf("hid.usb0")
      "keyboard" -> listOf("hid.usb0", "hid.usb1")
      else -> listOf("hid.usb0", "hid.usb1", "hid.usb2")
    }
  }

  private fun bytesToPrintfB(bytes: ByteArray): String {
    val sb = StringBuilder()
    for (b in bytes) {
      sb.append(String.format(Locale.US, "\\%03o", b.toInt() and 0xFF))
    }
    return sb.toString()
  }

  private fun bytesToPrintfX(bytes: ByteArray): String {
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
