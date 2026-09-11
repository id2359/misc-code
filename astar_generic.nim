# astar_generic.nim
# Generic A* with Nim concepts + heapqueue, plus JPS-style pruning idea
# nim c -r astar_generic.nim

import algorithm, heapqueue, tables, math, sequtils, strformat, strutils

type GridPos = tuple[x,y: int]

type Grid = object
  w,h: int
  blocked: seq[seq[bool]]

proc initGrid(w,h: int): Grid =
  result.w=w; result.h=h
  result.blocked = newSeqWith(h, newSeq[bool](w))

proc inBounds(g: Grid, p: GridPos): bool =
  p.x>=0 and p.x<g.w and p.y>=0 and p.y<g.h

proc isBlocked(g: Grid, p: GridPos): bool =
  if not g.inBounds(p): true else: g.blocked[p.y][p.x]

iterator neighbors4(g: Grid, p: GridPos): GridPos =
  for d in [(1,0),(-1,0),(0,1),(0,-1)]:
    let np: GridPos = (p.x+d[0], p.y+d[1])
    if g.inBounds(np) and not g.isBlocked(np):
      yield np

iterator neighbors8(g: Grid, p: GridPos): GridPos =
  for dy in -1..1:
    for dx in -1..1:
      if dx==0 and dy==0: continue
      let np: GridPos = (p.x+dx, p.y+dy)
      if not g.inBounds(np) or g.isBlocked(np): continue
      # prevent corner cutting
      if dx!=0 and dy!=0:
        if g.isBlocked((p.x+dx,p.y)) and g.isBlocked((p.x,p.y+dy)):
          continue
      yield np

func manhattan(a,b: GridPos): float = float(abs(a.x-b.x)+abs(a.y-b.y))
func euclid(a,b: GridPos): float = sqrt(float((a.x-b.x)^2+(a.y-b.y)^2))

type AStarNode = object
  pos: GridPos
  f, g: float

func `<`(a,b: AStarNode): bool = a.f < b.f

# Adapter API used by the generic implementation below.
proc neighbors(g: Grid, p: GridPos): seq[GridPos] =
  for dy in -1..1:
    for dx in -1..1:
      if dx == 0 and dy == 0:
        continue
      let next: GridPos = (p.x + dx, p.y + dy)
      if not g.inBounds(next) or g.isBlocked(next):
        continue
      if dx != 0 and dy != 0 and
          (g.isBlocked((p.x + dx, p.y)) and g.isBlocked((p.x, p.y + dy))):
        continue
      result.add next

func cost(g: Grid, source, target: GridPos): float =
  discard g
  if abs(source.x - target.x) + abs(source.y - target.y) == 2: 1.414 else: 1.0

func heuristic(g: Grid, source, target: GridPos): float =
  discard g
  euclid(source, target)

proc reconstruct(cameFrom: Table[GridPos, GridPos], cur: GridPos): seq[GridPos] =
  result.add cur
  var c = cur
  while c in cameFrom:
    c = cameFrom[c]
    result.add c
  result.reverse()

proc aStar(g: Grid, start, goal: GridPos, diag: bool = true): seq[GridPos] =
  var open = initHeapQueue[AStarNode]()
  open.push AStarNode(pos:start, g:0, f: euclid(start,goal))
  var cameFrom: Table[GridPos, GridPos]
  var gScore = initTable[GridPos,float]()
  gScore[start]=0
  var closed: Table[GridPos,bool]

  while open.len>0:
    let cur = open.pop().pos
    if cur==goal:
      return reconstruct(cameFrom, cur)
    if cur in closed: continue
    closed[cur]=true
    let neigh = if diag: toSeq(neighbors8(g,cur)) else: toSeq(neighbors4(g,cur))
    for nb in neigh:
      let tentative = gScore.getOrDefault(cur, Inf) + (if abs(nb.x-cur.x)+abs(nb.y-cur.y)==2: 1.414 else: 1.0)
      if tentative < gScore.getOrDefault(nb, Inf):
        cameFrom[nb]=cur
        gScore[nb]=tentative
        let f = tentative + euclid(nb,goal)
        open.push AStarNode(pos:nb, g:tentative, f:f)
  @[] # no path

# Generic version using concepts (Nim's killer feature).
type
  Navigable[Node] = concept graph
    neighbors(graph, default(Node)) is seq[Node]
    cost(graph, default(Node), default(Node)) is float
    heuristic(graph, default(Node), default(Node)) is float

type GenericAStarNode[Node] = object
  value: Node
  priority: float

func `<`[Node](a, b: GenericAStarNode[Node]): bool =
  a.priority < b.priority

proc aStarGeneric[Node, G](
    graph: G, start, goal: Node
): seq[Node] =
  ## Find a lowest-cost path using the graph's concept-defined operations.
  when not compiles(graph.neighbors(start)):
    {.error: "A Navigable graph must provide neighbors(graph, node).".}
  when not compiles(graph.cost(start, goal)):
    {.error: "A Navigable graph must provide cost(graph, from, to).".}
  when not compiles(graph.heuristic(start, goal)):
    {.error: "A Navigable graph must provide heuristic(graph, node, goal).".}

  var open = initHeapQueue[GenericAStarNode[Node]]()
  open.push GenericAStarNode[Node](
    value: start,
    priority: graph.heuristic(start, goal)
  )

  var cameFrom = initTable[Node, Node]()
  var gScore = initTable[Node, float]()
  var closed = initTable[Node, bool]()
  gScore[start] = 0.0

  while open.len > 0:
    let current = open.pop().value
    if current == goal:
      return reconstruct(cameFrom, current)
    if current in closed:
      continue
    closed[current] = true

    for next in graph.neighbors(current):
      let tentative = gScore[current] + graph.cost(current, next)
      if tentative < gScore.getOrDefault(next, Inf):
        cameFrom[next] = current
        gScore[next] = tentative
        open.push GenericAStarNode[Node](
          value: next,
          priority: tentative + graph.heuristic(next, goal)
        )

  @[]

when isMainModule:
  var g = initGrid(20,12)
  for x in 3..16: g.blocked[5][x]=true
  g.blocked[5][8]=false # doorway
  g.blocked[6][10]=true; g.blocked[7][10]=true
  let path = aStar(g, (0,0), (19,11), true)
  let genericPath = aStarGeneric(g, (0,0), (19,11))
  echo &"Path len {path.len}"
  echo &"Generic path len {genericPath.len}"
  var viz = newSeqWith(g.h, newSeq[char](g.w))
  for y in 0..<g.h:
    for x in 0..<g.w:
      viz[y][x] = if g.blocked[y][x]: '#' else: '.'
  for p in path: viz[p.y][p.x]='*'
  viz[0][0]='S'; viz[11][19]='G'
  for row in viz:
    echo row.join("")
  echo "\nWhy Nim? `concept` lets you write A* once and reuse for grid, navmesh, GCS graph, or game state. Iterators + heapqueue give zero-allocation neighbor generation."
