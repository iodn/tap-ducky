package org.kaijinlab.tap_ducky

import android.util.Base64
import java.util.Locale

object Configfs {
  const val HID_ALLOCATION_FAILED = 23
  const val GADGET_CREATION_FAILED = 24
  const val HOST_ATTACHED_REFUSED = 26
  const val SETUP_NOT_STARTED = 27
  const val STOCK_BINDING_CHANGED = 28
  const val USB_DATA_RESTORE_FAILED = 29

  private val stockFunctionProbe = """
    ANDROID_USB_MODES=${'$'}(getprop sys.usb.config 2>/dev/null || :)
    is_android_function() {
      case "${'$'}1" in
        ffs.adb|ffs.mtp|ffs.ptp|ffs.accessory|mtp.gs*|ptp.gs*|accessory.gs*|audio_source.gs*|midi.gs*|rndis.gs*|ncm.gs*|acm.gs*|mass_storage.gs*|uvc.gs*) return 0 ;;
        *) return 1 ;;
      esac
    }
    matches_android_mode() {
      case "${'$'}1" in
        ffs.*) mode=${'$'}{1#ffs.} ;;
        *.*) mode=${'$'}{1%%.*} ;;
        *) return 1 ;;
      esac
      case "${'$'}mode" in
        mtp|ptp|accessory|audio_source|midi|rndis|ncm|acm|mass_storage|uvc)
          case ",${'$'}ANDROID_USB_MODES," in *",${'$'}mode,"*) return 0 ;; esac
          ;;
      esac
      return 1
    }
    stock_evidence() {
      for link in "${'$'}1"/configs/*/*; do
        [ -L "${'$'}link" ] && [ -d "${'$'}link" ] || continue
        target=${'$'}(readlink "${'$'}link") || continue
        if is_android_function "${'$'}{target##*/}" || matches_android_mode "${'$'}{target##*/}"; then
          printf linked
          return
        fi
      done
      for fn in "${'$'}1"/functions/*; do
        [ -d "${'$'}fn" ] || continue
        if is_android_function "${'$'}{fn##*/}"; then
          printf defined
          return
        fi
      done
      printf unknown
    }
  """.trimIndent()

  fun buildStockInventoryScript(): String = """
    $stockFunctionProbe
    printf 'android:%s\n' "${'$'}(getprop sys.usb.controller 2>/dev/null)"
    for controller in /sys/class/udc/*; do
      [ -d "${'$'}controller" ] || continue
      printf 'udc:%s\n' "${'$'}{controller##*/}"
    done
    for base in /config/usb_gadget /sys/kernel/config/usb_gadget; do
      found=0
      for g in "${'$'}base"/*; do
        [ -d "${'$'}g" ] || continue
        udc=${'$'}(cat "${'$'}g/UDC") || exit 1
        printf 'gadget:%s:%s:%s\n' "${'$'}{g##*/}" "${'$'}udc" "${'$'}(stock_evidence "${'$'}g")"
        found=1
      done
      [ "${'$'}found" = 0 ] || exit 0
    done
    exit 1
  """.trimIndent()

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
        printf 'state=%s\n' "${'$'}(cat "/sys/class/udc/${'$'}UDC_NAME/state" 2>/dev/null)"
        devices_ready=1
        for fn in ${prefix}0 ${prefix}1 ${prefix}2; do
          for link in "${'$'}G"/configs/*/"${'$'}fn"; do
            [ -L "${'$'}link" ] && [ -d "${'$'}link" ] || continue
            target=${'$'}(readlink "${'$'}link") || continue
            [ "${'$'}{target##*/}" = "${'$'}fn" ] || continue
            protocol=${'$'}(cat "${'$'}G/functions/${'$'}fn/protocol") || exit 2
            dev=${'$'}(cat "${'$'}G/functions/${'$'}fn/dev" 2>/dev/null)
            [ -c "/dev/hidg${'$'}{dev##*:}" ] || devices_ready=0
            printf '%s=%s:%s\n' "${'$'}fn" "${'$'}protocol" "${'$'}dev"
            break
          done
        done
        printf 'devices_ready=%s\n' "${'$'}devices_ready"
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

      # Never touch the USB device controller while a host is attached.
      # Unbinding the stock Android gadget under a live host can reset or
      # reboot the device on some platforms. Only detached UDCs are usable.
      DETACHED_UDCS=""
      for UDC_NAME in ${'$'}UDC_CANDIDATES; do
        HOST_STATE=${'$'}(cat "/sys/class/udc/${'$'}UDC_NAME/state" 2>/dev/null | tr -d '\r' | tr 'A-Z' 'a-z' | tr '-' ' ')
        if [ "${'$'}HOST_STATE" = "not attached" ] || [ "${'$'}HOST_STATE" = "disconnected" ] || [ "${'$'}HOST_STATE" = "unbound" ] || [ "${'$'}HOST_STATE" = "disabled" ]; then
          DETACHED_UDCS="${'$'}DETACHED_UDCS ${'$'}UDC_NAME"
        fi
      done
      if [ -z "${'$'}DETACHED_UDCS" ]; then
        echo "Unplug the USB data cable before switching the Android USB configuration, then retry." >&2
        exit $HOST_ATTACHED_REFUSED
      fi
      UDC_CANDIDATES="${'$'}DETACHED_UDCS"

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
      "keyboard" -> buildKeyboardFunctionScript("hid.usb0")
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

  fun buildUnbindAndCleanupScript(gadgetDir: String): String {
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

  fun buildAttachToStockScript(
    profile: ParsedProfile,
    gadgetDir: String,
    udc: String,
    originalUdc: String,
    usbDataMarker: String? = null,
  ): String {
    val composite = profile.roleType.lowercase(Locale.US) !in listOf("keyboard", "mouse")
    val mouse = profile.roleType.equals("mouse", ignoreCase = true)
    val names = when {
      mouse -> "hid.tapducky0"
      composite -> "hid.tapducky0 hid.tapducky1"
      else -> "hid.tapducky0"
    }
    val functions = when {
      mouse -> buildMouseFunctionScript("hid.tapducky0")
      composite -> listOf(
        buildKeyboardFunctionScript("hid.tapducky0"),
        buildMouseFunctionScript("hid.tapducky1"),
      ).joinToString("\n\n")
      else -> buildKeyboardFunctionScript("hid.tapducky0")
    }
    return """
      set -e
      ${stockGadgetLocation(gadgetDir)}
      UDC_NAME=${shEscape(udc)}
      ${usbDataFunctions(usbDataMarker)}
      LIVE_SETUP=0
      if ! usb_quiet; then
        [ -n "${'$'}USB_DATA_MARKER" ] && [ ! -e "${'$'}USB_DATA_MARKER" ] || exit $SETUP_NOT_STARTED
        [ "${'$'}(usb_port_status)" = enabled ] || exit $SETUP_NOT_STARTED
        LIVE_SETUP=1
      fi
      CURRENT_UDC=${'$'}(cat UDC) || exit $STOCK_BINDING_CHANGED
      if [ "${'$'}CURRENT_UDC" != ${shEscape(originalUdc)} ] ||
        { [ -n "${'$'}CURRENT_UDC" ] && [ "${'$'}CURRENT_UDC" != "${'$'}UDC_NAME" ]; }; then
        echo "Android changed the USB controller binding before setup" >&2
        exit $STOCK_BINDING_CHANGED
      fi
      set -- configs/*
      if [ "${'$'}#" -ne 1 ] || [ ! -d "${'$'}1" ]; then
        echo "Stock USB gadget must have exactly one configuration" >&2
        exit 25
      fi
      CFG="${'$'}1"
      if [ "${'$'}LIVE_SETUP" = 1 ]; then
        [ -n "${'$'}CURRENT_UDC" ] || exit $SETUP_NOT_STARTED
        for link in "${'$'}CFG"/*; do
          [ -L "${'$'}link" ] || continue
          target=${'$'}(readlink "${'$'}link") || exit $SETUP_NOT_STARTED
          case "${'$'}{target##*/}" in hid.*) exit $SETUP_NOT_STARTED ;; esac
        done
      fi
      $stockFunctionProbe
      if [ "${'$'}(stock_evidence .)" = unknown ]; then
        echo "The gadget no longer has recognizable Android stock USB functions" >&2
        exit $STOCK_BINDING_CHANGED
      fi
      check_controller_owner() {
        for other in ../*/UDC; do
          [ -f "${'$'}other" ] || continue
          owner=${'$'}{other%/UDC}
          [ "${'$'}{owner##*/}" != "${'$'}NAME" ] || continue
          binding=${'$'}(cat "${'$'}other") || return 1
          [ "${'$'}binding" != "${'$'}UDC_NAME" ] || return 1
        done
        return 0
      }
      check_controller_owner || exit $STOCK_BINDING_CHANGED
      for old in hid.tapducky0 hid.tapducky1 hid.tapducky2; do
        if [ -L "${'$'}CFG/${'$'}old" ]; then
          echo "Existing TapDucky links must be restored before creating a new layout" >&2
          exit 25
        fi
      done
      if [ -d functions/hid.tapducky2 ]; then rmdir functions/hid.tapducky2; fi
      # Prepare and validate descriptors while the stock functions are still available.
      $functions
      for fn in $names; do
        if [ "${'$'}LIVE_SETUP" = 1 ] &&
          [ "${'$'}(cat "functions/${'$'}fn/no_out_endpoint" 2>/dev/null)" != 1 ]; then
          echo "The kernel cannot configure input-only HID for a connected USB setup" >&2
          exit $HOST_ATTACHED_REFUSED
        fi
        dev=${'$'}(cat "functions/${'$'}fn/dev")
        case "${'$'}dev" in *:[0-9]*) ;; *) exit 25 ;; esac
        printf 'hid.usb%s=%s\n' "${'$'}{fn#hid.tapducky}" "${'$'}dev"
      done
      restore_stock_on_error() {
        rc=${'$'}?
        trap - EXIT
        if [ "${'$'}rc" -ne 0 ] && [ "${'$'}(cat UDC)" = "" ] && usb_quiet; then
          for fn in hid.tapducky0 hid.tapducky1 hid.tapducky2; do
            [ "${'$'}(cat UDC)" = "" ] && usb_quiet || break
            [ ! -L "${'$'}CFG/${'$'}fn" ] || rm "${'$'}CFG/${'$'}fn" || :
          done
          if [ -n "${'$'}CURRENT_UDC" ] && [ "${'$'}(cat UDC)" = "" ] && usb_quiet; then
            printf '%s\n' "${'$'}CURRENT_UDC" > UDC || :
          fi
        fi
        if [ "${'$'}rc" -ne 0 ] && [ "${'$'}LIVE_SETUP" = 1 ] && [ -f "${'$'}USB_DATA_MARKER" ] &&
          [ "${'$'}(usb_port_status)" = disabled-force ] && usb_controller_detached &&
          [ "${'$'}(cat UDC)" = "" ] && check_controller_owner; then
          any_hid_link=0
          for fn in $names; do
            if [ -L "${'$'}CFG/${'$'}fn" ]; then any_hid_link=1; break; fi
          done
          if [ "${'$'}any_hid_link" = 0 ]; then printf '%s\n' "${'$'}CURRENT_UDC" > UDC || :; fi
        fi
        resume_usb_data || exit $USB_DATA_RESTORE_FAILED
        exit "${'$'}rc"
      }
      trap restore_stock_on_error EXIT
      trap 'exit 1' HUP INT TERM
      if [ "${'$'}LIVE_SETUP" = 1 ]; then
        pause_usb_data || exit $HOST_ATTACHED_REFUSED
      else
        usb_quiet || exit $HOST_ATTACHED_REFUSED
      fi
      [ "${'$'}(cat UDC)" = "${'$'}CURRENT_UDC" ] || exit 25
      check_controller_owner || exit 25
      usb_controller_detached || exit $HOST_ATTACHED_REFUSED
      if [ -n "${'$'}CURRENT_UDC" ]; then
        printf '\n' > UDC
      fi
      for fn in $names; do
        ln -s "${'$'}G/functions/${'$'}fn" "${'$'}CFG/${'$'}fn"
      done
      if ! usb_controller_detached || { [ "${'$'}LIVE_SETUP" = 0 ] && ! usb_quiet; }; then
        echo "USB became active during preparation" >&2
        exit $HOST_ATTACHED_REFUSED
      fi
      if [ -z "${'$'}(cat UDC)" ]; then
        printf '%s\n' "${'$'}UDC_NAME" > UDC || [ "${'$'}(cat UDC)" = "${'$'}UDC_NAME" ]
      fi
      [ "${'$'}(cat UDC)" = "${'$'}UDC_NAME" ] || exit 25
    """.trimIndent() + "\n"
  }

  fun buildResumeUsbDataScript(marker: String): String = """
    ${usbDataFunctions(marker)}
    resume_usb_data
  """.trimIndent()

  private fun usbDataFunctions(marker: String?): String = """
    USB_DATA_MARKER=${shEscape(marker.orEmpty())}
    usb_port_status() {
      dumpsys -t 2 usb 2>/dev/null | sed -n 's/^[[:space:]]*usb_data_status=//p'
    }
    pause_usb_data() {
      [ -n "${'$'}USB_DATA_MARKER" ] && [ ! -e "${'$'}USB_DATA_MARKER" ] || return 1
      [ "${'$'}(usb_port_status)" = enabled ] || return 1
      (umask 077 && : > "${'$'}USB_DATA_MARKER") || return 1
      svc usb enableUsbDataSignal false || return 1
      count=0
      until usb_data_paused; do
        [ "${'$'}count" -lt 15 ] || return 1
        count=${'$'}((count + 1))
        sleep 0.15
      done
    }
    usb_data_paused() {
      [ -n "${'$'}USB_DATA_MARKER" ] && [ -f "${'$'}USB_DATA_MARKER" ] &&
        [ "${'$'}(usb_port_status)" = disabled-force ] && usb_controller_detached
    }
    resume_usb_data() {
      [ -n "${'$'}USB_DATA_MARKER" ] && [ -f "${'$'}USB_DATA_MARKER" ] || return 0
      case "${'$'}(usb_port_status)" in
        enabled) ;;
        disabled-force) svc usb enableUsbDataSignal true || return 1 ;;
        *) return 1 ;;
      esac
      count=0
      until [ "${'$'}(usb_port_status)" = enabled ]; do
        [ "${'$'}count" -lt 15 ] || return 1
        count=${'$'}((count + 1))
        sleep 0.15
      done
      rm "${'$'}USB_DATA_MARKER"
    }
  """.trimIndent()

  private fun stockGadgetLocation(gadgetDir: String): String = """
    NAME=${shEscape(sanitizeGadgetName(gadgetDir))}
    G="/config/usb_gadget/${'$'}NAME"
    [ -d "${'$'}G" ] || G="/sys/kernel/config/usb_gadget/${'$'}NAME"
    cd "${'$'}G"
  """.trimIndent()

  private val stockLayoutProbe = """
    stock_layout() {
      for name in sys.usb.config sys.usb.state persist.sys.usb.config; do
        printf '%s=%s\n' "${'$'}name" "${'$'}(getprop "${'$'}name")"
      done
      for descriptor in UDC idVendor idProduct bcdUSB bcdDevice bDeviceClass bDeviceSubClass bDeviceProtocol \
        configs/*/bmAttributes configs/*/MaxPower; do
        [ -f "${'$'}descriptor" ] || continue
        value=${'$'}(cat "${'$'}descriptor") || return 1
        printf '%s=%s\n' "${'$'}descriptor" "${'$'}value"
      done
      for link in configs/*/*; do
        [ -L "${'$'}link" ] || continue
        target=${'$'}(readlink "${'$'}link") || return 1
        case "${'$'}{target##*/}" in hid.tapducky0|hid.tapducky1|hid.tapducky2) continue ;; esac
        printf '%s=%s\n' "${'$'}link" "${'$'}target"
      done
    }
  """.trimIndent()

  fun buildReadStockLayoutScript(gadgetDir: String): String = """
    set -e
    export LC_ALL=C
    ${stockGadgetLocation(gadgetDir)}
    $stockLayoutProbe
    mode=${'$'}(svc usb getFunctions 2>/dev/null) || mode='?'
    case "${'$'}mode" in *[!a-z0-9_,]*) mode='?' ;; esac
    printf 'mode=%s\n' "${'$'}mode"
    stock_layout
  """.trimIndent()

  fun buildVerifyStockLayoutScript(gadgetDir: String, layout: String): String {
    val reportedMode = layout.lineSequence().first().removePrefix("mode=")
    val configuredMode = layout.lineSequence().firstOrNull { it.startsWith("sys.usb.config=") }
      ?.substringAfter('=')?.split(',')?.filterNot { it == "adb" || it == "none" }?.joinToString(",")
    val originalMode = reportedMode.takeUnless { it.isEmpty() || it == "?" } ?: configuredMode ?: reportedMode
    return """
    set -e
    export LC_ALL=C
    ${stockGadgetLocation(gadgetDir)}
    $stockLayoutProbe
    EXPECTED=${shEscape(layout.substringAfter('\n'))}
    ORIGINAL_MODE=${shEscape(originalMode)}
    matches_baseline() {
      actual=${'$'}(stock_layout) && [ "${'$'}actual" = "${'$'}EXPECTED" ]
    }
    if matches_baseline; then exit 0; fi
    case "${'$'}ORIGINAL_MODE" in
      *[!a-z0-9_,]*) ;;
      '') svc usb setFunctions || : ;;
      *) svc usb setFunctions "${'$'}ORIGINAL_MODE" || : ;;
    esac
    for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
      if matches_baseline; then exit 0; fi
      sleep 0.5
    done
    echo "Android has not restored the USB layout captured before arming" >&2
    exit 25
    """.trimIndent()
  }

  fun buildStockUsbTransaction(udc: String, operation: String): String = """
    UDC_NAME=${shEscape(udc)}
    usb_controller_detached() {
      [ "${'$'}(cat "/sys/class/udc/${'$'}UDC_NAME/state" 2>/dev/null)" = "not attached" ]
    }
    usb_quiet() {
      usb_controller_detached || return 1
      for partner in /sys/class/typec/*-partner; do
        [ ! -e "${'$'}partner" ] || return 1
      done
      for signal in present online; do
        [ "${'$'}(cat "/sys/class/power_supply/usb/${'$'}signal" 2>/dev/null)" != 1 ] || return 1
      done
    }
    $operation
  """.trimIndent()

  fun buildRestoreStockScript(gadgetDir: String, originalUdc: String, usbDataMarker: String? = null): String = """
    set -e
    ${stockGadgetLocation(gadgetDir)}
    ${usbDataFunctions(usbDataMarker)}
    ORIGINAL_UDC=${shEscape(originalUdc)}
    CURRENT_UDC=${'$'}(cat UDC)
    if [ -n "${'$'}CURRENT_UDC" ] && [ "${'$'}CURRENT_UDC" != "${'$'}UDC_NAME" ]; then
      exit 25
    fi
    ARTIFACTS=0
    for fn in functions/hid.tapducky0 functions/hid.tapducky1 functions/hid.tapducky2; do
      if [ -d "${'$'}fn" ]; then ARTIFACTS=1; break; fi
    done
    if [ "${'$'}ARTIFACTS" -eq 0 ] && [ "${'$'}CURRENT_UDC" = "${'$'}ORIGINAL_UDC" ]; then
      exit 0
    fi
    can_restore_binding() {
      usb_quiet || usb_data_paused
    }
    finish_restoration() {
      rc=${'$'}?
      trap - EXIT
      if [ "${'$'}BINDING_CHECK_NEEDED" = 1 ]; then
        BOUND_UDC=${'$'}(cat UDC) || rc=25
        if [ -n "${'$'}ORIGINAL_UDC" ] && [ -z "${'$'}BOUND_UDC" ]; then
          if can_restore_binding; then
            printf '%s\n' "${'$'}ORIGINAL_UDC" > UDC || :
          fi
          BOUND_UDC=${'$'}(cat UDC) || rc=25
        fi
        if [ "${'$'}BOUND_UDC" != "${'$'}ORIGINAL_UDC" ]; then
          echo "Android changed the USB controller binding during restoration" >&2
          rc=25
        fi
      fi
      resume_usb_data || exit $USB_DATA_RESTORE_FAILED
      exit "${'$'}rc"
    }
    set --
    for link in configs/*/hid.tapducky0 configs/*/hid.tapducky1 configs/*/hid.tapducky2; do
      if [ -L "${'$'}link" ]; then set -- "${'$'}@" "${'$'}link"; fi
    done
    BINDING_CHECK_NEEDED=0
    trap finish_restoration EXIT
    trap 'exit 1' HUP INT TERM
    if ! usb_quiet; then
      [ -n "${'$'}ORIGINAL_UDC" ] && [ "${'$'}CURRENT_UDC" = "${'$'}ORIGINAL_UDC" ] || exit $HOST_ATTACHED_REFUSED
      for link in configs/*/*; do
        [ -L "${'$'}link" ] || continue
        target=${'$'}(readlink "${'$'}link") || exit $HOST_ATTACHED_REFUSED
        case "${'$'}{target##*/}" in
          hid.tapducky0|hid.tapducky1|hid.tapducky2)
            [ "${'$'}(cat "${'$'}link/no_out_endpoint" 2>/dev/null)" = 1 ] || exit $HOST_ATTACHED_REFUSED
            ;;
          hid.*) exit $HOST_ATTACHED_REFUSED ;;
        esac
      done
      pause_usb_data || exit $HOST_ATTACHED_REFUSED
    fi
    can_restore_binding || exit $HOST_ATTACHED_REFUSED
    [ "${'$'}(cat UDC)" = "${'$'}CURRENT_UDC" ] || exit 25
    BINDING_CHECK_NEEDED=1
    if [ "${'$'}#" -gt 0 ]; then
      if [ -n "${'$'}CURRENT_UDC" ]; then
        printf '\n' > UDC
      fi
      [ -z "${'$'}(cat UDC)" ] || exit 25
      rm "${'$'}@"
    fi
    for fn in functions/hid.tapducky0 functions/hid.tapducky1 functions/hid.tapducky2; do
      if [ -d "${'$'}fn" ]; then rmdir "${'$'}fn"; fi
    done
  """.trimIndent() + "\n"

  private fun buildMouseFunctionScript(fn: String): String {
    return buildHidFunctionScript(
      fn = fn,
      protocol = 0,
      subclass = 0,
      reportLength = 5,
      descriptor = HidSpec.AUX_REPORT_DESC,
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
      if [ ! -d functions/$fn ]; then
        if ! mkdir functions/$fn; then
          echo "Cannot allocate USB HID function $fn. The kernel's HID function slots may all be in use (Android's stock USB can hold idle instances) or HID gadget support may be missing." >&2
          exit $HID_ALLOCATION_FAILED
        fi
      fi
      echo $protocol > functions/$fn/protocol
      echo $subclass > functions/$fn/subclass
      echo $reportLength > functions/$fn/report_length
      if [ -f functions/$fn/no_out_endpoint ]; then
        # The app sends reports to the host. Avoid queued interrupt OUT requests on disconnect.
        printf '1\n' > functions/$fn/no_out_endpoint
      fi
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
    ).joinToString("\n\n")
  }

  private fun expectedFunctionNames(roleType: String): List<String> {
    return when (roleType.lowercase(Locale.US)) {
      "mouse" -> listOf("hid.usb0")
      "keyboard" -> listOf("hid.usb0")
      else -> listOf("hid.usb0", "hid.usb1")
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
