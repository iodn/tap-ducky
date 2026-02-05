package org.kaijinlab.tap_ducky

import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.max

class RootShell(private val log: LogBus) {

    data class ExecResult(
        val ok: Boolean,
        val exitCode: Int,
        val stdout: String,
        val stderr: String,
        val durationMs: Long,
    )

    // Writer FD numbers inside the persistent root shell:
    // - FD 3: keyboard (/dev/hidg0)
    // - FD 4: mouse    (/dev/hidg1)
    private val HID_FD_KBD = 3
    private val HID_FD_MOUSE = 4

    @Volatile private var kbdWriterReady: Boolean = false
    @Volatile private var mouseWriterReady: Boolean = false

    private val tokenCounter = AtomicInteger(1)

    @Volatile private var session: SuSession? = null
    private val sessionLock = Any()

    fun hasRoot(): Boolean {
        val r = exec("id", timeoutSec = 5)
        return r.ok && (r.stdout.contains("uid=0") || r.stderr.contains("uid=0"))
    }

    /**
     * Execute a script via the persistent su session when possible.
     * Fallbacks to one-shot `su -c` if interactive su cannot be kept alive on the device.
     *
     * NOTE: This executes the provided script via `sh -c '<script>'` inside the session,
     * so it does NOT permanently mutate the session shell environment.
     */
    fun exec(script: String, timeoutSec: Long = 10): ExecResult {
        val first = script.trim().lineSequence().firstOrNull()?.take(160) ?: "(empty)"
        log.log("root", "$ $first")

        val s = ensureSession() ?: return oneShotExec(script, timeoutSec)
        val r = s.execShC(script, timeoutSec)

        // If the session died or timed out, mark it unusable so we can recreate next time.
        if (!s.isAlive()) {
            dropSession("session_not_alive_after_exec")
        }
        return r
    }

    /**
     * Execute commands *directly in the persistent session shell* (no `sh -c`).
     * Use this ONLY when you need side-effects to persist in the session (e.g. `exec 3> /dev/hidg0`).
     */
    fun execDirect(commands: String, timeoutSec: Long = 10): ExecResult {
        val first = commands.trim().lineSequence().firstOrNull()?.take(160) ?: "(empty)"
        log.log("root", "$ $first")

        val s = ensureSession() ?: return oneShotExec(commands, timeoutSec) // best-effort fallback
        val r = s.execDirect(commands, timeoutSec)

        if (!s.isAlive()) {
            dropSession("session_not_alive_after_execDirect")
        }
        return r
    }

    /**
     * Send a raw single line command into the persistent session (no completion markers, no waiting).
     * Intended for extremely fast HID writes like: `printf '%b' '\x00\x08\x00\x00' >&4`
     *
     * If the session is not available, this throws.
     */
    fun sendRaw(line: String, logIt: Boolean = false) {
        val s = ensureSession() ?: throw IllegalStateException("Root session not available")
        if (logIt) {
            val p = line.trim().take(160)
            log.log("root/raw", p)
        }
        s.sendRaw(line)
        if (!s.isAlive()) {
            dropSession("session_not_alive_after_sendRaw")
            throw IllegalStateException("Root session died")
        }
    }

    fun isKeyboardWriterReady(): Boolean = kbdWriterReady
    fun isMouseWriterReady(): Boolean = mouseWriterReady

    /**
     * Open persistent writer FDs inside the long-lived root shell:
     * - FD 3 -> keyboardPath (if non-null)
     * - FD 4 -> mousePath    (if non-null)
     *
     * This is the key optimization: subsequent writes can be done via sendRaw(...) without re-opening.
     */
    fun openHidWriters(keyboardPath: String?, mousePath: String?, timeoutSec: Long = 6): ExecResult {
        val k = keyboardPath ?: ""
        val m = mousePath ?: ""

        // IMPORTANT: must be executed in-session (execDirect) so FDs persist.
        val script = """
            K=${shQuote(k)}
            M=${shQuote(m)}

            # Close any previous writer fds best-effort.
            (exec $HID_FD_KBD>&-) 2>/dev/null || true
            (exec $HID_FD_MOUSE>&-) 2>/dev/null || true

            # Wait briefly for device nodes to appear after binding (best-effort).
            if [ -n "$${'$'}K" ]; then
              i=0
              while [ $${'$'}i -lt 60 ] && [ ! -e "$${'$'}K" ]; do
                sleep 0.05
                i=$${'$'}((i+1))
              done
              exec $HID_FD_KBD> "$${'$'}K"
            fi

            if [ -n "$${'$'}M" ]; then
              i=0
              while [ $${'$'}i -lt 60 ] && [ ! -e "$${'$'}M" ]; do
                sleep 0.05
                i=$${'$'}((i+1))
              done
              exec $HID_FD_MOUSE> "$${'$'}M"
            fi

            FD3_OK=0
            FD4_OK=0
            [ -e /proc/$$/fd/$HID_FD_KBD ] && FD3_OK=1 || true
            [ -e /proc/$$/fd/$HID_FD_MOUSE ] && FD4_OK=1 || true
            echo "FD3_OK=$${'$'}FD3_OK"
            echo "FD4_OK=$${'$'}FD4_OK"

            # Succeed if requested writers are opened.
            ok=1
            if [ -n "$${'$'}K" ] && [ "$${'$'}FD3_OK" != "1" ]; then ok=0; fi
            if [ -n "$${'$'}M" ] && [ "$${'$'}FD4_OK" != "1" ]; then ok=0; fi
            [ $${'$'}ok -eq 1 ]
        """.trimIndent()

        val r = execDirect(script, timeoutSec)
        val fd3 = r.stdout.lineSequence().any { it.trim() == "FD3_OK=1" }
        val fd4 = r.stdout.lineSequence().any { it.trim() == "FD4_OK=1" }

        // Update readiness flags. If path wasn't requested, treat as not-ready.
        kbdWriterReady = keyboardPath != null && fd3 && r.ok
        mouseWriterReady = mousePath != null && fd4 && r.ok

        return r
    }

    /**
     * Close persistent HID writer FDs inside the persistent session shell.
     */
    fun closeHidWriters(timeoutSec: Long = 4): ExecResult {
        kbdWriterReady = false
        mouseWriterReady = false

        val script = """
            (exec $HID_FD_KBD>&-) 2>/dev/null || true
            (exec $HID_FD_MOUSE>&-) 2>/dev/null || true
            echo "FD3_CLOSED=1"
            echo "FD4_CLOSED=1"
            true
        """.trimIndent()
        return execDirect(script, timeoutSec)
    }

    /**
     * Fast-path write into an already-open writer FD (3 or 4).
     * No waiting, no markers. Best performance.
     */
    fun writeToFdFast(fd: Int, bytes: ByteArray) {
        val hexEsc = toHexEsc(bytes)
        // hexEsc contains only \xNN sequences, safe for single quotes.
        sendRaw("printf '%b' '$hexEsc' >&$fd", logIt = false)
    }

    fun writeKeyboardFast(bytes: ByteArray) {
        if (!kbdWriterReady) throw IllegalStateException("Keyboard writer not ready")
        writeToFdFast(HID_FD_KBD, bytes)
    }

    fun writeMouseFast(bytes: ByteArray) {
        if (!mouseWriterReady) throw IllegalStateException("Mouse writer not ready")
        writeToFdFast(HID_FD_MOUSE, bytes)
    }

    /* ---------------- Internals ---------------- */

    private fun ensureSession(): SuSession? {
        val existing = session
        if (existing != null && existing.isAlive()) return existing

        synchronized(sessionLock) {
            val cur = session
            if (cur != null && cur.isAlive()) return cur

            // If we had a previous session, drop it and reset writer readiness.
            kbdWriterReady = false
            mouseWriterReady = false

            return try {
                val s = SuSession(log)
                // Quick sanity check: ensure we can run a trivial command.
                val r = s.execShC("id", timeoutSec = 5)
                if (!r.ok) {
                    s.close()
                    session = null
                    null
                } else {
                    session = s
                    s
                }
            } catch (t: Throwable) {
                log.logError("root", "Failed to start persistent su session: ${t.message}")
                session = null
                null
            }
        }
    }

    private fun dropSession(reason: String) {
        synchronized(sessionLock) {
            try {
                session?.close()
            } catch (_: Throwable) {
            }
            session = null
            kbdWriterReady = false
            mouseWriterReady = false
            log.logError("root", "Dropped persistent su session ($reason)")
        }
    }

    /**
     * Fallback path: legacy one-shot exec via `su -c ...`.
     * This is slower and does NOT support persistent FDs.
     */
    private fun oneShotExec(script: String, timeoutSec: Long): ExecResult {
        val start = System.currentTimeMillis()
        val cmd = listOf("su", "-c", "sh -c ${shellQuote(script)}")

        return try {
            val pb = ProcessBuilder(cmd)
            pb.redirectErrorStream(false)
            val p = pb.start()

            val outSb = StringBuilder()
            val errSb = StringBuilder()

            val tOut = Thread {
                BufferedReader(InputStreamReader(p.inputStream)).use { br ->
                    while (true) {
                        val line = br.readLine() ?: break
                        outSb.append(line).append('\n')
                    }
                }
            }
            val tErr = Thread {
                BufferedReader(InputStreamReader(p.errorStream)).use { br ->
                    while (true) {
                        val line = br.readLine() ?: break
                        errSb.append(line).append('\n')
                    }
                }
            }

            tOut.start()
            tErr.start()

            val finished = p.waitFor(timeoutSec, java.util.concurrent.TimeUnit.SECONDS)
            if (!finished) {
                p.destroy()
                p.destroyForcibly()
            }

            tOut.join(250)
            tErr.join(250)

            val exit = if (finished) p.exitValue() else -1
            val dur = System.currentTimeMillis() - start
            val out = outSb.toString()
            val err = if (!finished) "timeout after ${timeoutSec}s\n${errSb}" else errSb.toString()
            val ok = finished && exit == 0 && !err.contains("Permission denied", ignoreCase = true)

            if (out.isNotBlank()) log.log("root/out", out.trimEnd())
            if (err.isNotBlank()) log.log("root/err", err.trimEnd())

            ExecResult(ok, exit, out, err, dur)
        } catch (t: Throwable) {
            val dur = System.currentTimeMillis() - start
            log.logError("root", "oneShot exec failed: ${t.message}")
            ExecResult(false, -1, "", t.message ?: "", dur)
        }
    }

    private fun shQuote(s: String): String = "'" + s.replace("'", "'\"'\"'") + "'"

    private fun shellQuote(s: String): String {
        // Safe for embedding in: sh -c '<script>'
        return "'" + s.replace("'", "'\\''") + "'"
    }

    private fun toHexEsc(bytes: ByteArray): String {
        val sb = StringBuilder(bytes.size * 4)
        for (b in bytes) {
            val v = b.toInt() and 0xFF
            sb.append(String.format(java.util.Locale.US, "\\x%02x", v))
        }
        return sb.toString()
    }

    /* ---------------- Persistent su session ---------------- */

    private class LineBuffer(private val maxLines: Int) {
        private val lock = Object()
        private val q = ArrayDeque<String>(max(16, maxLines))

        fun add(line: String) {
            synchronized(lock) {
                if (q.size >= maxLines) {
                    q.removeFirst()
                }
                q.addLast(line)
                lock.notifyAll()
            }
        }

        fun nextLine(timeoutMs: Long): String? {
            val deadline = System.currentTimeMillis() + timeoutMs
            synchronized(lock) {
                while (q.isEmpty()) {
                    val now = System.currentTimeMillis()
                    val remain = deadline - now
                    if (remain <= 0) return null
                    lock.wait(remain)
                }
                return q.removeFirst()
            }
        }

        fun clear() {
            synchronized(lock) {
                q.clear()
            }
        }
    }

    private inner class SuSession(private val log: LogBus) {
        private val p: Process
        private val stdin: OutputStreamWriter
        private val stdoutBuf = LineBuffer(4000)
        private val stderrBuf = LineBuffer(4000)

        init {
            val pb = ProcessBuilder(listOf("su"))
            pb.redirectErrorStream(false)
            p = pb.start()
            stdin = OutputStreamWriter(p.outputStream)

            // Reader threads continuously drain streams so the process never blocks.
            Thread {
                try {
                    BufferedReader(InputStreamReader(p.inputStream)).use { br ->
                        while (true) {
                            val line = br.readLine() ?: break
                            stdoutBuf.add(line)
                        }
                    }
                } catch (_: Throwable) {
                }
            }.apply { isDaemon = true; name = "su-stdout" }.start()

            Thread {
                try {
                    BufferedReader(InputStreamReader(p.errorStream)).use { br ->
                        while (true) {
                            val line = br.readLine() ?: break
                            stderrBuf.add(line)
                        }
                    }
                } catch (_: Throwable) {
                }
            }.apply { isDaemon = true; name = "su-stderr" }.start()
        }

        fun isAlive(): Boolean = try { p.isAlive } catch (_: Throwable) { false }

        fun close() {
            try { stdin.close() } catch (_: Throwable) {}
            try { p.destroy() } catch (_: Throwable) {}
            try { p.destroyForcibly() } catch (_: Throwable) {}
        }

        fun sendRaw(line: String) {
            // Send as a single line command.
            stdin.write(line)
            if (!line.endsWith("\n")) stdin.write("\n")
            stdin.flush()
        }

        fun execShC(script: String, timeoutSec: Long): ExecResult {
            val body = "sh -c ${shellQuote(script)}"
            return execWrapped(body, timeoutSec)
        }

        fun execDirect(commands: String, timeoutSec: Long): ExecResult {
            // Run in the session shell directly. This can persist FD changes (exec 3>...).
            // We wrap it in `{ ...; }` so it is a single compound command.
            val body = "{\n$commands\n}\n"
            return execWrapped(body, timeoutSec)
        }

        private fun execWrapped(body: String, timeoutSec: Long): ExecResult {
            val start = System.currentTimeMillis()
            val token = "GFS_${tokenCounter.getAndIncrement()}_${System.nanoTime()}"
            val begin = "__GFS_BEGIN__:$token"
            val end = "__GFS_END__:$token"
            val rcPrefix = "__GFS_RC__:$token:"

            // Markers on BOTH stdout and stderr.
            val wrapper = buildString {
                append("echo ").append(shQuote(begin)).append("\n")
                append("echo ").append(shQuote(begin)).append(" 1>&2\n")
                append(body).append("\n")
                append("RC=$?\n")
                append("echo ").append(shQuote("${rcPrefix}\$RC")).append("\n")
                append("echo ").append(shQuote(end)).append("\n")
                append("echo ").append(shQuote(end)).append(" 1>&2\n")
            }

            // Send wrapper
            sendRaw(wrapper)

            // Parse stdout
            val stdoutLines = StringBuilder()
            val stderrLines = StringBuilder()
            var exitCode: Int? = null

            val deadlineMs = start + timeoutSec * 1000
            fun remainingMs(): Long = max(0, deadlineMs - System.currentTimeMillis())

            // Wait for stdout begin
            while (true) {
                val line = stdoutBuf.nextLine(remainingMs())
                    ?: return timeoutResult(start, timeoutSec, stdoutLines.toString(), stderrLines.toString())
                if (line == begin) break
                // Discard noise (e.g., errors from raw writes) before begin.
            }

            // Capture stdout until end
            while (true) {
                val line = stdoutBuf.nextLine(remainingMs())
                    ?: return timeoutResult(start, timeoutSec, stdoutLines.toString(), stderrLines.toString())
                if (line == end) break
                if (line.startsWith(rcPrefix)) {
                    val n = line.removePrefix(rcPrefix).trim()
                    exitCode = n.toIntOrNull() ?: -1
                } else {
                    stdoutLines.append(line).append('\n')
                }
            }

            // Wait for stderr begin (best-effort), then capture until stderr end.
            // If it does not show up quickly, just drain nothing.
            var sawErrBegin = false
            val errBeginDeadline = System.currentTimeMillis() + 250L
            while (System.currentTimeMillis() < errBeginDeadline) {
                val line = stderrBuf.nextLine(50) ?: break
                if (line == begin) {
                    sawErrBegin = true
                    break
                }
                // Discard noise before begin.
            }
            if (sawErrBegin) {
                while (true) {
                    val line = stderrBuf.nextLine(remainingMs()) ?: break
                    if (line == end) break
                    // We keep rc marker only in stdout; stderr can include it, but ignore.
                    stderrLines.append(line).append('\n')
                }
            }

            val dur = System.currentTimeMillis() - start
            val exit = exitCode ?: -1
            val out = stdoutLines.toString()
            val err = stderrLines.toString()
            val ok = (exit == 0) && !err.contains("Permission denied", ignoreCase = true)

            if (out.isNotBlank()) log.log("root/out", out.trimEnd())
            if (err.isNotBlank()) log.log("root/err", err.trimEnd())

            return ExecResult(ok, exit, out, err, dur)
        }

        private fun timeoutResult(
            start: Long,
            timeoutSec: Long,
            stdoutSoFar: String,
            stderrSoFar: String
        ): ExecResult {
            val dur = System.currentTimeMillis() - start
            log.logError("root", "timeout (${timeoutSec}s) in persistent session")
            return ExecResult(
                ok = false,
                exitCode = -1,
                stdout = stdoutSoFar,
                stderr = "timeout after ${timeoutSec}s\n$stderrSoFar",
                durationMs = dur
            )
        }
    }
}
