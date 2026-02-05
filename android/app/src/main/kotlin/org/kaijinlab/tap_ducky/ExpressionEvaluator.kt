package org.kaijinlab.tap_ducky

import kotlin.math.abs

class ExpressionEvaluator {
  private enum class Kind { NUM, VAR, IDENT, OP, LPAREN, RPAREN, END }
  private data class Tok(val kind: Kind, val text: String)

  fun evaluate(expression: String, variables: Map<String, Int>): Int {
    val tokens = tokenize(expression)
    val p = Parser(tokens, variables)
    return p.parse()
  }

  private fun tokenize(expr: String): List<Tok> {
    val out = ArrayList<Tok>()
    var i = 0
    while (i < expr.length) {
      val c = expr[i]
      if (c.isWhitespace()) {
        i++
        continue
      }

      if (c == '(') {
        out.add(Tok(Kind.LPAREN, "("))
        i++
        continue
      }

      if (c == ')') {
        out.add(Tok(Kind.RPAREN, ")"))
        i++
        continue
      }

      if (c == '$') {
        if (i + 1 < expr.length && expr[i + 1] == '?') {
          out.add(Tok(Kind.VAR, "$?"))
          i += 2
          continue
        }
        var j = i + 1
        while (j < expr.length) {
          val ch = expr[j]
          if (ch.isLetterOrDigit() || ch == '_') j++ else break
        }
        val name = expr.substring(i, j)
        out.add(Tok(Kind.VAR, name))
        i = j
        continue
      }

      if (c.isLetter() || c == '_') {
        var j = i + 1
        while (j < expr.length) {
          val ch = expr[j]
          if (ch.isLetterOrDigit() || ch == '_') j++ else break
        }
        out.add(Tok(Kind.IDENT, expr.substring(i, j)))
        i = j
        continue
      }

      if (c.isDigit()) {
        if (c == '0' && i + 1 < expr.length && (expr[i + 1] == 'x' || expr[i + 1] == 'X')) {
          var j = i + 2
          while (j < expr.length) {
            val ch = expr[j]
            if (ch.isDigit() || (ch.lowercaseChar() in 'a'..'f')) j++ else break
          }
          val raw = expr.substring(i, j)
          out.add(Tok(Kind.NUM, raw))
          i = j
          continue
        } else {
          var j = i + 1
          while (j < expr.length && expr[j].isDigit()) j++
          out.add(Tok(Kind.NUM, expr.substring(i, j)))
          i = j
          continue
        }
      }

      val two = if (i + 1 < expr.length) expr.substring(i, i + 2) else ""
      when (two) {
        "&&", "||", "==", "!=", "<=", ">=" -> {
          out.add(Tok(Kind.OP, two))
          i += 2
          continue
        }
      }

      when (c) {
        '+', '-', '*', '/', '%', '^', '<', '>', '!' -> {
          out.add(Tok(Kind.OP, c.toString()))
          i++
          continue
        }

        '=' -> {
          out.add(Tok(Kind.OP, "=="))
          i++
          continue
        }

        else -> {
          i++
          continue
        }
      }
    }

    out.add(Tok(Kind.END, ""))
    return out
  }

  private class Parser(
    private val tokens: List<Tok>,
    private val vars: Map<String, Int>
  ) {
    private var pos = 0

    fun parse(): Int = parseOr()

    private fun peek(): Tok = tokens[pos]
    private fun consume(): Tok = tokens[pos++]

    private fun matchOp(op: String): Boolean {
      val t = peek()
      if (t.kind == Kind.OP && t.text == op) {
        pos++
        return true
      }
      return false
    }

    private fun match(kind: Kind): Tok? {
      val t = peek()
      if (t.kind == kind) {
        pos++
        return t
      }
      return null
    }

    private fun toBool(v: Int): Boolean = v != 0
    private fun b(v: Boolean): Int = if (v) 1 else 0

    private fun parseOr(): Int {
      var left = parseAnd()
      while (matchOp("||")) {
        val right = parseAnd()
        left = b(toBool(left) || toBool(right))
      }
      return left
    }

    private fun parseAnd(): Int {
      var left = parseEquality()
      while (matchOp("&&")) {
        val right = parseEquality()
        left = b(toBool(left) && toBool(right))
      }
      return left
    }

    private fun parseEquality(): Int {
      var left = parseRelational()
      while (true) {
        when {
          matchOp("==") -> {
            val right = parseRelational()
            left = b(left == right)
          }

          matchOp("!=") -> {
            val right = parseRelational()
            left = b(left != right)
          }

          else -> return left
        }
      }
    }

    private fun parseRelational(): Int {
      var left = parseAddSub()
      while (true) {
        when {
          matchOp("<=") -> {
            val right = parseAddSub()
            left = b(left <= right)
          }

          matchOp(">=") -> {
            val right = parseAddSub()
            left = b(left >= right)
          }

          matchOp("<") -> {
            val right = parseAddSub()
            left = b(left < right)
          }

          matchOp(">") -> {
            val right = parseAddSub()
            left = b(left > right)
          }

          else -> return left
        }
      }
    }

    private fun parseAddSub(): Int {
      var left = parseMulDiv()
      while (true) {
        when {
          matchOp("+") -> left = satAdd(left, parseMulDiv())
          matchOp("-") -> left = satSub(left, parseMulDiv())
          else -> return left
        }
      }
    }

    private fun parseMulDiv(): Int {
      var left = parsePower()
      while (true) {
        when {
          matchOp("*") -> left = satMul(left, parsePower())
          matchOp("/") -> {
            val d = parsePower()
            left = if (d == 0) 0 else left / d
          }

          matchOp("%") -> {
            val d = parsePower()
            left = if (d == 0) 0 else left % d
          }

          else -> return left
        }
      }
    }

    private fun parsePower(): Int {
      var left = parseUnary()
      if (matchOp("^")) {
        val right = parsePower()
        left = powInt(left, right)
      }
      return left
    }

    private fun parseUnary(): Int {
      if (matchOp("!")) {
        val v = parseUnary()
        return b(!toBool(v))
      }
      if (matchOp("-")) {
        val v = parseUnary()
        return satNeg(v)
      }
      if (matchOp("+")) {
        return parseUnary()
      }
      return parsePrimary()
    }

    private fun parsePrimary(): Int {
      val n = match(Kind.NUM)
      if (n != null) {
        val t = n.text
        return if (t.startsWith("0x", ignoreCase = true)) {
          t.substring(2).toLongOrNull(16)?.toInt() ?: 0
        } else {
          t.toIntOrNull() ?: 0
        }
      }

      val v = match(Kind.VAR)
      if (v != null) {
        return vars[v.text] ?: 0
      }

      val id = match(Kind.IDENT)
      if (id != null) {
        if (id.text.equals("TRUE", ignoreCase = true)) return 1
        if (id.text.equals("FALSE", ignoreCase = true)) return 0
        return 0
      }

      if (match(Kind.LPAREN) != null) {
        val inside = parseOr()
        match(Kind.RPAREN)
        return inside
      }

      consume()
      return 0
    }

    private fun satAdd(a: Int, b: Int): Int {
      val r = a.toLong() + b.toLong()
      return r.coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()
    }

    private fun satSub(a: Int, b: Int): Int {
      val r = a.toLong() - b.toLong()
      return r.coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()
    }

    private fun satMul(a: Int, b: Int): Int {
      val r = a.toLong() * b.toLong()
      return r.coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()
    }

    private fun satNeg(a: Int): Int {
      if (a == Int.MIN_VALUE) return Int.MAX_VALUE
      return -a
    }

    private fun powInt(base: Int, exp: Int): Int {
      if (exp == 0) return 1
      if (exp < 0) return 0
      var e = exp
      var b = base.toLong()
      var r = 1L
      while (e > 0) {
        if ((e and 1) == 1) {
          r = (r * b).coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong())
        }
        e = e ushr 1
        if (e > 0) {
          b = (b * b).coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong())
        }
      }
      return r.toInt()
    }
  }
}
