package org.kaijinlab.tap_ducky

import kotlin.math.abs

internal class DuckyExpressionSyntaxException(message: String) : DuckyScriptValueException(message) {
  var lineNumber: Int? = null
}

class ExpressionEvaluator(
  private val readInternalVariable: (String) -> Int? = {
    if (it == DuckyScriptHostOs.variable) 0 else null
  },
) {
  private enum class Kind { NUM, VAR, IDENT, OP, LPAREN, RPAREN, END }
  private data class Tok(val kind: Kind, val text: String)

  fun evaluate(expression: String, variables: Map<String, Int>): Int {
    val tokens = tokenize(expression)
    val p = Parser(tokens, variables, readInternalVariable)
    return p.parse()
  }

  internal fun validateSyntax(expression: String) {
    Parser(tokenize(expression), emptyMap(), { 0 }, syntaxOnly = true).parse()
  }

  internal fun evaluateCondition(
    expression: String,
    variables: Map<String, Int>,
    onInvalidExpression: () -> Unit = {},
  ): Boolean = try {
    evaluate(expression, variables) != 0
  } catch (error: DuckyScriptValueException) {
    throw error
  } catch (_: Exception) {
    onInvalidExpression()
    false
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
        "&&", "||", "==", "!=", "<=", ">=", "<<", ">>" -> {
          out.add(Tok(Kind.OP, two))
          i += 2
          continue
        }
      }

      when (c) {
        '+', '-', '*', '/', '%', '^', '<', '>', '!', '&', '|' -> {
          out.add(Tok(Kind.OP, c.toString()))
          i++
          continue
        }

        '=' -> {
          out.add(Tok(Kind.OP, "=="))
          i++
          continue
        }

        else -> throw DuckyExpressionSyntaxException("Unexpected character '$c' in expression")
      }
    }

    out.add(Tok(Kind.END, ""))
    return out
  }

  private class Parser(
    private val tokens: List<Tok>,
    private val vars: Map<String, Int>,
    private val readInternalVariable: (String) -> Int?,
    private val syntaxOnly: Boolean = false,
  ) {
    private var pos = 0

    fun parse(): Int {
      val value = parseOr()
      if (peek().kind != Kind.END) {
        throw DuckyExpressionSyntaxException("Unexpected token '${peek().text}' after expression")
      }
      return value
    }

    private fun peek(): Tok = tokens[pos]

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
      var left = parseBitwiseOr()
      while (matchOp("&&")) {
        val right = parseBitwiseOr()
        left = b(toBool(left) && toBool(right))
      }
      return left
    }

    private fun parseBitwiseOr(): Int {
      var left = parseBitwiseAnd()
      while (matchOp("|")) left = asU16(left or parseBitwiseAnd())
      return left
    }

    private fun parseBitwiseAnd(): Int {
      var left = parseEquality()
      while (matchOp("&")) left = asU16(left and parseEquality())
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
      var left = parseShift()
      while (true) {
        when {
          matchOp("<=") -> {
            val right = parseShift()
            left = b(left <= right)
          }

          matchOp(">=") -> {
            val right = parseShift()
            left = b(left >= right)
          }

          matchOp("<") -> {
            val right = parseShift()
            left = b(left < right)
          }

          matchOp(">") -> {
            val right = parseShift()
            left = b(left > right)
          }

          else -> return left
        }
      }
    }

    private fun asU16(value: Int): Int = value and 0xffff

    private fun parseShift(): Int {
      var left = parseAddSub()
      while (true) {
        val operator = when {
          matchOp("<<") -> "<<"
          matchOp(">>") -> ">>"
          else -> return left
        }
        val count = asU16(parseAddSub())
        left = when {
          count >= 16 -> 0
          operator == "<<" -> asU16(left shl count)
          else -> asU16(left) ushr count
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
          matchOp("/") -> left /= parseDivisor("Division")
          matchOp("%") -> left %= parseDivisor("Remainder")

          else -> return left
        }
      }
    }

    private fun parseDivisor(operation: String): Int {
      val divisor = parsePower()
      if (divisor != 0) return divisor
      if (syntaxOnly) return 1
      throw DuckyScriptValueException("$operation by zero in expression")
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
        val literal = n.text
        val value = if (literal.startsWith("0x", ignoreCase = true)) {
          literal.substring(2).toIntOrNull(16)
        } else {
          literal.toIntOrNull()
        }
        return value ?: throw DuckyExpressionSyntaxException("Invalid or out-of-range integer literal: $literal")
      }

      val v = match(Kind.VAR)
      if (v != null) {
        val name = v.text
        val value = readInternalVariable(name) ?: vars[name]
        if (value != null) return value
        if (name.startsWith("\$_")) throw DuckyVariableException("Unknown internal variable '$name'")
        return 0
      }

      val id = match(Kind.IDENT)
      if (id != null) {
        if (id.text.equals("TRUE", ignoreCase = true)) return 1
        if (id.text.equals("FALSE", ignoreCase = true)) return 0
        return DuckyScriptHostOs.constant(id.text)
          ?: throw DuckyExpressionSyntaxException("Unknown constant '${id.text}'")
      }

      if (match(Kind.LPAREN) != null) {
        val inside = parseOr()
        if (match(Kind.RPAREN) == null) {
          throw DuckyExpressionSyntaxException("Missing closing parenthesis in expression")
        }
        return inside
      }

      val unexpected = peek()
      val message = if (unexpected.kind == Kind.END) {
        "Expected a value at the end of the expression"
      } else {
        "Expected a value in expression, got '${unexpected.text}'"
      }
      throw DuckyExpressionSyntaxException(message)
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
