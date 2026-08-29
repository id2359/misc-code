# Modern Idiomatic Nim: Chapter 4 Scheme Interpreter
# Based on "Programming Languages: An Interpreter-based Approach" by Samuel Kamin

import std/[tables, strutils]

type
  Env = ref object
    bindings: Table[string, SExp]
    enclosing: Env

  SExpKind = enum
    skNil, skNum, skSym, skList, skClosure, skPrim

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

  EvalError = object of CatchableError

var
  globalEnv: Env
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
  of skClosure:
    "<closure>"
  of skPrim:
    "<primitive>"

proc isTrue(s: SExp): bool =
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

proc eval(e: Exp, env: Env): SExp

proc applyPrim(name: string, actuals: seq[SExp]): SExp =
  proc arity(op: string): int =
    case op
    of "+", "-", "*", "/", "=", "<", ">", "cons": 2
    of "car", "cdr", "number?", "symbol?", "list?", "null?", "primop?", "closure?", "print": 1
    else: 0

  if arity(name) != actuals.len:
    stdout.write("Wrong number of arguments to " & name & "\n")
    raise newException(EvalError, "Wrong number of arguments")

  case name
  of "+", "-", "*", "/":
    let s1 = actuals[0]
    let s2 = actuals[1]
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
    let s1 = actuals[0]
    let s2 = actuals[1]
    if s1.kind != skNum or s2.kind != skNum:
      stdout.write("Non-arithmetic arguments to " & name & "\n")
      raise newException(EvalError, "Non-arithmetic arguments")
    let cond = if name == "<": s1.intVal < s2.intVal else: s1.intVal > s2.intVal
    if cond: trueValue else: nilValue
  of "=":
    let s1 = actuals[0]
    let s2 = actuals[1]
    var eq = false
    if s1.kind == skNil and s2.kind == skNil:
      eq = true
    elif s1.kind == skNum and s2.kind == skNum and s1.intVal == s2.intVal:
      eq = true
    elif s1.kind == skSym and s2.kind == skSym and s1.symVal == s2.symVal:
      eq = true
    if eq: trueValue else: nilValue
  of "cons":
    SExp(kind: skList, carVal: actuals[0], cdrVal: actuals[1])
  of "car":
    let s = actuals[0]
    if s.kind != skList:
      stdout.write("Error: car applied to non-list: " & $s & "\n")
      nilValue
    else:
      s.carVal
  of "cdr":
    let s = actuals[0]
    if s.kind != skList:
      stdout.write("Error: cdr applied to non-list: " & $s & "\n")
      nilValue
    else:
      s.cdrVal
  of "number?":
    if actuals[0].kind == skNum: trueValue else: nilValue
  of "symbol?":
    if actuals[0].kind == skSym: trueValue else: nilValue
  of "list?":
    if actuals[0].kind == skList: trueValue else: nilValue
  of "null?":
    if actuals[0].kind == skNil: trueValue else: nilValue
  of "primop?":
    if actuals[0].kind == skPrim: trueValue else: nilValue
  of "closure?":
    if actuals[0].kind == skClosure: trueValue else: nilValue
  of "print":
    echo $actuals[0]
    actuals[0]
  else:
    nilValue

proc eval(e: Exp, env: Env): SExp =
  case e.kind
  of ekVal:
    result = e.sxp
  of ekVar:
    result = fetch(env, e.name)
  of ekLambda:
    result = SExp(kind: skClosure, params: e.formals, body: e.lambdaBody, closureEnv: env)
  of ekCall:
    # Check for special forms if optr is a variable
    if e.optr.kind == ekVar:
      case e.optr.name
      of "if":
        if e.args.len != 3:
          raise newException(EvalError, "Wrong number of arguments to if")
        if isTrue(eval(e.args[0], env)):
          return eval(e.args[1], env)
        else:
          return eval(e.args[2], env)
      of "while":
        if e.args.len != 2:
          raise newException(EvalError, "Wrong number of arguments to while")
        var res = nilValue
        while isTrue(eval(e.args[0], env)):
          res = eval(e.args[1], env)
        return res
      of "set":
        if e.args.len != 2 or e.args[0].kind != ekVar:
          raise newException(EvalError, "Invalid syntax for set")
        let val = eval(e.args[1], env)
        assign(env, e.args[0].name, val)
        return val
      of "begin":
        var res = nilValue
        for arg in e.args:
          res = eval(arg, env)
        return res
      else:
        discard

    # Standard function application
    let fn = eval(e.optr, env)
    var evaluatedArgs = newSeq[SExp](e.args.len)
    for i, arg in e.args:
      evaluatedArgs[i] = eval(arg, env)

    case fn.kind
    of skPrim:
      result = applyPrim(fn.primName, evaluatedArgs)
    of skClosure:
      if fn.params.len != evaluatedArgs.len:
        stdout.write("Wrong number of arguments to closure\n")
        raise newException(EvalError, "Wrong number of arguments")
      var newEnv = Env(bindings: initTable[string, SExp](), enclosing: fn.closureEnv)
      for i, p in fn.params:
        newEnv.bindings[p] = evaluatedArgs[i]
      result = eval(fn.body, newEnv)
    else:
      stdout.write("Applied non-function: " & $fn & "\n")
      raise newException(EvalError, "Applied non-function: " & $fn)

# --- REPL ---

proc initGlobalEnv() =
  globalEnv = Env(bindings: initTable[string, SExp](), enclosing: nil)
  let prims = [
    "+", "-", "*", "/", "=", "<", ">",
    "cons", "car", "cdr",
    "number?", "symbol?", "list?", "null?", "primop?", "closure?", "print"
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
        let clos = SExp(kind: skClosure, params: params, body: body, closureEnv: globalEnv)
        globalEnv.bindings[fnName] = clos
        echo fnName
      else:
        let exp = p.parseExp()
        let val = eval(exp, globalEnv)
        echo $val
        echo ""
    except EvalError:
      discard

when isMainModule:
  main()
