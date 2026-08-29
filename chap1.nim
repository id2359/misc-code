# Modern Idiomatic Nim: Chapter 1 Interpreter
# Based on "Programming Languages: An Interpreter-based Approach" by Samuel Kamin

import std/[tables, strutils]

type
  ExpKind = enum
    ekVal, ekVar, ekCall

  Exp = ref object
    case kind: ExpKind
    of ekVal:
      intVal: int
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
  globalEnv = initTable[string, int]()

const builtins = ["if", "while", "set", "begin", "+", "-", "*", "/", "=", "<", ">", "print"]

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
      # Number or symbol
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
    Exp(kind: ekVal, intVal: tok.intVal)
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

proc eval(e: Exp, localEnv: var Table[string, int]): int =
  case e.kind
  of ekVal:
    e.intVal
  of ekVar:
    if localEnv.hasKey(e.name):
      localEnv[e.name]
    elif globalEnv.hasKey(e.name):
      globalEnv[e.name]
    else:
      stdout.write("Undefined variable: " & e.name & "\n")
      raise newException(EvalError, "Undefined variable: " & e.name)
  of ekCall:
    case e.optr
    of "if":
      if e.args.len != 3:
        raise newException(EvalError, "Wrong number of arguments to if")
      if eval(e.args[0], localEnv) != 0:
        eval(e.args[1], localEnv)
      else:
        eval(e.args[2], localEnv)
    of "while":
      if e.args.len != 2:
        raise newException(EvalError, "Wrong number of arguments to while")
      var res = 0
      while eval(e.args[0], localEnv) != 0:
        res = eval(e.args[1], localEnv)
      res
    of "set":
      if e.args.len != 2 or e.args[0].kind != ekVar:
        raise newException(EvalError, "Invalid syntax for set")
      let val = eval(e.args[1], localEnv)
      let varName = e.args[0].name
      if localEnv.hasKey(varName):
        localEnv[varName] = val
      else:
        globalEnv[varName] = val
      val
    of "begin":
      var res = 0
      for arg in e.args:
        res = eval(arg, localEnv)
      res
    of "+", "-", "*", "/":
      if e.args.len != 2:
        stdout.write("Wrong number of arguments to " & e.optr & "\n")
        raise newException(EvalError, "Wrong number of arguments")
      let n1 = eval(e.args[0], localEnv)
      let n2 = eval(e.args[1], localEnv)
      case e.optr
      of "+": n1 + n2
      of "-": n1 - n2
      of "*": n1 * n2
      of "/":
        if n2 == 0:
          echo "Division by zero"
          raise newException(EvalError, "Division by zero")
        n1 div n2
      else: 0
    of "=", "<", ">":
      if e.args.len != 2:
        stdout.write("Wrong number of arguments to " & e.optr & "\n")
        raise newException(EvalError, "Wrong number of arguments")
      let n1 = eval(e.args[0], localEnv)
      let n2 = eval(e.args[1], localEnv)
      case e.optr
      of "=": (if n1 == n2: 1 else: 0)
      of "<": (if n1 < n2: 1 else: 0)
      of ">": (if n1 > n2: 1 else: 0)
      else: 0
    of "print":
      if e.args.len != 1:
        stdout.write("Wrong number of arguments to print\n")
        raise newException(EvalError, "Wrong number of arguments")
      let val = eval(e.args[0], localEnv)
      echo val
      val
    else:
      # User-defined function call
      if not fundefs.hasKey(e.optr):
        stdout.write("Undefined function: " & e.optr & "\n")
        raise newException(EvalError, "Undefined function: " & e.optr)
      let fn = fundefs[e.optr]
      if fn.params.len != e.args.len:
        stdout.write("Wrong number of arguments to " & e.optr & "\n")
        raise newException(EvalError, "Wrong number of arguments")
      var evaluatedArgs = newSeq[int](e.args.len)
      for i, arg in e.args:
        evaluatedArgs[i] = eval(arg, localEnv)
      var newLocalEnv = initTable[string, int]()
      for i, p in fn.params:
        newLocalEnv[p] = evaluatedArgs[i]
      eval(fn.body, newLocalEnv)

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
        var localEnv = initTable[string, int]()
        let val = eval(exp, localEnv)
        echo val
        echo ""
    except EvalError:
      discard

when isMainModule:
  main()
