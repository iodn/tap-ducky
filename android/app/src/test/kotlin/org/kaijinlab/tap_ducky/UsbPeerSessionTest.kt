package org.kaijinlab.tap_ducky

import org.junit.Assert.*
import org.junit.Test

class UsbPeerSessionTest {
    private val uuid = "1234567890abcdef1234567890abcdef"
    private fun row(function: String, gadget: String = "g1", controller: String = "dwc3") =
        "function:$gadget:$controller:$function\n"

    @Test fun distinguishesOwnAndForeignSessions() {
        val peers = UsbPeerSession.parse(row("hid.tapducky0") + row("hid.hidwiggle1") +
            row("hid.gadgetfs2"))
        assertEquals(listOf("tapducky", "hidwiggle", "gadgetfs"), peers.map { it.owner })
        assertEquals(listOf("TapDucky", "HID Wiggle", "GadgetFS"), peers.map { it.displayName })
        for (owner in peers.map { it.owner }) {
            assertEquals(2, peers.count { it.owner != owner })
        }
    }

    @Test fun groupsFunctionsAndDeduplicatesAliasesAndConfigs() {
        val peers = UsbPeerSession.parse(row("hid.tapducky0") + row("hid.tapducky0") +
            row("hid.tapducky1"))
        assertEquals(1, peers.size)
        assertEquals(setOf("hid.tapducky0", "hid.tapducky1"), peers.single().functions)
        assertEquals("g1", peers.single().gadget)
        assertEquals("dwc3", peers.single().controller)
    }

    @Test fun detectsSeparateDirectoryOwners() {
        for ((directory, owner) in listOf(
            "gadgetfs_$uuid" to "tapducky",
            "gadgetfs_hidwiggle_$uuid" to "hidwiggle",
            "gadgetfs_gadgetfs_$uuid" to "gadgetfs",
            "gadgetfs_12345678-1234-1234-1234-123456789abc" to "tapducky",
        )) {
            assertEquals(owner, UsbPeerSession.parse(row("hid.usb0", directory)).single().owner)
        }
        assertEquals("other", UsbPeerSession.parse(row("hid.usb0", "gadgetfs_not_uuid")).single().owner)
    }

    @Test fun detectsGadgetFsNonHidFunctionsAndSeparateCtap() {
        for (function in listOf("acm.gadgetfs0", "ccid.gadgetfs0", "uvc.gadgetfs0")) {
            assertEquals("gadgetfs", UsbPeerSession.parse(row(function)).single().owner)
        }
        for (function in listOf("acm.usb0", "ccid.usb0", "uvc.usb0", "hid.ctap")) {
            assertEquals("gadgetfs", UsbPeerSession.parse(
                row(function, "gadgetfs_gadgetfs_$uuid")).single().owner)
        }
    }

    @Test fun keepsMixedAndConflictingOwnershipVisible() {
        val peers = UsbPeerSession.parse(row("hid.hidwiggle0", "gadgetfs_$uuid") +
            row("hid.vendor", "gadgetfs_$uuid"))
        assertEquals(setOf("tapducky", "hidwiggle", "other"), peers.map { it.owner }.toSet())
        assertTrue(peers.any { it.owner != "tapducky" })
    }

    @Test fun retainsUnboundLinkedResidue() {
        val peer = UsbPeerSession.parse(row("hid.tapducky2", controller = "")).single()
        assertEquals("tapducky", peer.owner)
        assertEquals("", peer.controller)
    }

    @Test fun unknownHidIsNotStockAndNearMatchesAreNotTrusted() {
        for (function in listOf("hid.vendor0", "hid.usb0", "hid.tapducky3", "hidXtapducky0")) {
            val peers = UsbPeerSession.parse(row(function))
            if (function.startsWith("hid.")) {
                assertEquals("other", peers.single().owner)
                assertEquals("Other USB app", peers.single().displayName)
            } else {
                assertTrue(peers.isEmpty())
            }
        }
    }

    @Test fun ignoresGenericStockFunctions() {
        assertTrue(UsbPeerSession.parse(row("ffs.adb") + row("mtp.gs0") + row("acm.usb0")).isEmpty())
        assertTrue(UsbPeerSession.parse("").isEmpty())
    }

    @Test fun rejectsMalformedRowsAndPaths() {
        for (invalid in listOf(
            "garbage", "function:g1:dwc3", "function:g1:dwc3:hid.usb0:extra",
            "function:../g1:dwc3:hid.usb0", "function:/config/usb_gadget/g1:dwc3:hid.usb0",
            "function:g1:../dwc3:hid.usb0", "function:g1:dwc3:../hid.usb0",
            "function:.:dwc3:hid.usb0", "function:g1:..:hid.usb0",
            "function:g1:dwc3:", "function:g1:dwc3:hid.usb0;id",
            "function:g1:dwc3:hid.usb0\t", "function::dwc3:hid.usb0",
        )) {
            assertThrows(invalid, IllegalArgumentException::class.java) {
                UsbPeerSession.parse(row("hid.tapducky0") + invalid)
            }
        }
    }

    @Test fun scriptOnlyInventoriesCanonicalLinkedFunctionsWithoutBindingFilter() {
        val script = UsbPeerSession.buildInventoryScript()
        assertTrue(script.contains("/config/usb_gadget /sys/kernel/config/usb_gadget"))
        assertTrue(script.contains("[ -L \"${'$'}link\" ] && [ -d \"${'$'}link\" ]"))
        assertTrue(script.contains("[ \"${'$'}target\" = \"${'$'}gadget/functions/${'$'}function\" ]"))
        assertTrue(script.contains("readlink -f"))
        assertFalse(script.contains("[ -n \"${'$'}controller\" ] || continue"))
        assertFalse(Regex("\\b(rm|rmdir|mkdir|ln|mount|setprop|echo)\\b|>>?").containsMatchIn(script))
        assertFalse(script.contains("/data/"))
    }
}
