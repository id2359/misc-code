# Modern Idiomatic Nim: Chapter 7 Smalltalk Interpreter
# Based on "Programming Languages: An Interpreter-based Approach" by Samuel Kamin

import std/[tables, strutils]

type
  Class = ref object
    name: string
    superClass: Class
    rep: seq[string]
    methods: Table[string, FunDef]

  StValueKind = enum
    vkInt, vkSym, vkUser

  StValue = ref object
    owner: Class
    case kind: StValueKind
    of vkInt:
      intVal: int
    of vkSym:
      symVal: string
    of vkUser:
      ivars: Table[string, StValue]

  ExpKind = enum
    ekVal, ekVar, ekCall

  Exp = ref object
    case kind: ExpKind
    of ekVal:
      val: StValue
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
  classes = initTable[string, Class]()
  fundefs = initTable[string, FunDef]()
  globalEnv = initTable[string, StValue]()
  objectClass: Class

proc prValue(v: StValue) =
  case v.kind
  of vkInt:
    stdout.write($v.intVal)
  of vkSym:
    stdout.write(v.symVal)
  of vkUser:
    stdout.write("<userval>")

proc isTrue(v: StValue): bool =
  case v.kind
  of vkInt: v.intVal != 0
  of vkSym, vkUser: true

# --- Lexer & Parser ---

type
  TokenKind = enum
    tkLParen, tkRParen, tkHash, tkInt, tkSym, tkSymLit, tkEof

  Token = object
    kind: TokenKind
    strVal: string
    intVal: int

  Scanner = object
    input: string
    pos: int

proc isDelim(c: char): bool =
  c in {'(', ')', '#', ' ', ';', '\t', '\r', '\n'}

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
    elif c == '#':
      inc s.pos
      let start = s.pos
      while s.pos < s.input.len and not isDelim(s.input[s.pos]):
        inc s.pos
      return Token(kind: tkSymLit, strVal: s.input[start ..< s.pos])
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
  of tkSymLit:
    discard p.next()
    Exp(kind: ekVal, val: StValue(kind: vkSym, symVal: tok.strVal, owner: nil))
  of tkInt:
    discard p.next()
    Exp(kind: ekVal, val: StValue(kind: vkInt, intVal: tok.intVal, owner: nil))
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

# --- Evaluator ---

proc eval(e: Exp, localEnv: var Table[string, StValue], rcvr: StValue): StValue

proc methodSearch(optr: string, cl: Class): FunDef =
  var cur = cl
  while cur != nil:
    if cur.methods.hasKey(optr):
      return cur.methods[optr]
    cur = cur.superClass
  nil

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

proc eval(e: Exp, localEnv: var Table[string, StValue], rcvr: StValue): StValue =
  case e.kind
  of ekVal:
    result = e.val
  of ekVar:
    if localEnv.hasKey(e.name):
      result = localEnv[e.name]
    elif rcvr != nil and rcvr.kind == vkUser and rcvr.ivars.hasKey(e.name):
      result = rcvr.ivars[e.name]
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
      if isTrue(eval(e.args[0], localEnv, rcvr)):
        return eval(e.args[1], localEnv, rcvr)
      else:
        return eval(e.args[2], localEnv, rcvr)
    of "while":
      if e.args.len != 2:
        raise newException(EvalError, "Wrong number of arguments to while")
      var cond = eval(e.args[0], localEnv, rcvr)
      while isTrue(cond):
        discard eval(e.args[1], localEnv, rcvr)
        cond = eval(e.args[0], localEnv, rcvr)
      return cond
    of "set":
      if e.args.len != 2 or e.args[0].kind != ekVar:
        raise newException(EvalError, "Invalid syntax for set")
      let val = eval(e.args[1], localEnv, rcvr)
      let varName = e.args[0].name
      if localEnv.hasKey(varName):
        localEnv[varName] = val
      elif rcvr != nil and rcvr.kind == vkUser and rcvr.ivars.hasKey(varName):
        rcvr.ivars[varName] = val
      else:
        globalEnv[varName] = val
      return val
    of "begin":
      var res = StValue(kind: vkInt, intVal: 0, owner: nil)
      for arg in e.args:
        res = eval(arg, localEnv, rcvr)
      return res
    of "new":
      if e.args.len != 1 or e.args[0].kind != ekVar:
        raise newException(EvalError, "Invalid syntax for new")
      let className = e.args[0].name
      if not classes.hasKey(className):
        stdout.write("Undefined class: " & className & "\n")
        raise newException(EvalError, "Undefined class: " & className)
      let cl = classes[className]
      var ivars = initTable[string, StValue]()
      for f in cl.rep:
        ivars[f] = StValue(kind: vkInt, intVal: 0, owner: nil)
      let newObj = StValue(kind: vkUser, owner: cl, ivars: ivars)
      newObj.ivars["self"] = newObj
      return newObj
    else:
      # General function / method call
      var evaluatedArgs = newSeq[StValue](e.args.len)
      for i, arg in e.args:
        evaluatedArgs[i] = eval(arg, localEnv, rcvr)

      if evaluatedArgs.len > 0 and evaluatedArgs[0].owner != nil:
        let m = methodSearch(e.optr, evaluatedArgs[0].owner)
        if m != nil:
          if m.params.len != evaluatedArgs.len - 1:
            stdout.write("Wrong number of arguments to: " & m.name & "\n")
            raise newException(EvalError, "Wrong number of arguments")
          var methodLocalEnv = initTable[string, StValue]()
          for i, p in m.params:
            methodLocalEnv[p] = evaluatedArgs[i + 1]
          return eval(m.body, methodLocalEnv, evaluatedArgs[0])

      # Built-in value operations
      case e.optr
      of "+", "-", "*", "/":
        if evaluatedArgs.len != 2:
          stdout.write("Wrong number of arguments to " & e.optr & "\n")
          raise newException(EvalError, "Wrong number of arguments")
        if evaluatedArgs[0].kind != vkInt or evaluatedArgs[1].kind != vkInt:
          stdout.write("Non-arithmetic arguments to " & e.optr & "\n")
          raise newException(EvalError, "Non-arithmetic arguments")
        return StValue(kind: vkInt, intVal: applyOp(e.optr, evaluatedArgs[0].intVal, evaluatedArgs[1].intVal), owner: nil)
      of "<", ">":
        if evaluatedArgs.len != 2:
          stdout.write("Wrong number of arguments to " & e.optr & "\n")
          raise newException(EvalError, "Wrong number of arguments")
        if evaluatedArgs[0].kind != vkInt or evaluatedArgs[1].kind != vkInt:
          stdout.write("Non-arithmetic arguments to " & e.optr & "\n")
          raise newException(EvalError, "Non-arithmetic arguments")
        let cond = if e.optr == "<": evaluatedArgs[0].intVal < evaluatedArgs[1].intVal else: evaluatedArgs[0].intVal > evaluatedArgs[1].intVal
        return StValue(kind: vkInt, intVal: (if cond: 1 else: 0), owner: nil)
      of "=":
        if evaluatedArgs.len != 2:
          stdout.write("Wrong number of arguments to =\n")
          raise newException(EvalError, "Wrong number of arguments")
        var eq = false
        if evaluatedArgs[0].kind == evaluatedArgs[1].kind:
          if evaluatedArgs[0].kind == vkInt and evaluatedArgs[0].intVal == evaluatedArgs[1].intVal:
            eq = true
          elif evaluatedArgs[0].kind == vkSym and evaluatedArgs[0].symVal == evaluatedArgs[1].symVal:
            eq = true
        return StValue(kind: vkInt, intVal: (if eq: 1 else: 0), owner: nil)
      of "print":
        if evaluatedArgs.len != 1:
          stdout.write("Wrong number of arguments to print\n")
          raise newException(EvalError, "Wrong number of arguments")
        prValue(evaluatedArgs[0])
        stdout.write("\n")
        return evaluatedArgs[0]
      else:
        # Global function
        if fundefs.hasKey(e.optr):
          let fn = fundefs[e.optr]
          if fn.params.len != evaluatedArgs.len:
            stdout.write("Wrong number of arguments to: " & fn.name & "\n")
            raise newException(EvalError, "Wrong number of arguments")
          var newLocalEnv = initTable[string, StValue]()
          for i, p in fn.params:
            newLocalEnv[p] = evaluatedArgs[i]
          return eval(fn.body, newLocalEnv, rcvr)
        else:
          stdout.write("Undefined function: " & e.optr & "\n")
          raise newException(EvalError, "Undefined function: " & e.optr)

# --- REPL ---

proc initHierarchy() =
  objectClass = Class(name: "Object", superClass: nil, rep: @["self"], methods: initTable[string, FunDef]())
  classes["Object"] = objectClass

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
  FunDef(name: fnName, params: params, body: body)

proc main() =
  initHierarchy()
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
      if p.peek().kind == tkLParen and p.tokens.len >= 2 and p.tokens[1].kind == tkSym and p.tokens[1].strVal == "class":
        discard p.next() # '('
        discard p.next() # 'class'
        let clName = p.expect(tkSym).strVal
        let superName = p.expect(tkSym).strVal
        if not classes.hasKey(superName):
          stdout.write("Undefined superclass: " & superName & "\n")
          raise newException(EvalError, "Undefined superclass")
        let superCl = classes[superName]

        discard p.expect(tkLParen)
        var repFields: seq[string] = @[]
        while p.peek().kind != tkRParen and p.peek().kind != tkEof:
          repFields.add(p.expect(tkSym).strVal)
        discard p.expect(tkRParen)

        # Full rep is subclass rep followed by superclass rep
        for f in superCl.rep:
          if f notin repFields:
            repFields.add(f)

        var methods = initTable[string, FunDef]()
        while p.peek().kind == tkLParen:
          let m = parseFunDef(p)
          methods[m.name] = m
          echo m.name

        discard p.expect(tkRParen) # closing class ')'

        let newCl = Class(name: clName, superClass: superCl, rep: repFields, methods: methods)
        classes[clName] = newCl
        echo clName
      elif p.peek().kind == tkLParen and p.tokens.len >= 2 and p.tokens[1].kind == tkSym and p.tokens[1].strVal == "define":
        let fn = parseFunDef(p)
        fundefs[fn.name] = fn
        echo fn.name
      else:
        let exp = p.parseExp()
        var localEnv = initTable[string, StValue]()
        let val = eval(exp, localEnv, nil)
        prValue(val)
        stdout.write("\n\n")
    except EvalError:
      discard

when isMainModule:
  main()
