package org.kaijinlab.tap_ducky

/** Observed ownership, not permission to adopt or modify a gadget. Empty controller means residue. */
data class UsbPeerSession(
    val owner: String,
    val displayName: String,
    val gadget: String,
    val controller: String,
    val functions: Set<String>,
) {
    companion object {
        private val name = Regex("[A-Za-z0-9._-]+")
        private val uuid = "(?:[0-9a-fA-F]{32}|[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})"
        private val separate = Regex("gadgetfs_(?:(hidwiggle|gadgetfs)_)?$uuid")
        private val labels = mapOf(
            "tapducky" to "TapDucky",
            "hidwiggle" to "HID Wiggle",
            "gadgetfs" to "GadgetFS",
            "other" to "Other USB app",
        )

        /** Run as root; read-only. Rows are function:gadget:controller:function (no paths). */
        fun buildInventoryScript(): String = """
            valid_name() {
              case "${'$'}1" in ''|.|..|*[!A-Za-z0-9._-]*) return 1 ;; esac
            }
            found=0
            for candidate in /config/usb_gadget /sys/kernel/config/usb_gadget; do
              [ -d "${'$'}candidate" ] || continue
              base=${'$'}(readlink -f "${'$'}candidate") || exit 1
              found=1
              for entry in "${'$'}base"/*; do
                [ -d "${'$'}entry" ] || continue
                gadget=${'$'}(readlink -f "${'$'}entry") || continue
                name=${'$'}{entry##*/}
                valid_name "${'$'}name" || continue
                [ "${'$'}gadget" = "${'$'}base/${'$'}name" ] || continue
                controller=${'$'}(cat "${'$'}gadget/UDC") || exit 1
                if [ -n "${'$'}controller" ]; then valid_name "${'$'}controller" || exit 1; fi
                for config in "${'$'}gadget"/configs/*; do
                  [ -d "${'$'}config" ] || continue
                  config_name=${'$'}{config##*/}
                  valid_name "${'$'}config_name" || continue
                  canonical_config=${'$'}(readlink -f "${'$'}config") || continue
                  [ "${'$'}canonical_config" = "${'$'}gadget/configs/${'$'}config_name" ] || continue
                  for link in "${'$'}config"/*; do
                    [ -L "${'$'}link" ] && [ -d "${'$'}link" ] || continue
                    target=${'$'}(readlink -f "${'$'}link") || continue
                    function=${'$'}{target##*/}
                    valid_name "${'$'}function" || continue
                    [ "${'$'}target" = "${'$'}gadget/functions/${'$'}function" ] || continue
                    printf 'function:%s:%s:%s\n' "${'$'}name" "${'$'}controller" "${'$'}function"
                  done
                done
              done
            done
            [ "${'$'}found" = 1 ]
        """.trimIndent()

        /** Reject invalid inventory rather than presenting a partial inventory as safe. */
        fun parse(output: String): List<UsbPeerSession> {
            val sessions = linkedMapOf<Triple<String, String, String>, MutableSet<String>>()
            for (line in output.lineSequence().filter { it.isNotEmpty() }) {
                val fields = line.split(':')
                require(fields.size == 4 && fields[0] == "function") { "Invalid USB peer row" }
                val (_, gadget, controller, function) = fields
                fun valid(value: String) = name.matches(value) && value != "." && value != ".."
                require(valid(gadget) && (controller.isEmpty() || valid(controller)) &&
                    valid(function)) { "Invalid USB peer name" }
                val directoryOwner = separate.matchEntire(gadget)?.let {
                    it.groupValues[1].ifEmpty { "tapducky" }
                }
                val functionOwner = when {
                    function.matches(Regex("hid\\.tapducky[0-2]")) -> "tapducky"
                    function.matches(Regex("hid\\.hidwiggle[0-2]")) -> "hidwiggle"
                    function.matches(Regex("hid\\.gadgetfs[0-2]|(?:acm|ccid|uvc)\\.gadgetfs0")) -> "gadgetfs"
                    directoryOwner != null && function.matches(Regex("hid\\.usb[A-Za-z0-9_-]+")) ->
                        directoryOwner
                    directoryOwner == "gadgetfs" && function == "hid.ctap" -> directoryOwner
                    function.startsWith("hid.") -> "other"
                    else -> null
                }
                // Preserve conflicting evidence: never let an own marker hide a foreign marker.
                for (owner in listOfNotNull(directoryOwner, functionOwner).distinct()) {
                    sessions.getOrPut(Triple(owner, gadget, controller)) { linkedSetOf() }.add(function)
                }
            }
            return sessions.map { (key, functions) ->
                UsbPeerSession(key.first, labels.getValue(key.first), key.second, key.third, functions.toSet())
            }
        }
    }
}
