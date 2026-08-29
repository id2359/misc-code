# Modern Idiomatic Nim: Chapter 5 SASL (Lazy Evaluation) Interpreter
# Based on "Programming Languages: An Interpreter-based Approach" by Samuel Kamin

import std/[tables, strutils]

type
  Env = ref object
    bindings: Table[string, SExp]
    enclosing: Env

  SExpKind = enum
    skNil, skNum, skSym, skList, skClosure, skPrim, skThunk

  ExpKind = enum
    ekVal, ekVar, ekLambda, ekCall

  Exp = ref object
    case kind: ExpKind
    of ekVal:
      sxp: SExp
    of ekVar:
      name: string
    of ekLambda:
      formals: seq[string]
      lambdaBody: Exp
    of ekCall:
      optr: Exp
      args: seq[Exp]

  SExp = ref object
    case kind: SExpKind
    of skNil: discard
    of skNum: intVal: int
    of skSym: symVal: string
    of skList:
      carVal, cdrVal: SExp
    of skClosure:
      params: seq[string]
      body: Exp
      closureEnv: Env
    of skPrim:
      primName: string
    of skThunk:
      thunkExp: Exp
      thunkEnv: Env

  EvalError = object of CatchableError

var
  globalEnv: Env
  nilValue = SExp(kind: skNil)
  trueValue = SExp(kind: skSym, symVal: "T")

proc eval(e: Exp, env: Env): SExp

proc evalThunk(s: SExp) =
  if s != nil and s.kind == skThunk:
    let val = eval(s.thunkExp, s.thunkEnv)
    evalThunk(val)
    s[] = val[]

proc prValue(s: SExp) =
  case s.kind
  of skNil:
    stdout.write("()")
  of skNum:
    stdout.write($s.intVal)
  of skSym:
    stdout.write(s.symVal)
  of skPrim:
    stdout.write("<primitive: " & s.primName & ">")
  of skClosure:
    stdout.write("<closure>")
  of skThunk:
    stdout.write("...")
  of skList:
    stdout.write("(")
    prValue(s.carVal)
    var s1 = s.cdrVal
    while s1 != nil and s1.kind == skList:
      stdout.write(" ")
      prValue(s1.carVal)
      s1 = s1.cdrVal
    if s1 != nil and s1.kind == skThunk:
      stdout.write(" ...)")
    elif s1 != nil and s1.kind != skNil:
      stdout.write(" . ")
      prValue(s1)
      stdout.write(")")
    else:
      stdout.write(")")

proc isTrue(s: SExp): bool =
  evalThunk(s)
  s.kind != skNil

proc findEnv(env: Env, name: string): Env =
  var cur = env
  while cur != nil:
    if cur.bindings.hasKey(name):
      return cur
    cur = cur.enclosing
  nil

proc fetch(env: Env, name: string): SExp =
  let e = findEnv(env, name)
  if e != nil:
    e.bindings[name]
  else:
    stdout.write("Undefined variable: " & name & "\n")
    raise newException(EvalError, "Undefined variable: " & name)

proc assign(env: Env, name: string, val: SExp) =
  let e = findEnv(env, name)
  if e != nil:
    e.bindings[name] = val
  else:
    globalEnv.bindings[name] = val

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
    if p.peek().kind == tkSym and p.peek().strVal == "lambda":
      discard p.next() # 'lambda'
      discard p.expect(tkLParen)
      var params: seq[string] = @[]
      while p.peek().kind != tkRParen and p.peek().kind != tkEof:
        params.add(p.expect(tkSym).strVal)
      discard p.expect(tkRParen)
      let body = p.parseExp()
      discard p.expect(tkRParen)
      Exp(kind: ekLambda, formals: params, lambdaBody: body)
    else:
      let opExp = p.parseExp()
      var args: seq[Exp] = @[]
      while p.peek().kind != tkRParen and p.peek().kind != tkEof:
        args.add(p.parseExp())
      discard p.expect(tkRParen)
      Exp(kind: ekCall, optr: opExp, args: args)
  else:
    raise newException(EvalError, "Unexpected token in expression: " & tok.strVal)

# --- Evaluator ---

proc applyValueOp(name: string, actuals: seq[SExp]): SExp =
  proc arity(op: string): int =
    case op
    of "+", "-", "*", "/", "=", "<", ">", "cons": 2
    of "car", "cdr", "number?", "symbol?", "list?", "null?", "primop?", "closure?": 1
    else: 0

  if arity(name) != actuals.len:
    stdout.write("Wrong number of arguments to " & name & "\n")
    raise newException(EvalError, "Wrong number of arguments")

  let s1 = actuals[0]
  var s2: SExp = nil
  if actuals.len == 2:
    s2 = actuals[1]

  if name != "cons":
    evalThunk(s1)
  if name in ["+", "-", "*", "/", "=", "<", ">"]:
    evalThunk(s2)

  case name
  of "+", "-", "*", "/":
    if s1.kind != skNum or s2.kind != skNum:
      stdout.write("Non-arithmetic arguments to " & name & "\n")
      raise newException(EvalError, "Non-arithmetic arguments")
    let n1 = s1.intVal
    let n2 = s2.intVal
    let res = case name
      of "+": n1 + n2
      of "-": n1 - n2
      of "*": n1 * n2
      of "/":
        if n2 == 0:
          echo "Division by zero"
          raise newException(EvalError, "Division by zero")
        n1 div n2
      else: 0
    SExp(kind: skNum, intVal: res)
  of "<", ">":
    if s1.kind != skNum or s2.kind != skNum:
      stdout.write("Non-arithmetic arguments to " & name & "\n")
      raise newException(EvalError, "Non-arithmetic arguments")
    let cond = if name == "<": s1.intVal < s2.intVal else: s1.intVal > s2.intVal
    if cond: trueValue else: nilValue
  of "=":
    var eq = false
    if s1.kind == skNil and s2.kind == skNil:
      eq = true
    elif s1.kind == skNum and s2.kind == skNum and s1.intVal == s2.intVal:
      eq = true
    elif s1.kind == skSym and s2.kind == skSym and s1.symVal == s2.symVal:
      eq = true
    if eq: trueValue else: nilValue
  of "cons":
    SExp(kind: skList, carVal: s1, cdrVal: s2)
  of "car":
    if s1.kind != skList:
      stdout.write("Error: car applied to non-list: ")
      prValue(s1)
      stdout.write("\n")
      nilValue
    else:
      evalThunk(s1.carVal)
      s1.carVal
  of "cdr":
    if s1.kind != skList:
      stdout.write("Error: cdr applied to non-list: ")
      prValue(s1)
      stdout.write("\n")
      nilValue
    else:
      evalThunk(s1.cdrVal)
      s1.cdrVal
  of "number?":
    if s1.kind == skNum: trueValue else: nilValue
  of "symbol?":
    if s1.kind == skSym: trueValue else: nilValue
  of "list?":
    if s1.kind == skList: trueValue else: nilValue
  of "null?":
    if s1.kind == skNil: trueValue else: nilValue
  of "primop?":
    if s1.kind == skPrim: trueValue else: nilValue
  of "closure?":
    if s1.kind == skClosure: trueValue else: nilValue
  else:
    nilValue

proc eval(e: Exp, env: Env): SExp =
  case e.kind
  of ekVal:
    result = e.sxp
  of ekVar:
    let s = fetch(env, e.name)
    evalThunk(s)
    result = s
  of ekLambda:
    result = SExp(kind: skClosure, params: e.formals, body: e.lambdaBody, closureEnv: env)
  of ekCall:
    let op = eval(e.optr, env)
    evalThunk(op)

    if op.kind == skPrim and op.primName == "if":
      if e.args.len != 3:
        raise newException(EvalError, "Wrong number of arguments to if")
      let cond = eval(e.args[0], env)
      evalThunk(cond)
      if isTrue(cond):
        return eval(e.args[1], env)
      else:
        return eval(e.args[2], env)

    # Lazy argument list: create thunks for arguments
    var thunkArgs = newSeq[SExp](e.args.len)
    for i, arg in e.args:
      thunkArgs[i] = SExp(kind: skThunk, thunkExp: arg, thunkEnv: env)

    case op.kind
    of skPrim:
      result = applyValueOp(op.primName, thunkArgs)
    of skClosure:
      if op.params.len != thunkArgs.len:
        stdout.write("Wrong number of arguments to closure\n")
        raise newException(EvalError, "Wrong number of arguments")
      var newEnv = Env(bindings: initTable[string, SExp](), enclosing: op.closureEnv)
      for i, p in op.params:
        newEnv.bindings[p] = thunkArgs[i]
      result = eval(op.body, newEnv)
    else:
      stdout.write("Applied non-function: ")
      prValue(op)
      stdout.write("\n")
      raise newException(EvalError, "Applied non-function")

# --- REPL ---

proc initGlobalEnv() =
  globalEnv = Env(bindings: initTable[string, SExp](), enclosing: nil)
  let prims = [
    "if",
    "+", "-", "*", "/", "=", "<", ">",
    "cons", "car", "cdr",
    "number?", "symbol?", "list?", "null?", "primop?", "closure?"
  ]
  for p in prims:
    globalEnv.bindings[p] = SExp(kind: skPrim, primName: p)
  globalEnv.bindings["T"] = trueValue

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
  initGlobalEnv()
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
      if p.peek().kind == tkLParen and p.tokens.len >= 3 and p.tokens[1].kind == tkSym and p.tokens[1].strVal == "set":
        discard p.next() # '('
        discard p.next() # 'set'
        let varName = p.expect(tkSym).strVal
        let valExp = p.parseExp()
        discard p.expect(tkRParen)
        let setVal = eval(valExp, globalEnv)
        globalEnv.bindings[varName] = setVal
        prValue(setVal)
        stdout.write("\n\n")
      else:
        let exp = p.parseExp()
        let val = eval(exp, globalEnv)
        prValue(val)
        stdout.write("\n\n")
    except EvalError:
      discard

when isMainModule:
  main()
