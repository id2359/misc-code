# Modern Idiomatic Nim: Lisp with Explicit Evaluation Stack
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

  FunDef = ref object
    name: string
    params: seq[string]
    body: Exp

  EvalError = object of CatchableError

var
  fundefs = initTable[string, FunDef]()
  globalEnv = initTable[string, SExp]()
  evalStack: seq[SExp] = @[]
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

proc fetch(name: string): SExp =
  if globalEnv.hasKey(name):
    globalEnv[name]
  else:
    stdout.write("Undefined variable: " & name & "\n")
    raise newException(EvalError, "Undefined variable: " & name)

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
    let opName = p.expect(tkSym).strVal
    var args: seq[Exp] = @[]
    while p.peek().kind != tkRParen and p.peek().kind != tkEof:
      args.add(p.parseExp())
    discard p.expect(tkRParen)
    Exp(kind: ekCall, optr: opName, args: args)
  else:
    raise newException(EvalError, "Unexpected token in expression: " & tok.strVal)

# --- Evaluator using Explicit Stack ---

proc eval(e: Exp)

proc applyValueOp(op: string, numArgs: int) =
  proc arity(o: string): int =
    case o
    of "+", "-", "*", "/", "=", "<", ">", "cons": 2
    of "car", "cdr", "number?", "symbol?", "list?", "null?", "print": 1
    else: 0

  if arity(op) != numArgs:
    stdout.write("Wrong number of arguments to " & op & "\n")
    raise newException(EvalError, "Wrong number of arguments")

  let s2 = if numArgs == 2: evalStack.pop() else: nil
  let s1 = evalStack.pop()

  case op
  of "+", "-", "*", "/":
    if s1.kind != skNum or s2.kind != skNum:
      stdout.write("Non-arithmetic arguments to " & op & "\n")
      raise newException(EvalError, "Non-arithmetic arguments")
    let n1 = s1.intVal
    let n2 = s2.intVal
    let res = case op
      of "+": n1 + n2
      of "-": n1 - n2
      of "*": n1 * n2
      of "/":
        if n2 == 0:
          echo "Division by zero"
          raise newException(EvalError, "Division by zero")
        n1 div n2
      else: 0
    evalStack.add(SExp(kind: skNum, intVal: res))
  of "<", ">":
    if s1.kind != skNum or s2.kind != skNum:
      stdout.write("Non-arithmetic arguments to " & op & "\n")
      raise newException(EvalError, "Non-arithmetic arguments")
    let cond = if op == "<": s1.intVal < s2.intVal else: s1.intVal > s2.intVal
    evalStack.add(if cond: trueValue else: nilValue)
  of "=":
    var eq = false
    if s1.kind == skNil and s2.kind == skNil:
      eq = true
    elif s1.kind == skNum and s2.kind == skNum and s1.intVal == s2.intVal:
      eq = true
    elif s1.kind == skSym and s2.kind == skSym and s1.symVal == s2.symVal:
      eq = true
    evalStack.add(if eq: trueValue else: nilValue)
  of "cons":
    evalStack.add(SExp(kind: skList, carVal: s1, cdrVal: s2))
  of "car":
    if s1.kind != skList:
      stdout.write("Error: car applied to non-list: " & $s1 & "\n")
      evalStack.add(nilValue)
    else:
      evalStack.add(s1.carVal)
  of "cdr":
    if s1.kind != skList:
      stdout.write("Error: cdr applied to non-list: " & $s1 & "\n")
      evalStack.add(nilValue)
    else:
      evalStack.add(s1.cdrVal)
  of "number?":
    evalStack.add(if s1.kind == skNum: trueValue else: nilValue)
  of "symbol?":
    evalStack.add(if s1.kind == skSym: trueValue else: nilValue)
  of "list?":
    evalStack.add(if s1.kind == skList: trueValue else: nilValue)
  of "null?":
    evalStack.add(if s1.kind == skNil: trueValue else: nilValue)
  of "print":
    echo $s1
    evalStack.add(s1)
  else:
    evalStack.add(nilValue)

proc applyUserFun(fn: FunDef, numArgs: int) =
  if fn.params.len != numArgs:
    stdout.write("Wrong number of arguments to: " & fn.name & "\n")
    raise newException(EvalError, "Wrong number of arguments")

  # Pop arguments in reverse order from evalStack
  var actuals = newSeq[SExp](numArgs)
  for i in countdown(numArgs - 1, 0):
    actuals[i] = evalStack.pop()

  # Save old parameter bindings (dynamic scoping)
  var savedBindings = newSeq[(string, bool, SExp)](numArgs)
  for i, param in fn.params:
    let existed = globalEnv.hasKey(param)
    let oldVal = if existed: globalEnv[param] else: nil
    savedBindings[i] = (param, existed, oldVal)
    globalEnv[param] = actuals[i]

  try:
    eval(fn.body)
  finally:
    # Restore parameter bindings
    for i in countdown(numArgs - 1, 0):
      let (param, existed, oldVal) = savedBindings[i]
      if existed:
        globalEnv[param] = oldVal
      else:
        globalEnv.del(param)

proc eval(e: Exp) =
  case e.kind
  of ekVal:
    evalStack.add(e.sxp)
  of ekVar:
    evalStack.add(fetch(e.name))
  of ekCall:
    case e.optr
    of "if":
      if e.args.len != 3:
        raise newException(EvalError, "Wrong number of arguments to if")
      eval(e.args[0])
      let cond = evalStack.pop()
      if isTrue(cond):
        eval(e.args[1])
      else:
        eval(e.args[2])
    of "while":
      if e.args.len != 2:
        raise newException(EvalError, "Wrong number of arguments to while")
      eval(e.args[0])
      var cond = evalStack.pop()
      while isTrue(cond):
        eval(e.args[1])
        discard evalStack.pop()
        eval(e.args[0])
        cond = evalStack.pop()
      evalStack.add(nilValue)
    of "set":
      if e.args.len != 2 or e.args[0].kind != ekVar:
        raise newException(EvalError, "Invalid syntax for set")
      eval(e.args[1])
      let val = evalStack[^1] # set returns the assigned value
      globalEnv[e.args[0].name] = val
    of "begin":
      for i, arg in e.args:
        eval(arg)
        if i < e.args.len - 1:
          discard evalStack.pop()
    of "+", "-", "*", "/", "=", "<", ">", "cons", "car", "cdr", "number?", "symbol?", "list?", "null?", "print":
      for arg in e.args:
        eval(arg)
      applyValueOp(e.optr, e.args.len)
    else:
      if fundefs.hasKey(e.optr):
        for arg in e.args:
          eval(arg)
        applyUserFun(fundefs[e.optr], e.args.len)
      else:
        stdout.write("Undefined function: " & e.optr & "\n")
        raise newException(EvalError, "Undefined function: " & e.optr)

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
  globalEnv["T"] = trueValue
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
        fundefs[fnName] = FunDef(name: fnName, params: params, body: body)
        echo fnName
      else:
        let exp = p.parseExp()
        evalStack.setLen(0)
        eval(exp)
        if evalStack.len > 0:
          let val = evalStack.pop()
          echo $val
        else:
          echo "()"
        echo ""
    except EvalError:
      discard

when isMainModule:
  main()
