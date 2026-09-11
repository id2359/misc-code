# lsystem_compiletime.nim
# L-Systems with compile-time expansion + turtle -> SVG
# Demonstrates pure functions with compile-time static: execution
# nim c -r lsystem_compiletime.nim

import math, strformat

type Rule* = tuple[pre: char, succ: string]

func expand*(axiom: string, rules: openArray[Rule], iters: int): string =
  # pure func -> can run at compile time with static:
  var cur = axiom
  for _ in 0..<iters:
    var nxt = ""
    for c in cur:
      var replaced = false
      for r in rules:
        if r.pre == c:
          nxt.add r.succ
          replaced = true
          break
      if not replaced:
        nxt.add c
    cur = nxt
  cur

type TurtleState* = object
  x*, y*, ang*: float64
type Segment* = tuple[x1, y1, x2, y2: float64]

proc turtle*(commands: string, step: float64, turnDeg: float64): seq[Segment] =
  var stack: seq[TurtleState]
  var state = TurtleState(x: 0.0, y: 0.0, ang: 90.0) # pointing up
  for c in commands:
    case c
    of 'F', 'G':
      let rad = degToRad(state.ang)
      let nx = state.x + step * cos(rad)
      let ny = state.y + step * sin(rad)
      result.add (state.x, state.y, nx, ny)
      state.x = nx
      state.y = ny
    of 'f':
      let rad = degToRad(state.ang)
      state.x += step * cos(rad)
      state.y += step * sin(rad)
    of '+':
      state.ang += turnDeg
    of '-':
      state.ang -= turnDeg
    of '[':
      stack.add state
    of ']':
      if stack.len > 0:
        state = stack.pop()
    else: discard

proc toSVGString*(segs: seq[Segment]): string =
  if segs.len == 0: return ""
  var minX = segs[0].x1; var maxX = minX
  var minY = segs[0].y1; var maxY = minY
  for s in segs:
    minX = min(minX, min(s.x1, s.x2))
    maxX = max(maxX, max(s.x1, s.x2))
    minY = min(minY, min(s.y1, s.y2))
    maxY = max(maxY, max(s.y1, s.y2))
  let pad = 10.0
  let w = maxX - minX + pad * 2.0
  let h = maxY - minY + pad * 2.0
  result = &"<svg xmlns='http://www.w3.org/2000/svg' width='{w:.0f}' height='{h:.0f}' viewBox='{minX-pad} {minY-pad} {w} {h}'>\n"
  result.add "<path d='"
  var hasLast = false
  var lastX, lastY: float64
  for s in segs:
    if hasLast and abs(s.x1 - lastX) < 1e-4 and abs(s.y1 - lastY) < 1e-4:
      result.add &"L {s.x2:.2f} {s.y2:.2f} "
    else:
      result.add &"M {s.x1:.2f} {s.y1:.2f} L {s.x2:.2f} {s.y2:.2f} "
    lastX = s.x2
    lastY = s.y2
    hasLast = true
  result.add "' stroke='black' fill='none' stroke-width='0.8'/>\n</svg>"

proc toSVG*(segs: seq[Segment], filename: string) =
  let svg = toSVGString(segs)
  if svg.len > 0:
    writeFile(filename, svg)
    echo &"Wrote {filename} with {segs.len} segments"

# COMPILE TIME DEMO - these strings are computed by the compiler, not at runtime
const
  kochRules = [(pre: 'F', succ: "F+F--F+F")]
  kochStr* = static: expand("F", kochRules, 4)

  dragonRules = [(pre: 'X', succ: "X+YF+"), (pre: 'Y', succ: "-FX-Y")]
  dragonStr* = static: expand("FX", dragonRules, 10)

  plantRules = [(pre: 'X', succ: "F+[[X]-X]-F[-FX]+X"), (pre: 'F', succ: "FF")]
  plantStr* = static: expand("X", plantRules, 5)

when isMainModule:
  echo &"Koch compile-time len {kochStr.len} (iters 4)"
  echo &"Dragon compile-time len {dragonStr.len}"
  echo &"Plant compile-time len {plantStr.len}"

  let kochSegs = turtle(kochStr, 5, 60)
  toSVG(kochSegs, "koch.svg")

  let dragonSegs = turtle(dragonStr, 4, 90)
  toSVG(dragonSegs, "dragon.svg")

  let plantSegs = turtle(plantStr, 4, 25)
  toSVG(plantSegs, "plant.svg")

  echo "\nWhy Nim? `static:` runs any pure proc at compile time. You can generate huge command strings before the binary even exists, then emit SVG with zero runtime cost for expansion."
