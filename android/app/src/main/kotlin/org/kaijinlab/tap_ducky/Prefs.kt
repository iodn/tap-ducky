package org.kaijinlab.tap_ducky

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

class Prefs(context: Context) {
  private val sp: SharedPreferences = context.getSharedPreferences(NAME, Context.MODE_PRIVATE)

  var activeProfileId: String?
    get() = sp.getString(KEY_ACTIVE_PROFILE_ID, null)
    set(value) {
      sp.edit().putString(KEY_ACTIVE_PROFILE_ID, value).apply()
    }

  var activeRoleType: String?
    get() = sp.getString(KEY_ACTIVE_ROLE_TYPE, null)
    set(value) {
      sp.edit().putString(KEY_ACTIVE_ROLE_TYPE, value).apply()
    }

  var activeGadgetDir: String?
    get() = sp.getString(KEY_ACTIVE_GADGET_DIR, null)
    set(value) {
      sp.edit().putString(KEY_ACTIVE_GADGET_DIR, value).apply()
    }

  var activeKeyboardDev: String?
    get() = sp.getString(KEY_ACTIVE_KBD_DEV, null)
    set(value) {
      sp.edit().putString(KEY_ACTIVE_KBD_DEV, value).apply()
    }

  var activeMouseDev: String?
    get() = sp.getString(KEY_ACTIVE_MOUSE_DEV, null)
    set(value) {
      sp.edit().putString(KEY_ACTIVE_MOUSE_DEV, value).apply()
    }

  var prevSysUsbConfig: String?
    get() = sp.getString(KEY_PREV_SYS_USB_CONFIG, null)
    set(value) {
      sp.edit().putString(KEY_PREV_SYS_USB_CONFIG, value).apply()
    }

  var prevSysUsbState: String?
    get() = sp.getString(KEY_PREV_SYS_USB_STATE, null)
    set(value) {
      sp.edit().putString(KEY_PREV_SYS_USB_STATE, value).apply()
    }

  var prevSysUsbConfigfs: String?
    get() = sp.getString(KEY_PREV_SYS_USB_CONFIGFS, null)
    set(value) {
      sp.edit().putString(KEY_PREV_SYS_USB_CONFIGFS, value).apply()
    }

  var prevPersistSysUsbConfig: String?
    get() = sp.getString(KEY_PREV_PERSIST_SYS_USB_CONFIG, null)
    set(value) {
      sp.edit().putString(KEY_PREV_PERSIST_SYS_USB_CONFIG, value).apply()
    }

  var prevBoundGadgets: String?
    get() = sp.getString(KEY_PREV_BOUND_GADGETS, null)
    set(value) {
      sp.edit().putString(KEY_PREV_BOUND_GADGETS, value).apply()
    }

  var typingSpeedFactor: Float
    get() = sp.getFloat(KEY_TYPING_SPEED_FACTOR, 1.0f)
    set(value) {
      sp.edit().putFloat(KEY_TYPING_SPEED_FACTOR, value).apply()
    }

  var riskyFastMode: Boolean
    get() = sp.getBoolean(KEY_RISKY_FAST_MODE, false)
    set(value) {
      sp.edit().putBoolean(KEY_RISKY_FAST_MODE, value).apply()
    }

  var lastExecutedScript: String?
    get() = sp.getString(KEY_LAST_EXECUTED_SCRIPT, null)
    set(value) {
      sp.edit().putString(KEY_LAST_EXECUTED_SCRIPT, value).apply()
    }

  fun setDialShortcutBindings(bindings: List<DialShortcutBinding>) {
    val arr = JSONArray()
    for (b in bindings) {
      val obj = JSONObject()
      obj.put("code", b.code)
      obj.put("enabled", b.enabled)
      obj.put("mode", b.mode)
      obj.put("script", b.script ?: "")
      obj.put("name", b.name ?: "")
      arr.put(obj)
    }
    sp.edit().putString(KEY_DIAL_SHORTCUT_BINDINGS, arr.toString()).apply()
  }

  fun getDialShortcutBindings(): List<DialShortcutBinding> {
    val raw = sp.getString(KEY_DIAL_SHORTCUT_BINDINGS, null) ?: return emptyList()
    return try {
      val arr = JSONArray(raw)
      val out = ArrayList<DialShortcutBinding>(arr.length())
      for (i in 0 until arr.length()) {
        val obj = arr.optJSONObject(i) ?: continue
        val code = obj.optString("code", "").trim()
        if (code.isEmpty()) continue
        val enabled = obj.optBoolean("enabled", false)
        val mode = obj.optString("mode", "last")
        val script = obj.optString("script", "").takeIf { it.isNotBlank() }
        val name = obj.optString("name", "").takeIf { it.isNotBlank() }
        out.add(DialShortcutBinding(code, enabled, mode, script, name))
      }
      out
    } catch (_: Throwable) {
      emptyList()
    }
  }

  fun setActive(profileId: String, roleType: String, gadgetDir: String, keyboardDev: String?, mouseDev: String?) {
    sp.edit()
      .putString(KEY_ACTIVE_PROFILE_ID, profileId)
      .putString(KEY_ACTIVE_ROLE_TYPE, roleType)
      .putString(KEY_ACTIVE_GADGET_DIR, gadgetDir)
      .putString(KEY_ACTIVE_KBD_DEV, keyboardDev)
      .putString(KEY_ACTIVE_MOUSE_DEV, mouseDev)
      .apply()
  }

  fun clearActive() {
    sp.edit()
      .remove(KEY_ACTIVE_PROFILE_ID)
      .remove(KEY_ACTIVE_ROLE_TYPE)
      .remove(KEY_ACTIVE_GADGET_DIR)
      .remove(KEY_ACTIVE_KBD_DEV)
      .remove(KEY_ACTIVE_MOUSE_DEV)
      .apply()
  }

  fun setUsbSnapshot(
    sysUsbConfig: String?,
    sysUsbState: String?,
    sysUsbConfigfs: String?,
    persistSysUsbConfig: String?,
    boundGadgets: String?
  ) {
    sp.edit()
      .putString(KEY_PREV_SYS_USB_CONFIG, sysUsbConfig)
      .putString(KEY_PREV_SYS_USB_STATE, sysUsbState)
      .putString(KEY_PREV_SYS_USB_CONFIGFS, sysUsbConfigfs)
      .putString(KEY_PREV_PERSIST_SYS_USB_CONFIG, persistSysUsbConfig)
      .putString(KEY_PREV_BOUND_GADGETS, boundGadgets)
      .apply()
  }

  fun clearUsbSnapshot() {
    sp.edit()
      .remove(KEY_PREV_SYS_USB_CONFIG)
      .remove(KEY_PREV_SYS_USB_STATE)
      .remove(KEY_PREV_SYS_USB_CONFIGFS)
      .remove(KEY_PREV_PERSIST_SYS_USB_CONFIG)
      .remove(KEY_PREV_BOUND_GADGETS)
      .apply()
  }

  companion object {
    private const val NAME = "gadgetfs_prefs"
    private const val KEY_ACTIVE_PROFILE_ID = "active_profile_id"
    private const val KEY_ACTIVE_ROLE_TYPE = "active_role_type"
    private const val KEY_ACTIVE_GADGET_DIR = "active_gadget_dir"
    private const val KEY_ACTIVE_KBD_DEV = "active_keyboard_dev"
    private const val KEY_ACTIVE_MOUSE_DEV = "active_mouse_dev"
    private const val KEY_PREV_SYS_USB_CONFIG = "prev_sys_usb_config"
    private const val KEY_PREV_SYS_USB_STATE = "prev_sys_usb_state"
    private const val KEY_PREV_SYS_USB_CONFIGFS = "prev_sys_usb_configfs"
    private const val KEY_PREV_PERSIST_SYS_USB_CONFIG = "prev_persist_sys_usb_config"
    private const val KEY_PREV_BOUND_GADGETS = "prev_bound_gadgets"
    private const val KEY_TYPING_SPEED_FACTOR = "typing_speed_factor"
    private const val KEY_RISKY_FAST_MODE = "risky_fast_mode"
    private const val KEY_DIAL_SHORTCUT_BINDINGS = "dial_shortcut_bindings"
    private const val KEY_LAST_EXECUTED_SCRIPT = "last_executed_script"
  }
}

data class DialShortcutBinding(
  val code: String,
  val enabled: Boolean,
  val mode: String,
  val script: String?,
  val name: String?,
)
