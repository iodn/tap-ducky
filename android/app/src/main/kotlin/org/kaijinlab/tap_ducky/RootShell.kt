package org.kaijinlab.tap_ducky

import java.io.BufferedReader
import java.io.InterruptedIOException
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.max

class RootShell(private val log: LogBus) {

    private fun isExpectedStreamClose(t: Throwable): Boolean {
        val msg = t.message?.lowercase() ?: ""
        return t is InterruptedIOException ||
            msg.contains("read interrupted by close") ||
            msg.contains("stream closed") ||
            msg.contains("socket closed")
    }

    data class ExecResult(
        val ok: Boolean,
        val exitCode: Int,
        val stdout: String,
        val stderr: String,
        val durationMs: Long,
    )

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
    @Synchronized
    fun exec(script: String, timeoutSec: Long = 10): ExecResult {
        val first = script.trim().lineSequence().firstOrNull()?.take(160) ?: "(empty)"
        log.log("root", "$ $first")

        val s = ensureSession() ?: return oneShotExec(script, timeoutSec)
        val r = s.execShC(script, timeoutSec)

        // If the session died or timed out, mark it unusable so we can recreate next time.
        if (r.exitCode == -1 || !s.isAlive()) {
            dropSession("session_not_alive_after_exec")
        }
        return r
    }

    /* ---------------- Internals ---------------- */

    private fun ensureSession(): SuSession? {
        val existing = session
        if (existing != null && existing.isAlive()) return existing

        synchronized(sessionLock) {
            val cur = session
            if (cur != null && cur.isAlive()) return cur

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
                try {
                    BufferedReader(InputStreamReader(p.inputStream)).use { br ->
                        while (true) {
                            val line = br.readLine() ?: break
                            outSb.append(line).append('\n')
                        }
                    }
                } catch (t: Throwable) {
                    if (!isExpectedStreamClose(t)) throw t
                }
            }
            val tErr = Thread {
                try {
                    BufferedReader(InputStreamReader(p.errorStream)).use { br ->
                        while (true) {
                            val line = br.readLine() ?: break
                            errSb.append(line).append('\n')
                        }
                    }
                } catch (t: Throwable) {
                    if (!isExpectedStreamClose(t)) throw t
                }
            }

            tOut.start()
            tErr.start()

            val waiter = Thread {
                try {
                    p.waitFor()
                } catch (_: Throwable) {
                }
            }
            waiter.start()
            waiter.join(timeoutSec * 1000L)
            val finished = !waiter.isAlive
            if (!finished) {
                forceDestroyProcess(p)
            }

            tOut.join(250)
            tErr.join(250)

            if (waiter.isAlive) {
                waiter.join(250L)
            }
            val exit = if (finished) {
                try {
                    p.exitValue()
                } catch (_: Throwable) {
                    -1
                }
            } else {
                -1
            }
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

    private fun isProcessTerminated(process: Process): Boolean {
        return try {
            process.exitValue()
            true
        } catch (_: IllegalThreadStateException) {
            false
        } catch (_: Throwable) {
            true
        }
    }

    private fun forceDestroyProcess(process: Process) {
        try {
            process.destroy()
        } catch (_: Throwable) {
        }
        try {
            val destroyForcibly = Process::class.java.methods.firstOrNull { it.name == "destroyForcibly" }
            destroyForcibly?.invoke(process)
        } catch (_: Throwable) {
        }
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
                } catch (t: Throwable) {
                    if (!isExpectedStreamClose(t)) {
                        log.logError("root", "stdout reader failed: ${t.message ?: t.javaClass.simpleName}")
                    }
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
                } catch (t: Throwable) {
                    if (!isExpectedStreamClose(t)) {
                        log.logError("root", "stderr reader failed: ${t.message ?: t.javaClass.simpleName}")
                    }
                }
            }.apply { isDaemon = true; name = "su-stderr" }.start()
        }

        fun isAlive(): Boolean = !isProcessTerminated(p)

        fun close() {
            try { stdin.close() } catch (_: Throwable) {}
            forceDestroyProcess(p)
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
                append("printf '%s%s\\n' ").append(shQuote(rcPrefix)).append(" \"\$RC\"\n")
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
