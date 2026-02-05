package org.kaijinlab.tap_ducky

import java.util.Locale

object HidSpec {
    val MOUSE_REPORT_DESC: ByteArray = byteArrayOf(
        0x05, 0x01,
        0x09, 0x02,
        0xA1.toByte(), 0x01,
        0x09, 0x01,
        0xA1.toByte(), 0x00,
        0x05, 0x09,
        0x19, 0x01,
        0x29, 0x03,
        0x15, 0x00,
        0x25, 0x01,
        0x95.toByte(), 0x03,
        0x75, 0x01,
        0x81.toByte(), 0x02,
        0x95.toByte(), 0x01,
        0x75, 0x05,
        0x81.toByte(), 0x03,
        0x05, 0x01,
        0x09, 0x30,
        0x09, 0x31,
        0x09, 0x38,
        0x15, 0x81.toByte(),
        0x25, 0x7F,
        0x75, 0x08,
        0x95.toByte(), 0x03,
        0x81.toByte(), 0x06,
        0xC0.toByte(),
        0xC0.toByte(),
    )

    val KEYBOARD_REPORT_DESC: ByteArray = byteArrayOf(
        0x05, 0x01,
        0x09, 0x06,
        0xA1.toByte(), 0x01,
        0x05, 0x07,
        0x19, 0xE0.toByte(),
        0x29, 0xE7.toByte(),
        0x15, 0x00,
        0x25, 0x01,
        0x75, 0x01,
        0x95.toByte(), 0x08,
        0x81.toByte(), 0x02,
        0x95.toByte(), 0x01,
        0x75, 0x08,
        0x81.toByte(), 0x03,
        0x95.toByte(), 0x05,
        0x75, 0x01,
        0x05, 0x08,
        0x19, 0x01,
        0x29, 0x05,
        0x91.toByte(), 0x02,
        0x95.toByte(), 0x01,
        0x75, 0x03,
        0x91.toByte(), 0x03,
        0x95.toByte(), 0x06,
        0x75, 0x08,
        0x15, 0x00,
        0x25, 0x65,
        0x05, 0x07,
        0x19, 0x00,
        0x29, 0x65,
        0x81.toByte(), 0x00,
        0xC0.toByte(),
    )

    const val MOD_LEFT_CTRL = 0x01
    const val MOD_LEFT_SHIFT = 0x02
    const val MOD_LEFT_ALT = 0x04
    const val MOD_LEFT_GUI = 0x08
    const val MOD_RIGHT_CTRL = 0x10
    const val MOD_RIGHT_SHIFT = 0x20
    const val MOD_RIGHT_ALT = 0x40
    const val MOD_RIGHT_GUI = 0x80

    fun modifierFor(label: String): Int? {
        return when (label.trim().uppercase(Locale.US)) {
            "CTRL", "CONTROL" -> MOD_LEFT_CTRL
            "SHIFT" -> MOD_LEFT_SHIFT
            "ALT" -> MOD_LEFT_ALT
            "GUI", "WINDOWS", "COMMAND", "WIN" -> MOD_LEFT_GUI
            "RCTRL", "RCONTROL" -> MOD_RIGHT_CTRL
            "RSHIFT" -> MOD_RIGHT_SHIFT
            "RALT" -> MOD_RIGHT_ALT
            "RGUI", "RWINDOWS", "RCOMMAND" -> MOD_RIGHT_GUI
            else -> null
        }
    }

    fun keyCodeFor(label: String): Int? {
        val k = label.trim().uppercase(Locale.US).replace("_", "")
        if (k.length == 1) {
            val c = k[0]
            if (c in 'A'..'Z') {
                return 0x04 + (c.code - 'A'.code)
            }
            if (c in '0'..'9') {
                return when (c) {
                    '1' -> 0x1E
                    '2' -> 0x1F
                    '3' -> 0x20
                    '4' -> 0x21
                    '5' -> 0x22
                    '6' -> 0x23
                    '7' -> 0x24
                    '8' -> 0x25
                    '9' -> 0x26
                    '0' -> 0x27
                    else -> null
                }
            }
        }
        return when (k) {
            "ENTER" -> 0x28
            "ESC", "ESCAPE" -> 0x29
            "BACKSPACE", "BKSP" -> 0x2A
            "TAB" -> 0x2B
            "SPACE" -> 0x2C
            "DELETE", "DEL" -> 0x4C
            "UP", "UPARROW" -> 0x52
            "DOWN", "DOWNARROW" -> 0x51
            "LEFT", "LEFTARROW" -> 0x50
            "RIGHT", "RIGHTARROW" -> 0x4F
            "HOME" -> 0x4A
            "END" -> 0x4D
            "PAGEUP" -> 0x4B
            "PAGEDOWN" -> 0x4E
            "INSERT", "INS" -> 0x49
            "F1" -> 0x3A
            "F2" -> 0x3B
            "F3" -> 0x3C
            "F4" -> 0x3D
            "F5" -> 0x3E
            "F6" -> 0x3F
            "F7" -> 0x40
            "F8" -> 0x41
            "F9" -> 0x42
            "F10" -> 0x43
            "F11" -> 0x44
            "F12" -> 0x45
            "PRINTSCREEN", "PRTSCN" -> 0x46
            "SCROLLLOCK" -> 0x47
            "PAUSE", "BREAK" -> 0x48
            "CAPSLOCK" -> 0x39
            "NUMLOCK" -> 0x53
            "MENU", "APP" -> 0x65
            else -> null
        }
    }
}
