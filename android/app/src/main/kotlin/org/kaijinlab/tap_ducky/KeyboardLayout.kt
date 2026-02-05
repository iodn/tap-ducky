package org.kaijinlab.tap_ducky

import java.util.Locale

data class KeyStroke(val modifiers: Int, val keyCode: Int)

object KeyboardLayout {
    const val LAYOUT_US = 0
    const val LAYOUT_TR = 1
    const val LAYOUT_SV = 2
    const val LAYOUT_SI = 3
    const val LAYOUT_RU = 4
    const val LAYOUT_PT = 5
    const val LAYOUT_NO = 6
    const val LAYOUT_IT = 7
    const val LAYOUT_HR = 8
    const val LAYOUT_GB = 9
    const val LAYOUT_FR = 10
    const val LAYOUT_FI = 11
    const val LAYOUT_ES = 12
    const val LAYOUT_DK = 13
    const val LAYOUT_DE = 14
    const val LAYOUT_CA = 15
    const val LAYOUT_BR = 16
    const val LAYOUT_BE = 17
    const val LAYOUT_HU = 18

    private val layoutNames = mapOf(
        LAYOUT_US to "US (QWERTY)",
        LAYOUT_TR to "Turkish",
        LAYOUT_SV to "Swedish",
        LAYOUT_SI to "Slovenian",
        LAYOUT_RU to "Russian",
        LAYOUT_PT to "Portuguese",
        LAYOUT_NO to "Norwegian",
        LAYOUT_IT to "Italian",
        LAYOUT_HR to "Croatian",
        LAYOUT_GB to "UK (QWERTY)",
        LAYOUT_FR to "French (AZERTY)",
        LAYOUT_FI to "Finnish",
        LAYOUT_ES to "Spanish",
        LAYOUT_DK to "Danish",
        LAYOUT_DE to "German (QWERTZ)",
        LAYOUT_CA to "Canadian",
        LAYOUT_BR to "Brazilian",
        LAYOUT_BE to "Belgian",
        LAYOUT_HU to "Hungarian"
    )

    fun getLayoutName(layout: Int): String = layoutNames[layout] ?: "Unknown"
    fun getAllLayouts(): List<Pair<Int, String>> = layoutNames.toList()
}

class KeyboardMapper(private val layout: Int) {
    private val charMap = mutableMapOf<Char, KeyStroke>()

    private companion object {
        const val MOD_NONE = 0x00
        const val MOD_LSHIFT = 0x02
        const val MOD_RALT = 0x40
        const val MOD_SHIFT_RALT = MOD_LSHIFT or MOD_RALT
    }

    init {
        initializeLayout()
    }

    private fun initializeLayout() {
        when (layout) {
            KeyboardLayout.LAYOUT_US -> initUS()
            KeyboardLayout.LAYOUT_TR -> initTR()
            KeyboardLayout.LAYOUT_SV -> initSV()
            KeyboardLayout.LAYOUT_SI -> initSI()
            KeyboardLayout.LAYOUT_RU -> initRU()
            KeyboardLayout.LAYOUT_PT -> initPT()
            KeyboardLayout.LAYOUT_NO -> initNO()
            KeyboardLayout.LAYOUT_IT -> initIT()
            KeyboardLayout.LAYOUT_HR -> initHR()
            KeyboardLayout.LAYOUT_GB -> initGB()
            KeyboardLayout.LAYOUT_FR -> initFR()
            KeyboardLayout.LAYOUT_FI -> initFI()
            KeyboardLayout.LAYOUT_ES -> initES()
            KeyboardLayout.LAYOUT_DK -> initDK()
            KeyboardLayout.LAYOUT_DE -> initDE()
            KeyboardLayout.LAYOUT_CA -> initCA()
            KeyboardLayout.LAYOUT_BR -> initBR()
            KeyboardLayout.LAYOUT_BE -> initBE()
            KeyboardLayout.LAYOUT_HU -> initHU()
            else -> initUS()
        }
    }

    fun getStrokeForChar(ch: Char): KeyStroke? = charMap[ch]

    private fun map(ch: Char, keyCode: Int, modifiers: Int = MOD_NONE) {
        charMap[ch] = KeyStroke(modifiers, keyCode)
    }

    private fun mapCase(lower: Char, upper: Char, keyCode: Int, lowerMods: Int = MOD_NONE, upperMods: Int = MOD_LSHIFT) {
        map(lower, keyCode, lowerMods)
        map(upper, keyCode, upperMods)
    }

    private fun mapLettersUSQwerty() {
        mapCase('a', 'A', 0x04)
        mapCase('b', 'B', 0x05)
        mapCase('c', 'C', 0x06)
        mapCase('d', 'D', 0x07)
        mapCase('e', 'E', 0x08)
        mapCase('f', 'F', 0x09)
        mapCase('g', 'G', 0x0A)
        mapCase('h', 'H', 0x0B)
        mapCase('i', 'I', 0x0C)
        mapCase('j', 'J', 0x0D)
        mapCase('k', 'K', 0x0E)
        mapCase('l', 'L', 0x0F)
        mapCase('m', 'M', 0x10)
        mapCase('n', 'N', 0x11)
        mapCase('o', 'O', 0x12)
        mapCase('p', 'P', 0x13)
        mapCase('q', 'Q', 0x14)
        mapCase('r', 'R', 0x15)
        mapCase('s', 'S', 0x16)
        mapCase('t', 'T', 0x17)
        mapCase('u', 'U', 0x18)
        mapCase('v', 'V', 0x19)
        mapCase('w', 'W', 0x1A)
        mapCase('x', 'X', 0x1B)
        mapCase('y', 'Y', 0x1C)
        mapCase('z', 'Z', 0x1D)
    }

    private fun mapCommonControls() {
        map('\n', 0x28)
        map('\r', 0x28)
        map('\t', 0x2B)
        map('\b', 0x2A)
        map(' ', 0x2C)
    }

    private fun initUS() {
        map(' ', 0x2C)
        map('!', 0x1E, MOD_LSHIFT)
        map('"', 0x34, MOD_LSHIFT)
        map('#', 0x20, MOD_LSHIFT)
        map('$', 0x21, MOD_LSHIFT)
        map('%', 0x22, MOD_LSHIFT)
        map('&', 0x24, MOD_LSHIFT)
        map('\'', 0x34)
        map('(', 0x26, MOD_LSHIFT)
        map(')', 0x27, MOD_LSHIFT)
        map('*', 0x25, MOD_LSHIFT)
        map('+', 0x2E, MOD_LSHIFT)
        map(',', 0x36)
        map('-', 0x2D)
        map('.', 0x37)
        map('/', 0x38)
        map('0', 0x27)
        map('1', 0x1E)
        map('2', 0x1F)
        map('3', 0x20)
        map('4', 0x21)
        map('5', 0x22)
        map('6', 0x23)
        map('7', 0x24)
        map('8', 0x25)
        map('9', 0x26)
        map(':', 0x33, MOD_LSHIFT)
        map(';', 0x33)
        map('<', 0x36, MOD_LSHIFT)
        map('=', 0x2E)
        map('>', 0x37, MOD_LSHIFT)
        map('?', 0x38, MOD_LSHIFT)
        map('@', 0x1F, MOD_LSHIFT)
        mapLettersUSQwerty()
        map('[', 0x2F)
        map('\\', 0x31)
        map(']', 0x30)
        map('^', 0x23, MOD_LSHIFT)
        map('_', 0x2D, MOD_LSHIFT)
        map('`', 0x35)
        map('{', 0x2F, MOD_LSHIFT)
        map('|', 0x31, MOD_LSHIFT)
        map('}', 0x30, MOD_LSHIFT)
        map('~', 0x35, MOD_LSHIFT)
        mapCommonControls()
        map('€', 0x08, MOD_RALT)
        map('£', 0x20, MOD_RALT)
        map('¥', 0x1C, MOD_RALT)
        map('§', 0x21, MOD_RALT)
        map('°', 0x27, MOD_RALT)
        map('µ', 0x10, MOD_RALT)
    }

    private fun initTR() {
        initUS()
        map('€', 0x08, MOD_RALT)
        map('@', 0x14, MOD_RALT)
        mapCase('ğ', 'Ğ', 0x2F)
        mapCase('ü', 'Ü', 0x30)
        mapCase('ş', 'Ş', 0x33)
        mapCase('i', 'İ', 0x34)
        mapCase('ı', 'I', 0x0C)
        mapCase('ö', 'Ö', 0x36)
        mapCase('ç', 'Ç', 0x37)
    }

    private fun initSV() {
        initUS()
        map('€', 0x08, MOD_RALT)
        map('@', 0x1F, MOD_RALT)
        map('{', 0x24, MOD_RALT)
        map('[', 0x25, MOD_RALT)
        map(']', 0x26, MOD_RALT)
        map('}', 0x27, MOD_RALT)
        map('\\', 0x2E, MOD_RALT)
        map('|', 0x64, MOD_RALT)
        map('~', 0x30, MOD_RALT)
        mapCase('å', 'Å', 0x2F)
        mapCase('ö', 'Ö', 0x33)
        mapCase('ä', 'Ä', 0x34)
        map('´', 0x30)
        map('`', 0x30, MOD_LSHIFT)
        map('^', 0x2F, MOD_LSHIFT)
    }

    private fun initFI() {
        initSV()
    }

    private fun initNO() {
        initUS()
        map('€', 0x08, MOD_RALT)
        map('@', 0x1F, MOD_RALT)
        map('{', 0x24, MOD_RALT)
        map('[', 0x25, MOD_RALT)
        map(']', 0x26, MOD_RALT)
        map('}', 0x27, MOD_RALT)
        map('\\', 0x2E, MOD_RALT)
        map('|', 0x64, MOD_RALT)
        map('~', 0x30, MOD_RALT)
        mapCase('å', 'Å', 0x2F)
        mapCase('ø', 'Ø', 0x33)
        mapCase('æ', 'Æ', 0x34)
    }

    private fun initDK() {
        initNO()
        mapCase('ø', 'Ø', 0x33)
        mapCase('æ', 'Æ', 0x34)
        mapCase('å', 'Å', 0x2F)
    }

    private fun initDE() {
        initUS()
        mapCase('y', 'Y', 0x1D)
        mapCase('z', 'Z', 0x1C)
        mapCase('ü', 'Ü', 0x2F)
        mapCase('ö', 'Ö', 0x33)
        mapCase('ä', 'Ä', 0x34)
        map('ß', 0x2D)
        map('?', 0x2D, MOD_LSHIFT)
        map('@', 0x14, MOD_RALT)
        map('€', 0x08, MOD_RALT)
        map('{', 0x24, MOD_RALT)
        map('[', 0x25, MOD_RALT)
        map(']', 0x26, MOD_RALT)
        map('}', 0x27, MOD_RALT)
        map('\\', 0x2D, MOD_RALT)
        map('|', 0x64, MOD_RALT)
        map('/', 0x24, MOD_LSHIFT)
        map('(', 0x25, MOD_LSHIFT)
        map(')', 0x26, MOD_LSHIFT)
        map('=', 0x27, MOD_LSHIFT)
        map('-', 0x38)
        map('_', 0x38, MOD_LSHIFT)
    }

    private fun initES() {
        initUS()
        map('€', 0x08, MOD_RALT)
        map('@', 0x1F, MOD_RALT)
        mapCase('ñ', 'Ñ', 0x33)
        map('¡', 0x2E)
        map('¿', 0x38, MOD_LSHIFT)
        map('\\', 0x35, MOD_RALT)
        map('|', 0x64, MOD_RALT)
        map('{', 0x24, MOD_RALT)
        map('[', 0x25, MOD_RALT)
        map(']', 0x26, MOD_RALT)
        map('}', 0x27, MOD_RALT)
    }

    private fun initPT() {
        initUS()
        map('€', 0x08, MOD_RALT)
        map('@', 0x1F, MOD_RALT)
        mapCase('ç', 'Ç', 0x33)
        mapCase('º', 'ª', 0x35)
        map('\\', 0x35, MOD_RALT)
        map('|', 0x64, MOD_RALT)
        map('{', 0x24, MOD_RALT)
        map('[', 0x25, MOD_RALT)
        map(']', 0x26, MOD_RALT)
        map('}', 0x27, MOD_RALT)
    }

    private fun initIT() {
        initUS()
        map('€', 0x08, MOD_RALT)
        map('@', 0x14, MOD_RALT)
        mapCase('è', 'É', 0x2F)
        mapCase('ì', 'Ì', 0x30)
        mapCase('ò', 'Ò', 0x33)
        mapCase('à', 'À', 0x34)
        mapCase('ù', 'Ù', 0x2D)
        map('{', 0x24, MOD_RALT)
        map('[', 0x25, MOD_RALT)
        map(']', 0x26, MOD_RALT)
        map('}', 0x27, MOD_RALT)
        map('\\', 0x2D, MOD_RALT)
        map('|', 0x64, MOD_RALT)
    }

    private fun initHR() {
        initDE()
        mapCase('š', 'Š', 0x2F)
        mapCase('đ', 'Đ', 0x30)
        mapCase('č', 'Č', 0x33)
        mapCase('ć', 'Ć', 0x34)
        mapCase('ž', 'Ž', 0x2D, MOD_RALT, MOD_SHIFT_RALT)
        map('€', 0x08, MOD_RALT)
    }

    private fun initSI() {
        initHR()
    }

    private fun initFR() {
        initUS()
        mapCase('a', 'A', 0x14)
        mapCase('z', 'Z', 0x1A)
        mapCase('q', 'Q', 0x04)
        mapCase('w', 'W', 0x1D)
        mapCase('m', 'M', 0x33)

        map('&', 0x1E)
        map('1', 0x1E, MOD_LSHIFT)
        map('é', 0x1F)
        map('2', 0x1F, MOD_LSHIFT)
        map('"', 0x20)
        map('3', 0x20, MOD_LSHIFT)
        map('\'', 0x21)
        map('4', 0x21, MOD_LSHIFT)
        map('(', 0x22)
        map('5', 0x22, MOD_LSHIFT)
        map('-', 0x23)
        map('6', 0x23, MOD_LSHIFT)
        map('è', 0x24)
        map('7', 0x24, MOD_LSHIFT)
        map('_', 0x25)
        map('8', 0x25, MOD_LSHIFT)
        map('ç', 0x26)
        map('9', 0x26, MOD_LSHIFT)
        map('à', 0x27)
        map('0', 0x27, MOD_LSHIFT)
        map(')', 0x2D)
        map('°', 0x2D, MOD_LSHIFT)
        map('=', 0x2E)
        map('+', 0x2E, MOD_LSHIFT)

        map('^', 0x2F)
        map('¨', 0x2F, MOD_LSHIFT)
        map('$', 0x30)
        map('£', 0x30, MOD_LSHIFT)

        map('ù', 0x34)
        map('%', 0x34, MOD_LSHIFT)

        map(',', 0x10)
        map('?', 0x10, MOD_LSHIFT)
        map(';', 0x36)
        map('.', 0x36, MOD_LSHIFT)
        map(':', 0x37)
        map('/', 0x37, MOD_LSHIFT)
        map('!', 0x38)
        map('§', 0x38, MOD_LSHIFT)

        map('<', 0x64)
        map('>', 0x64, MOD_LSHIFT)
        map('|', 0x64, MOD_RALT)

        map('@', 0x27, MOD_RALT)
        map('€', 0x08, MOD_RALT)

        map('{', 0x21, MOD_RALT)
        map('[', 0x22, MOD_RALT)
        map(']', 0x2D, MOD_RALT)
        map('}', 0x2E, MOD_RALT)
        map('\\', 0x23, MOD_RALT)
        map('~', 0x1F, MOD_RALT)
        map('`', 0x24, MOD_RALT)
        map('#', 0x20, MOD_RALT)
    }

    private fun initBE() {
        initFR()
        map('@', 0x1F, MOD_RALT)
        map('€', 0x08, MOD_RALT)
    }

    private fun initGB() {
        initUS()
        map('"', 0x1F, MOD_LSHIFT)
        map('@', 0x34, MOD_LSHIFT)
        map('\\', 0x64)
        map('|', 0x64, MOD_LSHIFT)
        map('#', 0x32)
        map('~', 0x32, MOD_LSHIFT)
        map('£', 0x20, MOD_LSHIFT)
        map('€', 0x21, MOD_RALT)
    }

    private fun initCA() {
        initUS()
        map('€', 0x08, MOD_RALT)
        mapCase('é', 'É', 0x08, MOD_RALT, MOD_SHIFT_RALT)
        mapCase('à', 'À', 0x04, MOD_RALT, MOD_SHIFT_RALT)
        mapCase('è', 'È', 0x15, MOD_RALT, MOD_SHIFT_RALT)
        mapCase('ç', 'Ç', 0x06, MOD_RALT, MOD_SHIFT_RALT)
        mapCase('ù', 'Ù', 0x18, MOD_RALT, MOD_SHIFT_RALT)
    }

    private fun initBR() {
        initUS()
        map('€', 0x08, MOD_RALT)
        map('@', 0x14, MOD_RALT)
        mapCase('ç', 'Ç', 0x33)
        mapCase('ã', 'Ã', 0x04, MOD_RALT, MOD_SHIFT_RALT)
        mapCase('õ', 'Õ', 0x12, MOD_RALT, MOD_SHIFT_RALT)
    }

    private fun initHU() {
        initDE()
        mapCase('ö', 'Ö', 0x33)
        mapCase('ü', 'Ü', 0x34)
        mapCase('ó', 'Ó', 0x2F)
        mapCase('ő', 'Ő', 0x30)
        mapCase('á', 'Á', 0x31, MOD_RALT, MOD_SHIFT_RALT)
        mapCase('é', 'É', 0x08, MOD_RALT, MOD_SHIFT_RALT)
        mapCase('í', 'Í', 0x0C, MOD_RALT, MOD_SHIFT_RALT)
        mapCase('ú', 'Ú', 0x18, MOD_RALT, MOD_SHIFT_RALT)
        mapCase('ű', 'Ű', 0x2D, MOD_RALT, MOD_SHIFT_RALT)
        map('€', 0x08, MOD_RALT)
    }

    private fun initRU() {
        initUS()
        mapCase('й', 'Й', 0x14)
        mapCase('ц', 'Ц', 0x1A)
        mapCase('у', 'У', 0x08)
        mapCase('к', 'К', 0x15)
        mapCase('е', 'Е', 0x17)
        mapCase('н', 'Н', 0x1C)
        mapCase('г', 'Г', 0x18)
        mapCase('ш', 'Ш', 0x0C)
        mapCase('щ', 'Щ', 0x12)
        mapCase('з', 'З', 0x13)
        mapCase('х', 'Х', 0x2F)
        mapCase('ъ', 'Ъ', 0x30)

        mapCase('ф', 'Ф', 0x04)
        mapCase('ы', 'Ы', 0x16)
        mapCase('в', 'В', 0x07)
        mapCase('а', 'А', 0x09)
        mapCase('п', 'П', 0x0A)
        mapCase('р', 'Р', 0x0B)
        mapCase('о', 'О', 0x0D)
        mapCase('л', 'Л', 0x0E)
        mapCase('д', 'Д', 0x0F)
        mapCase('ж', 'Ж', 0x33)
        mapCase('э', 'Э', 0x34)

        mapCase('я', 'Я', 0x1D)
        mapCase('ч', 'Ч', 0x1B)
        mapCase('с', 'С', 0x06)
        mapCase('м', 'М', 0x19)
        mapCase('и', 'И', 0x05)
        mapCase('т', 'Т', 0x11)
        mapCase('ь', 'Ь', 0x10)
        mapCase('б', 'Б', 0x36)
        mapCase('ю', 'Ю', 0x37)

        mapCase('ё', 'Ё', 0x35)
        map('№', 0x20, MOD_LSHIFT)
        map('€', 0x08, MOD_RALT)
    }
}
