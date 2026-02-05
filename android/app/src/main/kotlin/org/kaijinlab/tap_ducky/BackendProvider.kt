package org.kaijinlab.tap_ducky

import android.content.Context

object BackendProvider {
  @Volatile
  private var instance: Backend? = null

  fun get(ctx: Context): Backend {
    return instance ?: synchronized(this) {
      instance ?: Backend(ctx.applicationContext).also { instance = it }
    }
  }

  class Backend(ctx: Context) {
    val logBus = LogBus()
    val manager = GadgetManager(ctx, logBus)
  }
}
