import std/[tables, strutils, hashes]

type
  Variable = object
    name: string
    index: int

  ExpKind = enum
    ekVar, ekInt, ekAp

  Exp = ref object
    case kind: ExpKind
    of ekVar:
      v: Variable
    of ekInt:
      intVal: int
    of ekAp:
      optr: string
      args: seq[Exp]

  Goal = ref object
    pred: string
    args: seq[Exp]

  Clause = ref object
    lhs: Goal
    rhs: seq[Goal]

  Subst = ref object
    bindings: Table[Variable, Exp]

  EvalError = object of CatchableError

var
  clauses: seq[Clause] = @[]
  quittingtime = false

proc `==`(v1, v2: Variable): bool =
  v1.name == v2.name and v1.index == v2.index

proc hash(v: Variable): int =
  hash(v.name) !& hash(v.index)

proc prExp(e: Exp) =
  case e.kind
  of ekInt:
    stdout.write($e.intVal)
  of ekVar:
    stdout.write(e.v.name)
    if e.v.index > 0:
      stdout.write($e.v.index)
  of ekAp:
    if e.args.len == 0:
      stdout.write(e.optr)
    else:
      stdout.write("(")
      stdout.write(e.optr)
      for arg in e.args:
        stdout.write(" ")
        prExp(arg)
      stdout.write(")")

proc prExplist(el: seq[Exp]) =
  for i, e in el:
    if i > 0: stdout.write(" ")
    prExp(e)

# --- Substitutions ---

proc applySubst(s: Subst, e: Exp): Exp

proc applySubst(s: Subst, e: Exp): Exp =
  if s == nil or s.bindings.len == 0: return e
  case e.kind
  of ekInt:
    e
  of ekVar:
    if s.bindings.hasKey(e.v):
      applySubst(s, s.bindings[e.v])
    else:
      e
  of ekAp:
    var newArgs = newSeq[Exp](e.args.len)
    for i, a in e.args:
      newArgs[i] = applySubst(s, a)
    Exp(kind: ekAp, optr: e.optr, args: newArgs)

proc applySubst(s: Subst, g: Goal): Goal =
  var newArgs = newSeq[Exp](g.args.len)
  for i, a in g.args:
    newArgs[i] = applySubst(s, a)
  Goal(pred: g.pred, args: newArgs)

proc compose(s1: var Subst, s2: Subst) =
  if s2 == nil: return
  if s1 == nil:
    s1 = Subst(bindings: initTable[Variable, Exp]())
  for v, e in s1.bindings:
    s1.bindings[v] = applySubst(s2, e)
  for v, e in s2.bindings:
    if not s1.bindings.hasKey(v):
      s1.bindings[v] = e

# --- Unification ---

proc occursInExp(v: Variable, e: Exp): bool =
  case e.kind
  of ekInt: false
  of ekVar: e.v == v
  of ekAp:
    for arg in e.args:
      if occursInExp(v, arg): return true
    false

proc findELDiff(el1, el2: seq[Exp], diff1, diff2: var Exp): bool

proc findExpDiff(e1, e2: Exp, diff1, diff2: var Exp): bool =
  diff1 = e1
  diff2 = e2
  if e1.kind == e2.kind:
    case e1.kind
    of ekVar:
      return not (e1.v == e2.v)
    of ekInt:
      return not (e1.intVal == e2.intVal)
    of ekAp:
      if e1.optr == e2.optr:
        return findELDiff(e1.args, e2.args, diff1, diff2)
      else:
        return true
  true

proc findELDiff(el1, el2: seq[Exp], diff1, diff2: var Exp): bool =
  if el1.len != el2.len: return true
  for i in 0 ..< el1.len:
    if findExpDiff(el1[i], el2[i], diff1, diff2):
      return true
  false

proc unify(g1In, g2In: Goal): Subst =
  if g1In.pred != g2In.pred or g1In.args.len != g2In.args.len:
    return nil
  var g1 = Goal(pred: g1In.pred, args: g1In.args)
  var g2 = Goal(pred: g2In.pred, args: g2In.args)
  var sigma = Subst(bindings: initTable[Variable, Exp]())

  while true:
    var diff1, diff2: Exp
    let foundDiff = findELDiff(g1.args, g2.args, diff1, diff2)
    if not foundDiff:
      return sigma
    var varSubst: Subst = nil
    if diff1.kind == ekVar:
      if not occursInExp(diff1.v, diff2):
        varSubst = Subst(bindings: {diff1.v: diff2}.toTable)
    elif diff2.kind == ekVar:
      if not occursInExp(diff2.v, diff1):
        varSubst = Subst(bindings: {diff2.v: diff1}.toTable)

    if varSubst == nil:
      return nil

    g1 = applySubst(varSubst, g1)
    g2 = applySubst(varSubst, g2)
    compose(sigma, varSubst)

# --- Lexer & Parser ---

type
  TokenKind = enum
    tkLParen, tkRParen, tkInt, tkSym, tkEof

  Token = object
    kind: TokenKind
    strVal: string
    intVal: int

  Scanner = object
    input: string
    pos: int

proc isDelim(c: char): bool =
  c in {'(', ')', ' ', ';', '\t', '\r', '\n'}

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

proc isVarName(name: string): bool =
  name.len > 0 and name[0] in {'A'..'Z'}

proc parseExp(p: var Parser): Exp =
  let tok = p.peek()
  case tok.kind
  of tkInt:
    discard p.next()
    Exp(kind: ekInt, intVal: tok.intVal)
  of tkSym:
    discard p.next()
    if isVarName(tok.strVal):
      Exp(kind: ekVar, v: Variable(name: tok.strVal, index: 0))
    else:
      Exp(kind: ekAp, optr: tok.strVal, args: @[])
  of tkLParen:
    discard p.next()
    let optr = p.expect(tkSym).strVal
    var args: seq[Exp] = @[]
    while p.peek().kind != tkRParen and p.peek().kind != tkEof:
      args.add(p.parseExp())
    discard p.expect(tkRParen)
    Exp(kind: ekAp, optr: optr, args: args)
  else:
    raise newException(EvalError, "Unexpected token: " & tok.strVal)

proc parseGoal(p: var Parser): Goal =
  if p.peek().kind == tkLParen:
    discard p.next()
    let pred = p.expect(tkSym).strVal
    var args: seq[Exp] = @[]
    while p.peek().kind != tkRParen and p.peek().kind != tkEof:
      args.add(p.parseExp())
    discard p.expect(tkRParen)
    Goal(pred: pred, args: args)
  else:
    let pred = p.expect(tkSym).strVal
    Goal(pred: pred, args: @[])

proc parseGoalList(p: var Parser): seq[Goal] =
  var goals: seq[Goal] = @[]
  while p.peek().kind != tkRParen and p.peek().kind != tkEof:
    goals.add(p.parseGoal())
  goals

# --- Evaluator ---

proc copyExp(e: Exp, id: int): Exp =
  case e.kind
  of ekInt:
    e
  of ekVar:
    Exp(kind: ekVar, v: Variable(name: e.v.name, index: if id == 0: e.v.index else: id))
  of ekAp:
    var newArgs = newSeq[Exp](e.args.len)
    for i, a in e.args:
      newArgs[i] = copyExp(a, id)
    Exp(kind: ekAp, optr: e.optr, args: newArgs)

proc copyGoal(g: Goal, id: int): Goal =
  var newArgs = newSeq[Exp](g.args.len)
  for i, a in g.args:
    newArgs[i] = copyExp(a, id)
  Goal(pred: g.pred, args: newArgs)

proc copyGoalList(gl: seq[Goal], id: int): seq[Goal] =
  result = newSeq[Goal](gl.len)
  for i, g in gl:
    result[i] = copyGoal(g, id)

proc isPrimPred(name: string): bool =
  name in ["plus", "minus", "less", "print"]

proc applyPrim(g: Goal, sigma: var Subst): bool =
  sigma = Subst(bindings: initTable[Variable, Exp]())
  if g.pred == "print":
    prExplist(g.args)
    stdout.write("\n")
    return true

  if g.args.len < 2: return false
  let a1 = g.args[0]
  let a2 = g.args[1]
  if a1.kind != ekInt or a2.kind != ekInt:
    return false

  case g.pred
  of "plus", "minus":
    if g.args.len != 3: return false
    let a3 = g.args[2]
    if a3.kind == ekAp: return false
    let res = if g.pred == "plus": a1.intVal + a2.intVal else: a1.intVal - a2.intVal
    if a3.kind == ekInt:
      return a3.intVal == res
    elif a3.kind == ekVar:
      sigma.bindings[a3.v] = Exp(kind: ekInt, intVal: res)
      return true
    else:
      return false
  of "less":
    if g.args.len != 2: return false
    return a1.intVal < a2.intVal
  else:
    return false

proc prove(gl: seq[Goal], id: int): Subst =
  if gl.len == 0:
    return Subst(bindings: initTable[Variable, Exp]())

  let head = gl[0]
  let tail = gl[1..^1]

  if isPrimPred(head.pred):
    var sigma0: Subst
    if applyPrim(head, sigma0):
      var newTail = newSeq[Goal](tail.len)
      for i, g in tail:
        newTail[i] = applySubst(sigma0, g)
      let sigma1 = prove(newTail, id + 1)
      if sigma1 != nil:
        compose(sigma0, sigma1)
        return sigma0
    return nil
  else:
    for cl in clauses:
      let clHead = copyGoal(cl.lhs, id)
      let sigma0 = unify(clHead, head)
      if sigma0 != nil:
        let clBody = copyGoalList(cl.rhs, id)
        var newGoals = newSeq[Goal](clBody.len + tail.len)
        for i, g in clBody:
          newGoals[i] = applySubst(sigma0, g)
        for i, g in tail:
          newGoals[clBody.len + i] = applySubst(sigma0, g)

        let sigma1 = prove(newGoals, id + 1)
        if sigma1 != nil:
          var res = sigma0
          compose(res, sigma1)
          return res
    return nil

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
      if p.peek().kind == tkLParen and p.tokens.len >= 2 and p.tokens[1].kind == tkSym and p.tokens[1].strVal == "infer":
        discard p.next() # '('
        discard p.next() # 'infer'
        let head = p.parseGoal()
        var body: seq[Goal] = @[]
        if p.peek().kind == tkSym and p.peek().strVal == "from":
          discard p.next() # 'from'
          body = p.parseGoalList()
        discard p.expect(tkRParen)
        clauses.add(Clause(lhs: head, rhs: body))
        stdout.write("\n")
      elif p.peek().kind == tkLParen and p.tokens.len >= 2 and p.tokens[1].kind == tkSym and p.tokens[1].strVal == "infer?":
        discard p.next() # '('
        discard p.next() # 'infer?'
        let queryGoals = p.parseGoalList()
        discard p.expect(tkRParen)
        stdout.write("\n")
        let subst = prove(queryGoals, 1)
        if subst == nil:
          stdout.write("Not satisfied\n\n")
        else:
          stdout.write("Satisfied\n\n")
    except EvalError:
      discard

when isMainModule:
  main()
