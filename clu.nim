# Modern Idiomatic Nim: Chapter 6 CLU (Clusters & ADTs) Interpreter
# Based on "Programming Languages: An Interpreter-based Approach" by Samuel Kamin

import std/[tables, strutils]

type
  CluValueKind = enum
    vkPrim, vkUser

  CluValue = ref object
    case kind: CluValueKind
    of vkPrim:
      intVal: int
    of vkUser:
      fields: Table[string, CluValue]

  FunType = enum
    fnNormal, fnConstructor, fnSelector, fnSettor

  ExpKind = enum
    ekVal, ekVar, ekCall

  Exp = ref object
    case kind: ExpKind
    of ekVal:
      val: CluValue
    of ekVar:
      name: string
    of ekCall:
      funName: string
      clustName: string # empty if one-part
      args: seq[Exp]

  FunDef = ref object
    name: string
    case ftype: FunType
    of fnNormal:
      params: seq[string]
      body: Exp
    of fnConstructor, fnSelector:
      discard
    of fnSettor:
      selName: string

  Cluster = ref object
    name: string
    rep: seq[string]
    exported: Table[string, FunDef]
    nonexported: Table[string, FunDef]

  EvalError = object of CatchableError

var
  fundefs = initTable[string, FunDef]()
  clusters = initTable[string, Cluster]()
  globalEnv = initTable[string, CluValue]()

proc prValue(v: CluValue) =
  case v.kind
  of vkPrim:
    stdout.write($v.intVal)
  of vkUser:
    stdout.write("<userval>")

proc isTrue(v: CluValue): bool =
  case v.kind
  of vkPrim: v.intVal != 0
  of vkUser: true

# --- Lexer & Parser ---

type
  TokenKind = enum
    tkLParen, tkRParen, tkDollar, tkInt, tkSym, tkEof

  Token = object
    kind: TokenKind
    strVal: string
    intVal: int

  Scanner = object
    input: string
    pos: int

proc isDelim(c: char): bool =
  c in {'(', ')', '$', ' ', ';', '\t', '\r', '\n'}

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
    elif c == '$':
      inc s.pos
      return Token(kind: tkDollar, strVal: "$")
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

proc parseExp(p: var Parser): Exp =
  let tok = p.peek()
  case tok.kind
  of tkInt:
    discard p.next()
    Exp(kind: ekVal, val: CluValue(kind: vkPrim, intVal: tok.intVal))
  of tkSym:
    discard p.next()
    Exp(kind: ekVar, name: tok.strVal)
  of tkLParen:
    discard p.next()
    var fnName = p.expect(tkSym).strVal
    var clName = ""
    if p.peek().kind == tkDollar:
      discard p.next() # '$'
      clName = fnName
      fnName = p.expect(tkSym).strVal
    var args: seq[Exp] = @[]
    while p.peek().kind != tkRParen and p.peek().kind != tkEof:
      args.add(p.parseExp())
    discard p.expect(tkRParen)
    Exp(kind: ekCall, funName: fnName, clustName: clName, args: args)
  else:
    raise newException(EvalError, "Unexpected token in expression: " & tok.strVal)

# --- Evaluator ---

proc eval(e: Exp, localEnv: var Table[string, CluValue], currentClust: string): CluValue

proc applyOp(op: string, n1, n2: int): int =
  case op
  of "+": n1 + n2
  of "-": n1 - n2
  of "*": n1 * n2
  of "/":
    if n2 == 0:
      echo "Division by zero"
      raise newException(EvalError, "Division by zero")
    n1 div n2
  of "=": (if n1 == n2: 1 else: 0)
  of "<": (if n1 < n2: 1 else: 0)
  of ">": (if n1 > n2: 1 else: 0)
  else: 0

proc eval(e: Exp, localEnv: var Table[string, CluValue], currentClust: string): CluValue =
  case e.kind
  of ekVal:
    result = e.val
  of ekVar:
    if localEnv.hasKey(e.name):
      result = localEnv[e.name]
    elif globalEnv.hasKey(e.name):
      result = globalEnv[e.name]
    else:
      stdout.write("Undefined variable: " & e.name & "\n")
      raise newException(EvalError, "Undefined variable: " & e.name)
  of ekCall:
    if e.clustName.len == 0:
      case e.funName
      of "if":
        if e.args.len != 3:
          raise newException(EvalError, "Wrong number of arguments to if")
        if isTrue(eval(e.args[0], localEnv, currentClust)):
          return eval(e.args[1], localEnv, currentClust)
        else:
          return eval(e.args[2], localEnv, currentClust)
      of "while":
        if e.args.len != 2:
          raise newException(EvalError, "Wrong number of arguments to while")
        var cond = eval(e.args[0], localEnv, currentClust)
        while isTrue(cond):
          discard eval(e.args[1], localEnv, currentClust)
          cond = eval(e.args[0], localEnv, currentClust)
        return cond
      of "set":
        if e.args.len != 2 or e.args[0].kind != ekVar:
          raise newException(EvalError, "Invalid syntax for set")
        let val = eval(e.args[1], localEnv, currentClust)
        let varName = e.args[0].name
        if localEnv.hasKey(varName):
          localEnv[varName] = val
        else:
          globalEnv[varName] = val
        return val
      of "begin":
        var res = CluValue(kind: vkPrim, intVal: 0)
        for arg in e.args:
          res = eval(arg, localEnv, currentClust)
        return res
      of "+", "-", "*", "/", "=", "<", ">":
        if e.args.len != 2:
          stdout.write("Wrong number of arguments to " & e.funName & "\n")
          raise newException(EvalError, "Wrong number of arguments")
        let v1 = eval(e.args[0], localEnv, currentClust)
        let v2 = eval(e.args[1], localEnv, currentClust)
        if v1.kind != vkPrim or v2.kind != vkPrim:
          stdout.write("Non-arithmetic arguments to " & e.funName & "\n")
          raise newException(EvalError, "Non-arithmetic arguments")
        return CluValue(kind: vkPrim, intVal: applyOp(e.funName, v1.intVal, v2.intVal))
      of "print":
        if e.args.len != 1:
          stdout.write("Wrong number of arguments to print\n")
          raise newException(EvalError, "Wrong number of arguments")
        let val = eval(e.args[0], localEnv, currentClust)
        prValue(val)
        stdout.write("\n")
        return val
      else:
        discard

    # Evaluate arguments
    var evaluatedArgs = newSeq[CluValue](e.args.len)
    for i, arg in e.args:
      evaluatedArgs[i] = eval(arg, localEnv, currentClust)

    # Function dispatch
    var targetFun: FunDef = nil
    var targetClust = ""

    if e.clustName.len > 0:
      # Two-part name: C$op
      if not clusters.hasKey(e.clustName):
        stdout.write("Undefined cluster: " & e.clustName & "\n")
        raise newException(EvalError, "Undefined cluster")
      let cl = clusters[e.clustName]
      if cl.exported.hasKey(e.funName):
        targetFun = cl.exported[e.funName]
        targetClust = e.clustName
      elif currentClust == e.clustName and cl.nonexported.hasKey(e.funName):
        targetFun = cl.nonexported[e.funName]
        targetClust = e.clustName
      else:
        stdout.write("Undefined cluster operation: " & e.clustName & "$" & e.funName & "\n")
        raise newException(EvalError, "Undefined cluster operation")
    else:
      # One-part name
      if currentClust.len > 0 and clusters.hasKey(currentClust):
        let cl = clusters[currentClust]
        if cl.exported.hasKey(e.funName):
          targetFun = cl.exported[e.funName]
          targetClust = currentClust
        elif cl.nonexported.hasKey(e.funName):
          targetFun = cl.nonexported[e.funName]
          targetClust = currentClust

      if targetFun == nil:
        if fundefs.hasKey(e.funName):
          targetFun = fundefs[e.funName]
          targetClust = ""
        else:
          stdout.write("Undefined function: " & e.funName & "\n")
          raise newException(EvalError, "Undefined function")

    case targetFun.ftype
    of fnNormal:
      if targetFun.params.len != evaluatedArgs.len:
        stdout.write("Wrong number of arguments to " & targetFun.name & "\n")
        raise newException(EvalError, "Wrong number of arguments")
      var newLocalEnv = initTable[string, CluValue]()
      for i, p in targetFun.params:
        newLocalEnv[p] = evaluatedArgs[i]
      result = eval(targetFun.body, newLocalEnv, targetClust)
    of fnConstructor:
      let cl = clusters[targetClust]
      if cl.rep.len != evaluatedArgs.len:
        stdout.write("Wrong number of arguments to " & targetFun.name & "\n")
        raise newException(EvalError, "Wrong number of arguments")
      var recFields = initTable[string, CluValue]()
      for i, f in cl.rep:
        recFields[f] = evaluatedArgs[i]
      result = CluValue(kind: vkUser, fields: recFields)
    of fnSelector:
      if evaluatedArgs.len != 1 or evaluatedArgs[0].kind != vkUser:
        stdout.write("Wrong arguments to selector " & targetFun.name & "\n")
        raise newException(EvalError, "Wrong arguments to selector")
      result = evaluatedArgs[0].fields[targetFun.name]
    of fnSettor:
      if evaluatedArgs.len != 2 or evaluatedArgs[0].kind != vkUser:
        stdout.write("Wrong arguments to settor " & targetFun.name & "\n")
        raise newException(EvalError, "Wrong arguments to settor")
      evaluatedArgs[0].fields[targetFun.selName] = evaluatedArgs[1]
      result = evaluatedArgs[1]

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

proc parseFunDef(p: var Parser): FunDef =
  discard p.expect(tkLParen) # '('
  let defTok = p.expect(tkSym) # 'define'
  if defTok.strVal != "define":
    raise newException(EvalError, "Expected 'define'")
  let fnName = p.expect(tkSym).strVal
  discard p.expect(tkLParen) # '('
  var params: seq[string] = @[]
  while p.peek().kind != tkRParen and p.peek().kind != tkEof:
    params.add(p.expect(tkSym).strVal)
  discard p.expect(tkRParen)
  let body = p.parseExp()
  discard p.expect(tkRParen)
  FunDef(name: fnName, ftype: fnNormal, params: params, body: body)

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
      if p.peek().kind == tkLParen and p.tokens.len >= 2 and p.tokens[1].kind == tkSym and p.tokens[1].strVal == "cluster":
        discard p.next() # '('
        discard p.next() # 'cluster'
        let clName = p.expect(tkSym).strVal
        discard p.expect(tkLParen)
        discard p.expect(tkSym) # 'rep'
        var repFields: seq[string] = @[]
        while p.peek().kind != tkRParen and p.peek().kind != tkEof:
          repFields.add(p.expect(tkSym).strVal)
        discard p.expect(tkRParen)

        var exportedFuns = initTable[string, FunDef]()
        while p.peek().kind == tkLParen:
          let fn = parseFunDef(p)
          exportedFuns[fn.name] = fn
          echo fn.name

        discard p.expect(tkRParen) # closing cluster ')'

        var nonexportedFuns = initTable[string, FunDef]()
        # Constructor
        nonexportedFuns[clName] = FunDef(name: clName, ftype: fnConstructor)
        # Selectors and Settors
        for f in repFields:
          nonexportedFuns[f] = FunDef(name: f, ftype: fnSelector)
          let setName = "set-" & f
          nonexportedFuns[setName] = FunDef(name: setName, ftype: fnSettor, selName: f)

        let clust = Cluster(name: clName, rep: repFields, exported: exportedFuns, nonexported: nonexportedFuns)
        clusters[clName] = clust
        echo clName
      elif p.peek().kind == tkLParen and p.tokens.len >= 2 and p.tokens[1].kind == tkSym and p.tokens[1].strVal == "define":
        let fn = parseFunDef(p)
        fundefs[fn.name] = fn
        echo fn.name
      else:
        let exp = p.parseExp()
        var localEnv = initTable[string, CluValue]()
        let val = eval(exp, localEnv, "")
        prValue(val)
        stdout.write("\n\n")
    except EvalError:
      discard

when isMainModule:
  main()
