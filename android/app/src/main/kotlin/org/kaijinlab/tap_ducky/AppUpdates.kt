package org.kaijinlab.tap_ducky

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.core.app.NotificationCompat
import androidx.core.content.pm.PackageInfoCompat
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

internal data class UpdateVersion(val major: Int, val minor: Int, val patch: Int, val build: Long?) {
  fun isNewerThan(installed: UpdateVersion): Boolean {
    val order = compareValuesBy(this, installed, { it.major }, { it.minor }, { it.patch })
    if (order < 0 || (build != null && installed.build != null && build <= installed.build)) return false
    return order > 0 || (build != null && installed.build != null && build > installed.build)
  }

  override fun toString() = "$major.$minor.$patch" + (build?.let { "+$it" } ?: "")

  companion object {
    private val pattern = Regex("v?(\\d+)\\.(\\d+)\\.(\\d+)(?:\\+(\\d+))?")

    fun parse(input: String): UpdateVersion? {
      val match = pattern.matchEntire(input.trim()) ?: return null
      val (major, minor, patch, build) = match.destructured
      return UpdateVersion(
        major.toIntOrNull() ?: return null,
        minor.toIntOrNull() ?: return null,
        patch.toIntOrNull() ?: return null,
        if (build.isEmpty()) null else build.toLongOrNull() ?: return null,
      )
    }
  }
}

internal data class UpdateAsset(val url: URI, val size: Long, val sha256: String)
internal data class UpdateRelease(val version: UpdateVersion, val asset: UpdateAsset?)

internal object GitHubUpdates {
  const val RELEASES = "https://github.com/iodn/tap-ducky/releases"
  private val latest = URI("https://api.github.com/repos/iodn/tap-ducky/releases/latest")
  private val assetHosts = setOf("github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com")
  private val supportedAbis = setOf("arm64-v8a", "armeabi-v7a", "x86_64")
  private val digest = Regex("sha256:([a-fA-F0-9]{64})")

  fun readRelease(json: JSONObject, abis: List<String>): UpdateRelease? {
    if (json.optBoolean("draft") || json.optBoolean("prerelease")) return null
    val tag = json.optString("tag_name")
    val taggedVersion = UpdateVersion.parse(tag) ?: throw IOException("Unrecognized release version.")
    val titleVersion = UpdateVersion.parse(json.optString("name"))
    val version = if (taggedVersion.build == null && titleVersion != null && titleVersion.copy(build = null) == taggedVersion) {
      titleVersion
    } else {
      taggedVersion
    }
    val assets = json.optJSONArray("assets")
    if (assets != null) {
      for (abi in abis.filter { it in supportedAbis }) {
        val name = "tapducky-$abi-release.apk"
        val url = "$RELEASES/download/$tag/$name"
        for (index in 0 until assets.length()) {
          val item = assets.optJSONObject(index) ?: continue
          if (item.optString("name") != name || item.optString("state") != "uploaded" ||
            item.optString("browser_download_url") != url
          ) continue
          val hash = digest.matchEntire(item.optString("digest"))?.groupValues?.get(1) ?: continue
          val size = item.optLong("size")
          if (size in 1..500_000_000) return UpdateRelease(version, UpdateAsset(URI(url), size, hash.lowercase()))
        }
      }
    }
    return UpdateRelease(version, null)
  }

  fun latestRelease(): UpdateRelease? = request(latest, setOf("api.github.com")) { response ->
    if (response.responseCode == 404) return@request null
    if (response.responseCode != 200) throw IOException("GitHub returned HTTP ${response.responseCode}.")
    val body = ByteArrayOutputStream()
    response.inputStream.use { input ->
      val buffer = ByteArray(8192)
      while (true) {
        val count = input.read(buffer)
        if (count < 0) break
        if (body.size() + count > 2_000_000) throw IOException("GitHub release response is too large.")
        body.write(buffer, 0, count)
      }
    }
    readRelease(JSONObject(body.toString("UTF-8")), Build.SUPPORTED_ABIS.toList())
  }

  fun download(asset: UpdateAsset, destination: File) {
    val hash = MessageDigest.getInstance("SHA-256")
    var received = 0L
    request(asset.url, assetHosts) { response ->
      if (response.responseCode != 200) throw IOException("APK download returned HTTP ${response.responseCode}.")
      response.inputStream.use { input ->
        destination.outputStream().use { output ->
          val buffer = ByteArray(64 * 1024)
          while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            received += count
            if (received > asset.size) throw IOException("The APK is larger than expected.")
            hash.update(buffer, 0, count)
            output.write(buffer, 0, count)
          }
        }
      }
    }
    if (received != asset.size || hash.digest().joinToString("") { "%02x".format(it) } != asset.sha256) {
      throw IOException("The APK did not match GitHub's checksum.")
    }
  }

  private fun <T> request(start: URI, hosts: Set<String>, read: (HttpURLConnection) -> T): T {
    var uri = start
    repeat(5) {
      if (uri.scheme != "https" || uri.host !in hosts || uri.userInfo != null || uri.port !in listOf(-1, 443)) {
        throw IOException("The update redirected outside GitHub.")
      }
      val connection = uri.toURL().openConnection() as HttpURLConnection
      try {
        connection.instanceFollowRedirects = false
        connection.connectTimeout = 15_000
        connection.readTimeout = 25_000
        connection.setRequestProperty("User-Agent", "TapDucky-Updates")
        if (uri.host == "api.github.com") connection.setRequestProperty("Accept", "application/vnd.github+json")
        if (connection.responseCode !in listOf(301, 302, 303, 307, 308)) return read(connection)
        val location = connection.getHeaderField("Location") ?: throw IOException("GitHub redirect has no destination.")
        uri = uri.resolve(location)
      } finally {
        connection.disconnect()
      }
    }
    throw IOException("GitHub returned too many redirects.")
  }
}

class UpdateFileProvider : FileProvider()

internal class AppUpdates(private val context: Context) {
  private val preferences = context.getSharedPreferences("app_updates", Context.MODE_PRIVATE)
  private val notifications = context.getSystemService(NotificationManager::class.java)
  val enabled: Boolean get() = preferences.getBoolean("enabled", false)

  fun settings(): Map<String, Any> = mapOf(
    "enabled" to enabled,
    "notificationsAllowed" to notificationsAllowed(),
    "installed" to installed.let { "${it.versionName}+${PackageInfoCompat.getLongVersionCode(it)}" },
  )

  private fun notificationsAllowed(): Boolean = notifications.areNotificationsEnabled() &&
    (Build.VERSION.SDK_INT < 26 || notifications.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)

  fun schedule() {
    if (!enabled) return
    val work = PeriodicWorkRequestBuilder<UpdateWorker>(24, TimeUnit.HOURS)
      .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
      .build()
    WorkManager.getInstance(context).enqueueUniquePeriodicWork(CHANNEL, ExistingPeriodicWorkPolicy.KEEP, work)
  }

  fun setEnabled(value: Boolean) {
    preferences.edit().putBoolean("enabled", value).apply()
    if (value) {
      schedule()
    } else {
      WorkManager.getInstance(context).cancelUniqueWork(CHANNEL)
      notifications.cancel(NOTIFICATION_ID)
      preferences.edit().remove("notified").apply()
    }
  }

  @Suppress("DEPRECATION")
  private val installed get() = context.packageManager.getPackageInfo(context.packageName, 0)

  fun check(): UpdateRelease? {
    val info = installed
    val current = UpdateVersion.parse(info.versionName.orEmpty())?.copy(build = PackageInfoCompat.getLongVersionCode(info))
      ?: throw IOException("Cannot read the installed app version.")
    return GitHubUpdates.latestRelease()?.takeIf { it.version.isNewerThan(current) }
  }

  fun notify(release: UpdateRelease?) {
    if (release == null) {
      notifications.cancel(NOTIFICATION_ID)
      return
    }
    if (!enabled || !notificationsAllowed()) return
    if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
      PackageManager.PERMISSION_GRANTED
    ) return
    val version = release.version.toString()
    if (preferences.getString("notified", null) == version) return
    if (Build.VERSION.SDK_INT >= 26) {
      notifications.createNotificationChannel(NotificationChannel(CHANNEL, "App updates", NotificationManager.IMPORTANCE_DEFAULT))
    }
    val launch = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
      .putExtra(OPEN_UPDATES, true)
    val pending = PendingIntent.getActivity(context, NOTIFICATION_ID, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    notifications.notify(NOTIFICATION_ID, NotificationCompat.Builder(context, CHANNEL)
      .setSmallIcon(android.R.drawable.stat_sys_download_done)
      .setContentTitle("TapDucky update available")
      .setContentText("Version $version")
      .setContentIntent(pending)
      .setAutoCancel(true)
      .build())
    preferences.edit().putString("notified", version).apply()
  }

  @Suppress("DEPRECATION")
  fun prepareUpdate(expectedVersion: String): File {
    val release = check()?.takeIf { it.version.toString() == expectedVersion }
      ?: throw IOException("The release changed. Check for updates again.")
    val asset = release.asset ?: throw IOException("No verified APK is available for this device.")
    val directory = File(context.cacheDir, "app-updates")
    directory.mkdirs()
    val cutoff = System.currentTimeMillis() - TimeUnit.DAYS.toMillis(1)
    directory.listFiles()?.filter { it.lastModified() < cutoff }?.forEach { it.delete() }
    val file = File.createTempFile("update-", ".apk", directory)
    try {
      GitHubUpdates.download(asset, file)
      val signatureFlags = if (Build.VERSION.SDK_INT >= 28) {
        PackageManager.GET_SIGNING_CERTIFICATES
      } else {
        PackageManager.GET_SIGNATURES
      }
      val archive = context.packageManager.getPackageArchiveInfo(file.path, signatureFlags)
        ?: throw IOException("The download is not a valid APK.")
      val build = PackageInfoCompat.getLongVersionCode(archive)
      if (archive.packageName != context.packageName || build <= PackageInfoCompat.getLongVersionCode(installed) ||
        UpdateVersion.parse(archive.versionName.orEmpty())?.copy(build = null) != release.version.copy(build = null) ||
        (release.version.build != null && build != release.version.build)
      ) throw IOException("The APK does not match this app and release version.")
      val current = context.packageManager.getPackageInfo(context.packageName, signatureFlags)
      val currentSigners = if (Build.VERSION.SDK_INT >= 28) current.signingInfo?.apkContentsSigners else current.signatures
      val archiveSigners = if (Build.VERSION.SDK_INT >= 28) archive.signingInfo?.apkContentsSigners else archive.signatures
      if (currentSigners.isNullOrEmpty() || currentSigners.toSet() != archiveSigners?.toSet()) {
        throw IOException("This APK has a different signing key. Update TapDucky from the source you installed it from.")
      }
      return file
    } catch (failure: Exception) {
      file.delete()
      throw failure
    }
  }

  @Suppress("DEPRECATION")
  fun launchInstaller(activity: Activity, apk: File) {
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", apk)
    val intent = Intent(Intent.ACTION_INSTALL_PACKAGE, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    val installer = context.packageManager.queryIntentActivities(intent, PackageManager.MATCH_SYSTEM_ONLY).firstOrNull()
      ?: throw IOException("Android's package installer is unavailable.")
    intent.setClassName(installer.activityInfo.packageName, installer.activityInfo.name)
    activity.startActivity(intent)
  }

  fun openNotificationSettings(activity: Activity) {
    val intent = if (Build.VERSION.SDK_INT >= 26) {
      Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
    } else {
      Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
    }
    activity.startActivity(intent)
  }

  companion object {
    const val OPEN_UPDATES = "org.kaijinlab.tap_ducky.OPEN_UPDATES"
    private const val CHANNEL = "app_updates"
    private const val NOTIFICATION_ID = 4702
  }
}

class UpdateWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
  override fun doWork(): Result {
    val updates = AppUpdates(applicationContext)
    if (!updates.enabled) return Result.success()
    return try {
      updates.notify(updates.check())
      Result.success()
    } catch (_: Exception) {
      if (runAttemptCount < 2) Result.retry() else Result.success()
    }
  }
}
