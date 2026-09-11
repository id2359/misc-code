# macro_state_machine.nim
# Demonstrates Nim's AST-based macro system by building a declarative
# Finite State Machine (FSM) Domain-Specific Language (DSL).
#
# Compile and run:
#   nim c -r macro_state_machine.nim

import macros, strformat, strutils

macro stateMachine*(name: untyped, body: untyped): untyped =
  ## Generates a type-safe finite state machine with:
  ## - `<Name>State` enum (pure)
  ## - `<Name>Event` enum (pure)
  ## - `<Name>` object type tracking current state and transitions
  ## - `init<Name>()` constructor
  ## - `handle(m, event): bool` dispatch procedure
  ## - `canHandle(m, event): bool` query procedure
  ## - `toMermaid(): string` diagram generator
  result = newStmtList()

  var initialStateNode: NimNode = nil
  var states: seq[string] = @[]
  var events: seq[string] = @[]

  type TransitionDef = tuple[fromState, event, toState: string, action: NimNode]
  var transitions: seq[TransitionDef] = @[]

  for stmt in body:
    case stmt.kind
    of nnkCommand:
      if stmt[0].strVal == "initial":
        initialStateNode = stmt[1]
      else:
        error(&"Unknown directive '{stmt[0].strVal}'. Expected 'initial <State>'", stmt)
    of nnkCall:
      let fromState = stmt[0].strVal
      if fromState notin states:
        states.add fromState

      for child in stmt[1]:
        if child.kind == nnkInfix and child[0].strVal == "->":
          let onNode = child[1]
          let targetNode = child[2]
          let action = child[3]

          if onNode.kind != nnkCall or onNode[0].strVal != "on":
            error("Expected transition syntax: on(Event) -> TargetState: action", onNode)

          let eventName = onNode[1].strVal
          let targetState = targetNode.strVal

          if eventName notin events:
            events.add eventName
          if targetState notin states:
            states.add targetState

          transitions.add (fromState, eventName, targetState, action)
        else:
          error("Expected transition rule: on(Event) -> TargetState: action", child)
    else:
      error("Invalid statement in stateMachine definition", stmt)

  if initialStateNode == nil:
    error("State machine definition must declare an initial state, e.g.: initial Locked", body)

  if initialStateNode.strVal notin states:
    error(&"Initial state '{initialStateNode.strVal}' is not among defined states", initialStateNode)

  let baseName = name.strVal
  let stateEnumName = ident(baseName & "State")
  let eventEnumName = ident(baseName & "Event")
  let machineTypeName = ident(baseName)
  let initProcName = ident("init" & baseName)
  let mermaidProcName = ident(baseName.toLowerAscii() & "Diagram")

  # 1. State Enum definition
  var stateEnumDef = nnkEnumTy.newTree(newEmptyNode())
  for s in states:
    stateEnumDef.add ident(s)

  # 2. Event Enum definition
  var eventEnumDef = nnkEnumTy.newTree(newEmptyNode())
  for e in events:
    eventEnumDef.add ident(e)

  # 3. Type Section: State enum, Event enum, and Machine object
  result.add nnkTypeSection.newTree(
    nnkTypeDef.newTree(
      nnkPragmaExpr.newTree(
        nnkPostfix.newTree(ident("*"), stateEnumName),
        nnkPragma.newTree(ident("pure"))
      ),
      newEmptyNode(),
      stateEnumDef
    ),
    nnkTypeDef.newTree(
      nnkPragmaExpr.newTree(
        nnkPostfix.newTree(ident("*"), eventEnumName),
        nnkPragma.newTree(ident("pure"))
      ),
      newEmptyNode(),
      eventEnumDef
    ),
    nnkTypeDef.newTree(
      nnkPostfix.newTree(ident("*"), machineTypeName),
      newEmptyNode(),
      nnkObjectTy.newTree(
        newEmptyNode(),
        newEmptyNode(),
        nnkRecList.newTree(
          nnkIdentDefs.newTree(nnkPostfix.newTree(ident("*"), ident("state")), stateEnumName, newEmptyNode()),
          nnkIdentDefs.newTree(nnkPostfix.newTree(ident("*"), ident("transitionCount")), ident("int"), newEmptyNode())
        )
      )
    )
  )

  # 4. Constructor: init<Name>()
  let initProc = newProc(
    name = nnkPostfix.newTree(ident("*"), initProcName),
    params = [machineTypeName],
    body = newStmtList(
      nnkObjConstr.newTree(
        machineTypeName,
        nnkExprColonExpr.newTree(ident("state"), nnkDotExpr.newTree(stateEnumName, initialStateNode)),
        nnkExprColonExpr.newTree(ident("transitionCount"), newLit(0))
      )
    )
  )
  result.add initProc

  # 5. canHandle proc: checks if event is valid in current state
  var canHandleOuterCase = nnkCaseStmt.newTree(nnkDotExpr.newTree(ident("m"), ident("state")))
  for s in states:
    var innerCase = nnkCaseStmt.newTree(ident("evt"))
    var handledEvents: seq[string] = @[]
    for t in transitions:
      if t.fromState == s and t.event notin handledEvents:
        handledEvents.add t.event
        innerCase.add nnkOfBranch.newTree(
          nnkDotExpr.newTree(eventEnumName, ident(t.event)),
          newStmtList(nnkReturnStmt.newTree(ident("true")))
        )
    if handledEvents.len < events.len:
      innerCase.add nnkElse.newTree(
        newStmtList(nnkReturnStmt.newTree(ident("false")))
      )
    canHandleOuterCase.add nnkOfBranch.newTree(
      nnkDotExpr.newTree(stateEnumName, ident(s)),
      newStmtList(innerCase)
    )

  let canHandleProc = newProc(
    name = nnkPostfix.newTree(ident("*"), ident("canHandle")),
    params = [
      ident("bool"),
      nnkIdentDefs.newTree(ident("m"), machineTypeName, newEmptyNode()),
      nnkIdentDefs.newTree(ident("evt"), eventEnumName, newEmptyNode())
    ],
    body = newStmtList(canHandleOuterCase)
  )
  result.add canHandleProc

  # 6. handle proc: executes transition and associated action block
  var outerCase = nnkCaseStmt.newTree(nnkDotExpr.newTree(ident("m"), ident("state")))
  for s in states:
    var innerCase = nnkCaseStmt.newTree(ident("evt"))
    var handledEvents: seq[string] = @[]
    for t in transitions:
      if t.fromState == s and t.event notin handledEvents:
        handledEvents.add t.event
        let actionBlock = newStmtList()
        if t.action.len > 0:
          actionBlock.add t.action
        actionBlock.add nnkAsgn.newTree(
          nnkDotExpr.newTree(ident("m"), ident("state")),
          nnkDotExpr.newTree(stateEnumName, ident(t.toState))
        )
        actionBlock.add nnkCommand.newTree(ident("inc"), nnkDotExpr.newTree(ident("m"), ident("transitionCount")))
        actionBlock.add nnkReturnStmt.newTree(ident("true"))
        innerCase.add nnkOfBranch.newTree(
          nnkDotExpr.newTree(eventEnumName, ident(t.event)),
          actionBlock
        )
    if handledEvents.len < events.len:
      innerCase.add nnkElse.newTree(
        newStmtList(nnkReturnStmt.newTree(ident("false")))
      )
    outerCase.add nnkOfBranch.newTree(
      nnkDotExpr.newTree(stateEnumName, ident(s)),
      newStmtList(innerCase)
    )

  let handleProc = newProc(
    name = nnkPostfix.newTree(ident("*"), ident("handle")),
    params = [
      ident("bool"),
      nnkIdentDefs.newTree(ident("m"), nnkVarTy.newTree(machineTypeName), newEmptyNode()),
      nnkIdentDefs.newTree(ident("evt"), eventEnumName, newEmptyNode())
    ],
    body = newStmtList(outerCase)
  )
  result.add handleProc

  # 7. Diagram procedure: generates a Mermaid state diagram string
  var diagramLines: seq[string] = @["stateDiagram-v2"]
  diagramLines.add &"    [*] --> {initialStateNode.strVal}"
  for t in transitions:
    diagramLines.add &"    {t.fromState} --> {t.toState} : {t.event}"
  let diagramStr = diagramLines.join("\n")

  let diagramProc = newProc(
    name = nnkPostfix.newTree(ident("*"), mermaidProcName),
    params = [ident("string")],
    body = newStmtList(nnkReturnStmt.newTree(newLit(diagramStr)))
  )
  result.add diagramProc

# Demo: Turnstile State Machine defined using our new macro
stateMachine Turnstile:
  initial Locked
  Locked:
    on(Coin) -> Unlocked:
      echo "  [Action] Coin received! Unlocking turnstile."
    on(Push) -> Locked:
      echo "  [Action] Push attempted while locked. Turnstile resists!"
  Unlocked:
    on(Push) -> Locked:
      echo "  [Action] Patron walked through. Re-locking turnstile."
    on(Coin) -> Unlocked:
      echo "  [Action] Coin refunded! Turnstile is already unlocked."

when isMainModule:
  echo "=== Nim Macros: Declarative State Machine DSL ==="
  var turnstile = initTurnstile()
  echo &"Initial State: {turnstile.state}"

  echo "\n1. Check if Push is valid when Locked:"
  echo &"   canHandle(Push): {turnstile.canHandle(TurnstileEvent.Push)}"

  echo "\n2. Insert Coin:"
  let ok1 = turnstile.handle(TurnstileEvent.Coin)
  echo &"   Handled: {ok1}, Current State: {turnstile.state}"

  echo "\n3. Insert another Coin (refund expected):"
  let ok2 = turnstile.handle(TurnstileEvent.Coin)
  echo &"   Handled: {ok2}, Current State: {turnstile.state}"

  echo "\n4. Push through turnstile:"
  let ok3 = turnstile.handle(TurnstileEvent.Push)
  echo &"   Handled: {ok3}, Current State: {turnstile.state}"

  echo "\n5. Push again while locked:"
  let ok4 = turnstile.handle(TurnstileEvent.Push)
  echo &"   Handled: {ok4}, Current State: {turnstile.state}"

  echo &"\nTotal Successful Transitions: {turnstile.transitionCount}"

  echo "\nGenerated Mermaid State Diagram:"
  echo turnstileDiagram()
