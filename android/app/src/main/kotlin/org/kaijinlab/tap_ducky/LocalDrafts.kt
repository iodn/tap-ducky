package org.kaijinlab.tap_ducky

import android.app.Activity
import android.content.Intent
import android.content.Context
import android.os.Build
import android.provider.OpenableColumns
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.ResponseFormat
import com.google.ai.edge.litertlm.ThinkingConfig
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

internal class LocalDrafts(private val activity: Activity) {
  private val model = File(activity.noBackupFilesDir, "draft-model.litertlm")
  private val metadata = activity.getSharedPreferences("local_draft_model", Context.MODE_PRIVATE)
  private val worker = Executors.newSingleThreadExecutor()
  private var channel: MethodChannel? = null
  private var pendingPicker: MethodChannel.Result? = null
  private var working = false
  private val supported = android.os.Process.is64Bit() &&
    Build.SUPPORTED_ABIS.any { it == "arm64-v8a" || it == "x86_64" }

  fun register(messenger: BinaryMessenger) {
    channel = MethodChannel(messenger, "org.kaijinlab.tap_ducky/local_drafts").apply {
      setMethodCallHandler { call, result ->
        when {
          call.method == "status" -> {
            val ready = supported && model.isFile
            result.success(mapOf(
              "state" to if (!supported) "unsupported" else if (ready) "ready" else "missing",
              "name" to if (ready) metadata.getString("name", null) else null,
              "sizeBytes" to if (ready) model.length() else null,
            ))
          }
          !supported -> result.error("UNSUPPORTED", "This device cannot run the local model.", null)
          working || pendingPicker != null -> result.error("BUSY", "Wait for the current model operation.", null)
          call.method == "pickModel" -> {
            pendingPicker = result
            try {
              activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
              }, PICK_MODEL)
            } catch (_: android.content.ActivityNotFoundException) {
              pendingPicker = null
              result.error("PICKER", "The file picker is unavailable.", null)
            }
          }
          call.method == "removeModel" -> background(result, "Could not remove the model.") {
            check(!model.exists() || model.delete())
            metadata.edit().remove("name").apply()
            null
          }
          call.method == "generate" -> {
            val prompt = call.argument<String>("prompt")?.trim() ?: ""
            if (!model.isFile || prompt.isEmpty() || prompt.length > 500) {
              result.error("NOT_READY", "Select a model and enter a request of up to 500 characters.", null)
            } else {
              background(result, "The model could not generate a draft. Try a compatible LiteRT model.") {
                Engine(EngineConfig(modelPath = model.path, maxNumTokens = 2048)).use { engine ->
                  engine.initialize()
                  val config = ConversationConfig(
                    automaticToolCalling = false,
                    maxOutputToken = 384,
                    thinkingConfig = ThinkingConfig(enableThinking = false),
                    enableResponseFormat = true,
                  )
                  engine.createConversation(config).use {
                    it.sendMessage(
                      "$INSTRUCTION\n\nRequest: $prompt\nReturn the JSON draft now.",
                      responseFormat = ResponseFormat.json(SCHEMA),
                    ).toString()
                  }
                }
              }
            }
          }
          else -> result.notImplemented()
        }
      }
    }
  }

  fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
    if (request != PICK_MODEL) return false
    val result = pendingPicker ?: return true
    pendingPicker = null
    val uri = data?.data
    if (code != Activity.RESULT_OK || uri == null) {
      result.success(false)
      return true
    }
    background(result, "Could not import the model. Choose a .litertlm file and check free storage.") {
      val resolver = activity.contentResolver
      val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
        if (it.moveToFirst()) it.getString(0) else null
      }
      if (name?.endsWith(".gguf", ignoreCase = true) == true) {
        throw ModelFormatException("GGUF is not supported by LiteRT-LM. Choose a .litertlm model instead.")
      }
      if (name?.endsWith(".litertlm", ignoreCase = true) != true) {
        throw ModelFormatException("Choose a model file ending in .litertlm.")
      }
      val temporary = File.createTempFile("draft-model-", ".tmp", model.parentFile)
      try {
        val size = resolver.openInputStream(uri)?.use { source ->
          temporary.outputStream().use { target -> source.copyTo(target, 128 * 1024) }
        }
        check(size != null && size > 0 && temporary.renameTo(model))
        metadata.edit().putString("name", name).apply()
      } finally {
        temporary.delete()
      }
      true
    }
    return true
  }

  private fun background(result: MethodChannel.Result, error: String, work: () -> Any?) {
    working = true
    worker.execute {
      val outcome = runCatching(work)
      activity.runOnUiThread {
        working = false
        outcome.fold(result::success) {
          if (it is ModelFormatException) {
            result.error("MODEL_FORMAT", it.message, null)
          } else {
            result.error("LOCAL_MODEL", error, null)
          }
        }
      }
    }
  }

  fun close() {
    channel?.setMethodCallHandler(null)
    pendingPicker?.success(false)
    pendingPicker = null
    worker.shutdown()
  }

  private class ModelFormatException(message: String) : IllegalArgumentException(message)

  private companion object {
    const val PICK_MODEL = 7351
    const val SCHEMA = """{"type":"object","properties":{"title":{"type":"string"},
"description":{"type":"string"},"tags":{"type":"array","items":{"type":"string"}},
"text":{"type":"string"},"repeat":{"type":"integer"}},
"required":["title","description","tags","text","repeat"],"additionalProperties":false}"""
    const val INSTRUCTION = """Produce a single JSON object for a plain-text typing demo.
Keys: title (short string), description (short string), tags (array of up to 5 short strings),
text (one printable ASCII line of prose), repeat (integer 1 to 100).
Example: {"title":"Hello world","description":"Types a greeting twenty times.","tags":["demo"],"text":"hello world","repeat":20}
Do not emit script code, terminal commands, or instructions to open applications. Return {} if the request requires anything other than typing display text. Return JSON only."""
  }
}
