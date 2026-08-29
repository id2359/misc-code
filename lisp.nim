# Modern Idiomatic Nim: Chapter 2 Lisp Interpreter
# Based on "Programming Languages: An Interpreter-based Approach" by Samuel Kamin

import std/[tables, strutils]

type
  SExpKind = enum
    skNil, skNum, skSym, skList

  SExp = ref object
    case kind: SExpKind
    of skNil: discard
    of skNum: intVal: int
    of skSym: symVal: string
    of skList:
      carVal, cdrVal: SExp

  ExpKind = enum
    ekVal, ekVar, ekCall

  Exp = ref object
    case kind: ExpKind
    of ekVal:
      sxp: SExp
    of ekVar:
      name: string
    of ekCall:
      optr: string
      args: seq[Exp]

  FunDef = object
    params: seq[string]
    body: Exp

  EvalError = object of CatchableError

var
  fundefs = initTable[string, FunDef]()
  globalEnv = initTable[string, SExp]()
  nilValue = SExp(kind: skNil)
  trueValue = SExp(kind: skSym, symVal: "T")

proc `$`(s: SExp): string =
  case s.kind
  of skNil:
    "()"
  of skNum:
    $s.intVal
  of skSym:
    s.symVal
  of skList:
    var res = "(" & $s.carVal
    var cur = s.cdrVal
    while cur != nil and cur.kind == skList:
      res.add(" " & $cur.carVal)
      cur = cur.cdrVal
    if cur != nil and cur.kind != skNil:
      res.add(" . " & $cur)
    res.add(")")
    res

proc isTrue(s: SExp): bool =
  s.kind != skNil

# --- Lexer & Parser ---

type
  TokenKind = enum
    tkLParen, tkRParen, tkQuote, tkInt, tkSym, tkEof

  Token = object
    kind: TokenKind
    strVal: string
    intVal: int

  Scanner = object
    input: string
    pos: int

proc isDelim(c: char): bool =
  c in {'(', ')', '\'', ' ', ';', '\t', '\r', '\n'}

proc nextToken(s: var Scanner): Token =
  while s.pos < s.input.len:
    let c = s.input[s.pos]
    if c in {' ', '\t', '\r', '\n'}:
      inc s.pos
    elif c == ';':
      while s.pos < s.input.len and s.input[s.pos] notin {'\n', '\r'}:
        inc s.pos
    elif c == '(':
      inc s.pos
      return Token(kind: tkLParen, strVal: "(")
    elif c == ')':
      inc s.pos
      return Token(kind: tkRParen, strVal: ")")
    elif c == '\'':
      inc s.pos
      return Token(kind: tkQuote, strVal: "'")
    else:
      let start = s.pos
      var isNum = false
      if c in {'0'..'9'} or (c == '-' and s.pos + 1 < s.input.len and s.input[s.pos + 1] in {'0'..'9'}):
        isNum = true
        var p = if c == '-': s.pos + 1 else: s.pos
        while p < s.input.len and s.input[p] in {'0'..'9'}:
          inc p
        if p < s.input.len and not isDelim(s.input[p]):
          isNum = false

      while s.pos < s.input.len and not isDelim(s.input[s.pos]):
        inc s.pos
      let text = s.input[start ..< s.pos]
      if isNum:
        try:
          return Token(kind: tkInt, strVal: text, intVal: parseInt(text))
        except ValueError:
          return Token(kind: tkSym, strVal: text)
      else:
        return Token(kind: tkSym, strVal: text)

  Token(kind: tkEof, strVal: "")

type Parser = object
  tokens: seq[Token]
  pos: int

proc peek(p: Parser): Token =
  if p.pos < p.tokens.len: p.tokens[p.pos] else: Token(kind: tkEof)

proc next(p: var Parser): Token =
  result = p.peek()
  if p.pos < p.tokens.len: inc p.pos

proc expect(p: var Parser, kind: TokenKind): Token =
  let t = p.next()
  if t.kind != kind:
    raise newException(EvalError, "Expected " & $kind & ", got " & t.strVal)
  t

proc parseSExp(p: var Parser): SExp =
  let tok = p.peek()
  case tok.kind
  of tkInt:
    discard p.next()
    SExp(kind: skNum, intVal: tok.intVal)
  of tkSym:
    discard p.next()
    SExp(kind: skSym, symVal: tok.strVal)
  of tkLParen:
    discard p.next()
    var items: seq[SExp] = @[]
    while p.peek().kind != tkRParen and p.peek().kind != tkEof:
      items.add(p.parseSExp())
    discard p.expect(tkRParen)
    var list = nilValue
    for i in countdown(items.len - 1, 0):
      list = SExp(kind: skList, carVal: items[i], cdrVal: list)
    list
  else:
    raise newException(EvalError, "Unexpected token in S-expression: " & tok.strVal)

proc parseExp(p: var Parser): Exp =
  let tok = p.peek()
  case tok.kind
  of tkQuote:
    discard p.next()
    Exp(kind: ekVal, sxp: p.parseSExp())
  of tkInt:
    discard p.next()
    Exp(kind: ekVal, sxp: SExp(kind: skNum, intVal: tok.intVal))
  of tkSym:
    discard p.next()
    Exp(kind: ekVar, name: tok.strVal)
  of tkLParen:
    discard p.next()
    let opTok = p.expect(tkSym)
    var args: seq[Exp] = @[]
    while p.peek().kind != tkRParen and p.peek().kind != tkEof:
      args.add(p.parseExp())
    discard p.expect(tkRParen)
    Exp(kind: ekCall, optr: opTok.strVal, args: args)
  else:
    raise newException(EvalError, "Unexpected token in expression: " & tok.strVal)

# --- Evaluator ---

proc eval(e: Exp, localEnv: var Table[string, SExp]): SExp =
  case e.kind
  of ekVal:
    result = e.sxp
  of ekVar:
    if localEnv.hasKey(e.name):
      result = localEnv[e.name]
    elif globalEnv.hasKey(e.name):
      result = globalEnv[e.name]
    else:
      stdout.write("Undefined variable: " & e.name & "\n")
      raise newException(EvalError, "Undefined variable: " & e.name)
  of ekCall:
    case e.optr
    of "if":
      if e.args.len != 3:
        raise newException(EvalError, "Wrong number of arguments to if")
      if isTrue(eval(e.args[0], localEnv)):
        result = eval(e.args[1], localEnv)
      else:
        result = eval(e.args[2], localEnv)
    of "while":
      if e.args.len != 2:
        raise newException(EvalError, "Wrong number of arguments to while")
      var res = nilValue
      while isTrue(eval(e.args[0], localEnv)):
        res = eval(e.args[1], localEnv)
      result = res
    of "set":
      if e.args.len != 2 or e.args[0].kind != ekVar:
        raise newException(EvalError, "Invalid syntax for set")
      let val = eval(e.args[1], localEnv)
      let varName = e.args[0].name
      if localEnv.hasKey(varName):
        localEnv[varName] = val
      else:
        globalEnv[varName] = val
      result = val
    of "begin":
      var res = nilValue
      for arg in e.args:
        res = eval(arg, localEnv)
      result = res
    of "+", "-", "*", "/":
      if e.args.len != 2:
        stdout.write("Wrong number of arguments to " & e.optr & "\n")
        raise newException(EvalError, "Wrong number of arguments")
      let s1 = eval(e.args[0], localEnv)
      let s2 = eval(e.args[1], localEnv)
      if s1.kind != skNum or s2.kind != skNum:
        stdout.write("Non-arithmetic arguments to " & e.optr & "\n")
        raise newException(EvalError, "Non-arithmetic arguments")
      let n1 = s1.intVal
      let n2 = s2.intVal
      let res = case e.optr
        of "+": n1 + n2
        of "-": n1 - n2
        of "*": n1 * n2
        of "/":
          if n2 == 0:
            echo "Division by zero"
            raise newException(EvalError, "Division by zero")
          n1 div n2
        else: 0
      result = SExp(kind: skNum, intVal: res)
    of "<", ">":
      if e.args.len != 2:
        stdout.write("Wrong number of arguments to " & e.optr & "\n")
        raise newException(EvalError, "Wrong number of arguments")
      let s1 = eval(e.args[0], localEnv)
      let s2 = eval(e.args[1], localEnv)
      if s1.kind != skNum or s2.kind != skNum:
        stdout.write("Non-arithmetic arguments to " & e.optr & "\n")
        raise newException(EvalError, "Non-arithmetic arguments")
      let cond = if e.optr == "<": s1.intVal < s2.intVal else: s1.intVal > s2.intVal
      result = if cond: trueValue else: nilValue
    of "=":
      if e.args.len != 2:
        stdout.write("Wrong number of arguments to =\n")
        raise newException(EvalError, "Wrong number of arguments")
      let s1 = eval(e.args[0], localEnv)
      let s2 = eval(e.args[1], localEnv)
      var eq = false
      if s1.kind == skNil and s2.kind == skNil:
        eq = true
      elif s1.kind == skNum and s2.kind == skNum and s1.intVal == s2.intVal:
        eq = true
      elif s1.kind == skSym and s2.kind == skSym and s1.symVal == s2.symVal:
        eq = true
      result = if eq: trueValue else: nilValue
    of "cons":
      if e.args.len != 2:
        stdout.write("Wrong number of arguments to cons\n")
        raise newException(EvalError, "Wrong number of arguments")
      let s1 = eval(e.args[0], localEnv)
      let s2 = eval(e.args[1], localEnv)
      result = SExp(kind: skList, carVal: s1, cdrVal: s2)
    of "car":
      if e.args.len != 1:
        stdout.write("Wrong number of arguments to car\n")
        raise newException(EvalError, "Wrong number of arguments")
      let s = eval(e.args[0], localEnv)
      if s.kind != skList:
        stdout.write("Error: car applied to non-list: " & $s & "\n")
        result = nilValue
      else:
        result = s.carVal
    of "cdr":
      if e.args.len != 1:
        stdout.write("Wrong number of arguments to cdr\n")
        raise newException(EvalError, "Wrong number of arguments")
      let s = eval(e.args[0], localEnv)
      if s.kind != skList:
        stdout.write("Error: cdr applied to non-list: " & $s & "\n")
        result = nilValue
      else:
        result = s.cdrVal
    of "number?":
      if e.args.len != 1:
        stdout.write("Wrong number of arguments to number?\n")
        raise newException(EvalError, "Wrong number of arguments")
      result = if eval(e.args[0], localEnv).kind == skNum: trueValue else: nilValue
    of "symbol?":
      if e.args.len != 1:
        stdout.write("Wrong number of arguments to symbol?\n")
        raise newException(EvalError, "Wrong number of arguments")
      result = if eval(e.args[0], localEnv).kind == skSym: trueValue else: nilValue
    of "list?":
      if e.args.len != 1:
        stdout.write("Wrong number of arguments to list?\n")
        raise newException(EvalError, "Wrong number of arguments")
      result = if eval(e.args[0], localEnv).kind == skList: trueValue else: nilValue
    of "null?":
      if e.args.len != 1:
        stdout.write("Wrong number of arguments to null?\n")
        raise newException(EvalError, "Wrong number of arguments")
      result = if eval(e.args[0], localEnv).kind == skNil: trueValue else: nilValue
    of "print":
      if e.args.len != 1:
        stdout.write("Wrong number of arguments to print\n")
        raise newException(EvalError, "Wrong number of arguments")
      let val = eval(e.args[0], localEnv)
      echo $val
      result = val
    else:
      # User-defined function call (Dynamic Scoping)
      if not fundefs.hasKey(e.optr):
        stdout.write("Undefined function: " & e.optr & "\n")
        raise newException(EvalError, "Undefined function: " & e.optr)
      let fn = fundefs[e.optr]
      if fn.params.len != e.args.len:
        stdout.write("Wrong number of arguments to " & e.optr & "\n")
        raise newException(EvalError, "Wrong number of arguments")
      var evaluatedArgs = newSeq[SExp](e.args.len)
      for i, arg in e.args:
        evaluatedArgs[i] = eval(arg, localEnv)
      # Dynamic scoping: extend existing localEnv with bindings, then restore
      var savedBindings: seq[(string, bool, SExp)] = @[]
      for i, p in fn.params:
        let hadOld = localEnv.hasKey(p)
        let oldVal = if hadOld: localEnv[p] else: nil
        savedBindings.add((p, hadOld, oldVal))
        localEnv[p] = evaluatedArgs[i]
      try:
        result = eval(fn.body, localEnv)
      finally:
        for (p, hadOld, oldVal) in savedBindings:
          if hadOld:
            localEnv[p] = oldVal
          else:
            localEnv.del(p)

# --- REPL ---

proc readSExpInput(): string =
  stdout.write("-> ")
  stdout.flushFile()
  var input = ""
  var parenDepth = 0
  var inComment = false

  while true:
    let c = stdin.readChar()
    if c == '\0' or stdin.endOfFile:
      if input.len == 0:
        return ""
      break
    if c == '\r':
      continue
    if c == '\n':
      inComment = false
      if parenDepth > 0:
        stdout.write("> ")
        stdout.flushFile()
        input.add(' ')
      else:
        break
    elif inComment:
      continue
    elif c == ';':
      inComment = true
    elif c == '\t':
      input.add(' ')
    else:
      input.add(c)
      if c == '(': inc parenDepth
      elif c == ')': dec parenDepth

  input

proc tokenize(s: string): seq[Token] =
  var sc = Scanner(input: s, pos: 0)
  while true:
    let tok = sc.nextToken()
    if tok.kind == tkEof: break
    result.add(tok)

proc main() =
  while true:
    let line = readSExpInput()
    if line.len == 0 and stdin.endOfFile:
      break
    if line.strip().len == 0:
      continue

    let tokens = tokenize(line)
    if tokens.len == 0:
      continue

    if tokens.len == 1 and tokens[0].kind == tkSym and tokens[0].strVal == "quit":
      break

    try:
      var p = Parser(tokens: tokens, pos: 0)
      if p.peek().kind == tkLParen and p.tokens.len >= 2 and p.tokens[1].kind == tkSym and p.tokens[1].strVal == "define":
        discard p.next() # '('
        discard p.next() # 'define'
        let fnName = p.expect(tkSym).strVal
        discard p.expect(tkLParen)
        var params: seq[string] = @[]
        while p.peek().kind != tkRParen and p.peek().kind != tkEof:
          params.add(p.expect(tkSym).strVal)
        discard p.expect(tkRParen)
        let body = p.parseExp()
        discard p.expect(tkRParen)
        fundefs[fnName] = FunDef(params: params, body: body)
        echo fnName
      else:
        let exp = p.parseExp()
        var localEnv = initTable[string, SExp]()
        let val = eval(exp, localEnv)
        echo $val
        echo ""
    except EvalError:
      discard

when isMainModule:
  main()
