package org.kaijinlab.tap_ducky

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AppUpdatesTest {
  @Test
  fun comparesNumericVersionsAndAndroidBuildNumbers() {
    val current = UpdateVersion.parse("1.0.9+10")!!
    assertTrue(UpdateVersion.parse("v1.0.10+11")!!.isNewerThan(current))
    assertTrue(UpdateVersion.parse("1.0.9+11")!!.isNewerThan(current))
    assertTrue(UpdateVersion.parse("v1.1.0")!!.isNewerThan(current))
    for (version in listOf("v1.0.9", "1.0.9+10", "1.0.10+9", "0.9.9+11")) {
      assertFalse(UpdateVersion.parse(version)!!.isNewerThan(current))
    }
    assertNull(UpdateVersion.parse("1.0.10-rc.1"))
  }

  @Test
  fun selectsTheFirstCompatibleVerifiedAssetAndReadsTheReleaseTitleBuild() {
    val release = GitHubUpdates.readRelease(metadata(asset("armeabi-v7a"), asset("arm64-v8a")), listOf("arm64-v8a", "armeabi-v7a"))!!
    assertEquals("1.0.9+10", release.version.toString())
    assertEquals("tapducky-arm64-v8a-release.apk", release.asset?.url?.path?.substringAfterLast('/'))
    assertEquals("a".repeat(64), release.asset?.sha256)
  }

  @Test
  fun refusesUnverifiedAndUnofficialApksAndPrereleases() {
    val elsewhere = asset("arm64-v8a").put("browser_download_url", "https://example.org/app.apk")
    val noDigest = asset("arm64-v8a").put("digest", "")
    val unknownAbi = asset("x86_64")
    assertNull(GitHubUpdates.readRelease(metadata(elsewhere, noDigest, unknownAbi), listOf("arm64-v8a"))?.asset)
    assertNull(GitHubUpdates.readRelease(metadata().put("prerelease", true), listOf("arm64-v8a")))
  }

  private fun metadata(vararg assets: JSONObject) = JSONObject()
    .put("tag_name", "v1.0.9")
    .put("name", "1.0.9+10")
    .put("assets", JSONArray(assets.toList()))

  private fun asset(abi: String): JSONObject {
    val name = "tapducky-$abi-release.apk"
    return JSONObject().put("name", name)
      .put("state", "uploaded")
      .put("size", 20_000_000)
      .put("digest", "sha256:${"a".repeat(64)}")
      .put("browser_download_url", "${GitHubUpdates.RELEASES}/download/v1.0.9/$name")
  }
}
