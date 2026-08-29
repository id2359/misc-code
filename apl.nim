# Modern Idiomatic Nim: Chapter 3 APL Interpreter
# Based on "Programming Languages: An Interpreter-based Approach" by Samuel Kamin

import std/[tables, strutils]

type
  Rank = enum
    rkScalar, rkVector, rkMatrix

  AplValue = ref object
    case rank: Rank
    of rkScalar:
      scalarVal: int
    of rkVector:
      vecVals: seq[int]
    of rkMatrix:
      rows, cols: int
      matVals: seq[int]

  ExpKind = enum
    ekVal, ekVar, ekCall

  Exp = ref object
    case kind: ExpKind
    of ekVal:
      val: AplValue
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
  globalEnv = initTable[string, AplValue]()

proc elements(a: AplValue): seq[int] =
  case a.rank
  of rkScalar: @[a.scalarVal]
  of rkVector: a.vecVals
  of rkMatrix: a.matVals

proc size(a: AplValue): int =
  case a.rank
  of rkScalar: 1
  of rkVector: a.vecVals.len
  of rkMatrix: a.rows * a.cols

proc isTrueVal(a: AplValue): bool =
  let elems = a.elements
  if elems.len == 0: false else: elems[0] == 1

proc prValue(a: AplValue) =
  case a.rank
  of rkScalar:
    stdout.write(align($a.scalarVal, 6) & " \n")
  of rkVector:
    for v in a.vecVals:
      stdout.write(align($v, 6) & " ")
    stdout.write("\n")
  of rkMatrix:
    for r in 0 ..< a.rows:
      for c in 0 ..< a.cols:
        stdout.write(align($a.matVals[r * a.cols + c], 6) & " ")
      stdout.write("\n")

proc ncopy(src: seq[int], count: int): seq[int] =
  if count == 0 or src.len == 0:
    return @[]
  result = newSeq[int](count)
  for i in 0 ..< count:
    result[i] = src[i mod src.len]

proc applyOp(op: string, i, j: int): int =
  case op
  of "+", "+/": i + j
  of "-", "-/": i - j
  of "*", "*/": i * j
  of "/", "//":
    if j == 0:
      echo "Division by zero"
      raise newException(EvalError, "Division by zero")
    i div j
  of "max", "max/":
    if i > j: i else: j
  of "or", "or/":
    if i == 1 or j == 1: 1 else: 0
  of "and", "and/":
    if i == 1 and j == 1: 1 else: 0
  of "=": (if i == j: 1 else: 0)
  of "<": (if i < j: 1 else: 0)
  of ">": (if i > j: 1 else: 0)
  else: 0

proc applyArithOp(op: string, a1, a2: AplValue): AplValue =
  var templateObj: AplValue
  if a1.rank == rkScalar:
    templateObj = a2
  elif a2.rank == rkScalar:
    templateObj = a1
  elif a1.size == 1:
    templateObj = a2
  else:
    templateObj = a1

  let s1 = a1.size
  let s2 = a2.size
  let e1 = a1.elements
  let e2 = a2.elements

  var resVals: seq[int] = @[]
  if s1 > 0 and s2 > 0:
    let resSize = if s1 == 1: s2 elif s2 == 1: s1 else: min(s1, s2)
    resVals = newSeq[int](resSize)
    for i in 0 ..< resSize:
      let v1 = if s1 == 1: e1[0] else: e1[i]
      let v2 = if s2 == 1: e2[0] else: e2[i]
      resVals[i] = applyOp(op, v1, v2)

  case templateObj.rank
  of rkScalar:
    if resVals.len > 0:
      AplValue(rank: rkScalar, scalarVal: resVals[0])
    else:
      AplValue(rank: rkScalar, scalarVal: 0)
  of rkVector:
    AplValue(rank: rkVector, vecVals: resVals)
  of rkMatrix:
    AplValue(rank: rkMatrix, rows: templateObj.rows, cols: templateObj.cols, matVals: resVals)

proc redVec(op: string, vec: seq[int]): int =
  if vec.len == 0: 0
  elif vec.len == 1: vec[0]
  else:
    # Right-associative fold
    var res = vec[^1]
    for i in countdown(vec.len - 2, 0):
      res = applyOp(op, vec[i], res)
    res

proc applyRedOp(op: string, a: AplValue): AplValue =
  case a.rank
  of rkScalar:
    a
  of rkVector:
    let v = redVec(op, a.vecVals)
    AplValue(rank: rkScalar, scalarVal: v)
  of rkMatrix:
    var rowResults = newSeq[int](a.rows)
    for r in 0 ..< a.rows:
      let rowSlice = a.matVals[r * a.cols ..< (r + 1) * a.cols]
      rowResults[r] = redVec(op, rowSlice)
    AplValue(rank: rkVector, vecVals: rowResults)

proc compress(a1, a2: AplValue): AplValue =
  let mask = a1.elements
  if a2.rank == rkVector:
    var res: seq[int] = @[]
    for i in 0 ..< min(mask.len, a2.vecVals.len):
      if mask[i] == 1:
        res.add(a2.vecVals[i])
    AplValue(rank: rkVector, vecVals: res)
  else:
    var resMat: seq[int] = @[]
    var selectedRows = 0
    for i in 0 ..< min(mask.len, a2.rows):
      if mask[i] == 1:
        inc selectedRows
        for c in 0 ..< a2.cols:
          resMat.add(a2.matVals[i * a2.cols + c])
    AplValue(rank: rkMatrix, rows: selectedRows, cols: a2.cols, matVals: resMat)

proc shape(a: AplValue): AplValue =
  case a.rank
  of rkScalar:
    AplValue(rank: rkVector, vecVals: @[])
  of rkVector:
    AplValue(rank: rkVector, vecVals: @[a.vecVals.len])
  of rkMatrix:
    AplValue(rank: rkVector, vecVals: @[a.rows, a.cols])

proc ravel(a: AplValue): AplValue =
  AplValue(rank: rkVector, vecVals: a.elements)

proc restruct(shapevec, valvec: AplValue): AplValue =
  let valElems = valvec.elements
  if valElems.len == 0:
    echo "Cannot restructure null vector"
    raise newException(EvalError, "Cannot restructure null vector")

  let sElems = shapevec.elements
  if shapevec.rank == rkScalar:
    let dim1 = shapevec.scalarVal
    let vals = ncopy(valElems, dim1)
    AplValue(rank: rkVector, vecVals: vals)
  elif sElems.len == 0:
    let vals = ncopy(valElems, 1)
    AplValue(rank: rkScalar, scalarVal: vals[0])
  elif sElems.len == 1:
    let dim1 = sElems[0]
    let vals = ncopy(valElems, dim1)
    AplValue(rank: rkVector, vecVals: vals)
  else:
    let dim1 = sElems[0]
    let dim2 = sElems[1]
    let vals = ncopy(valElems, dim1 * dim2)
    AplValue(rank: rkMatrix, rows: dim1, cols: dim2, matVals: vals)

proc cat(a1, a2: AplValue): AplValue =
  var res = a1.elements
  res.add(a2.elements)
  AplValue(rank: rkVector, vecVals: res)

proc indx(a: AplValue): AplValue =
  let n = a.elements[0]
  var res = newSeq[int](n)
  for i in 1 .. n:
    res[i - 1] = i
  AplValue(rank: rkVector, vecVals: res)

proc trans(a: AplValue): AplValue =
  if a.rank != rkMatrix:
    a
  else:
    let newRows = a.cols
    let newCols = a.rows
    var res = newSeq[int](newRows * newCols)
    for r in 0 ..< a.rows:
      for c in 0 ..< a.cols:
        res[c * newCols + r] = a.matVals[r * a.cols + c]
    AplValue(rank: rkMatrix, rows: newRows, cols: newCols, matVals: res)

proc subscript(a1, a2: AplValue): AplValue =
  let subs = a2.elements
  if a1.rank == rkVector:
    var res: seq[int] = @[]
    for idx in subs:
      if idx >= 1 and idx <= a1.vecVals.len:
        res.add(a1.vecVals[idx - 1])
    AplValue(rank: rkVector, vecVals: res)
  else:
    var res: seq[int] = @[]
    for idx in subs:
      if idx >= 1 and idx <= a1.rows:
        for c in 0 ..< a1.cols:
          res.add(a1.matVals[(idx - 1) * a1.cols + c])
    let outRows = if a2.rank == rkScalar: 1 else: a2.size
    AplValue(rank: rkMatrix, rows: outRows, cols: a1.cols, matVals: res)

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

proc parseVal(p: var Parser): AplValue =
  let tok = p.peek()
  case tok.kind
  of tkInt:
    discard p.next()
    AplValue(rank: rkScalar, scalarVal: tok.intVal)
  of tkLParen:
    discard p.next()
    var items: seq[int] = @[]
    while p.peek().kind != tkRParen and p.peek().kind != tkEof:
      let t = p.next()
      if t.kind != tkInt:
        raise newException(EvalError, "Expected integer in array constant")
      items.add(t.intVal)
    discard p.expect(tkRParen)
    AplValue(rank: rkVector, vecVals: items)
  else:
    raise newException(EvalError, "Unexpected token in value: " & tok.strVal)

proc parseExp(p: var Parser): Exp =
  let tok = p.peek()
  case tok.kind
  of tkQuote:
    discard p.next()
    Exp(kind: ekVal, val: p.parseVal())
  of tkInt:
    discard p.next()
    Exp(kind: ekVal, val: AplValue(rank: rkScalar, scalarVal: tok.intVal))
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

proc eval(e: Exp, localEnv: var Table[string, AplValue]): AplValue =
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
    case e.optr
    of "if":
      if e.args.len != 3:
        raise newException(EvalError, "Wrong number of arguments to if")
      if isTrueVal(eval(e.args[0], localEnv)):
        result = eval(e.args[1], localEnv)
      else:
        result = eval(e.args[2], localEnv)
    of "while":
      if e.args.len != 2:
        raise newException(EvalError, "Wrong number of arguments to while")
      var res = AplValue(rank: rkScalar, scalarVal: 0)
      while isTrueVal(eval(e.args[0], localEnv)):
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
      var res = AplValue(rank: rkScalar, scalarVal: 0)
      for arg in e.args:
        res = eval(arg, localEnv)
      result = res
    of "+", "-", "*", "/", "max", "or", "and", "=", "<", ">":
      if e.args.len != 2:
        stdout.write("Wrong number of arguments to " & e.optr & "\n")
        raise newException(EvalError, "Wrong number of arguments")
      let a1 = eval(e.args[0], localEnv)
      let a2 = eval(e.args[1], localEnv)
      result = applyArithOp(e.optr, a1, a2)
    of "+/", "-/", "*/", "//", "max/", "or/", "and/":
      if e.args.len != 1:
        stdout.write("Wrong number of arguments to " & e.optr & "\n")
        raise newException(EvalError, "Wrong number of arguments")
      let a = eval(e.args[0], localEnv)
      result = applyRedOp(e.optr, a)
    of "compress":
      if e.args.len != 2:
        stdout.write("Wrong number of arguments to compress\n")
        raise newException(EvalError, "Wrong number of arguments")
      let a1 = eval(e.args[0], localEnv)
      let a2 = eval(e.args[1], localEnv)
      result = compress(a1, a2)
    of "shape":
      if e.args.len != 1:
        stdout.write("Wrong number of arguments to shape\n")
        raise newException(EvalError, "Wrong number of arguments")
      result = shape(eval(e.args[0], localEnv))
    of "ravel":
      if e.args.len != 1:
        stdout.write("Wrong number of arguments to ravel\n")
        raise newException(EvalError, "Wrong number of arguments")
      result = ravel(eval(e.args[0], localEnv))
    of "restruct":
      if e.args.len != 2:
        stdout.write("Wrong number of arguments to restruct\n")
        raise newException(EvalError, "Wrong number of arguments")
      let a1 = eval(e.args[0], localEnv)
      let a2 = eval(e.args[1], localEnv)
      result = restruct(a1, a2)
    of "cat":
      if e.args.len != 2:
        stdout.write("Wrong number of arguments to cat\n")
        raise newException(EvalError, "Wrong number of arguments")
      let a1 = eval(e.args[0], localEnv)
      let a2 = eval(e.args[1], localEnv)
      result = cat(a1, a2)
    of "indx":
      if e.args.len != 1:
        stdout.write("Wrong number of arguments to indx\n")
        raise newException(EvalError, "Wrong number of arguments")
      result = indx(eval(e.args[0], localEnv))
    of "trans":
      if e.args.len != 1:
        stdout.write("Wrong number of arguments to trans\n")
        raise newException(EvalError, "Wrong number of arguments")
      result = trans(eval(e.args[0], localEnv))
    of "[]":
      if e.args.len != 2:
        stdout.write("Wrong number of arguments to []\n")
        raise newException(EvalError, "Wrong number of arguments")
      let a1 = eval(e.args[0], localEnv)
      let a2 = eval(e.args[1], localEnv)
      result = subscript(a1, a2)
    of "print":
      if e.args.len != 1:
        stdout.write("Wrong number of arguments to print\n")
        raise newException(EvalError, "Wrong number of arguments")
      let val = eval(e.args[0], localEnv)
      prValue(val)
      result = val
    else:
      # User-defined function call
      if not fundefs.hasKey(e.optr):
        stdout.write("Undefined function: " & e.optr & "\n")
        raise newException(EvalError, "Undefined function: " & e.optr)
      let fn = fundefs[e.optr]
      if fn.params.len != e.args.len:
        stdout.write("Wrong number of arguments to " & e.optr & "\n")
        raise newException(EvalError, "Wrong number of arguments")
      var evaluatedArgs = newSeq[AplValue](e.args.len)
      for i, arg in e.args:
        evaluatedArgs[i] = eval(arg, localEnv)
      var newLocalEnv = initTable[string, AplValue]()
      for i, p in fn.params:
        newLocalEnv[p] = evaluatedArgs[i]
      result = eval(fn.body, newLocalEnv)

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
        var localEnv = initTable[string, AplValue]()
        let val = eval(exp, localEnv)
        prValue(val)
        stdout.write("\n\n")
    except EvalError:
      discard

when isMainModule:
  main()
