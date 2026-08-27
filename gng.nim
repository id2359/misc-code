# gng.nim
#
# A compact, single-file example implementation of Fritzke's
# Growing Neural Gas (GNG) algorithm.
#
# Compile:
#   nim c -r gng.nim
#
# This example trains on a simple 2-D synthetic data set.
# The implementation follows the original GNG structure:
#   - find nearest and second-nearest units
#   - accumulate quantization error at the winner
#   - move winner and graph neighbours toward the sample
#   - connect winner and runner-up
#   - age/remove stale edges
#   - periodically insert a unit in the highest-error region
#   - decay accumulated errors

import math, random, sequtils, strformat

type
  Vec = seq[float64]

  Node = object
    w: Vec
    err: float64

  Edge = object
    a, b: int
    age: int

  GNG = object
    nodes: seq[Node]
    edges: seq[Edge]

    epsWinner: float64
    epsNeighbor: float64
    maxAge: int
    insertEvery: int
    alpha: float64
    decay: float64

proc sqDist(a, b: Vec): float64 =
  assert a.len == b.len
  for i in 0 ..< a.len:
    let d = a[i] - b[i]
    result += d * d

proc moveToward(w: var Vec, x: Vec, rate: float64) =
  assert w.len == x.len
  for i in 0 ..< w.len:
    w[i] += rate * (x[i] - w[i])

proc edgeIndex(g: GNG, a, b: int): int =
  for i, e in g.edges:
    if (e.a == a and e.b == b) or (e.a == b and e.b == a):
      return i
  return -1

proc addOrResetEdge(g: var GNG, a, b: int) =
  let idx = edgeIndex(g, a, b)
  if idx >= 0:
    g.edges[idx].age = 0
  else:
    g.edges.add Edge(a: a, b: b, age: 0)

proc neighbors(g: GNG, nodeIdx: int): seq[int] =
  for e in g.edges:
    if e.a == nodeIdx:
      result.add e.b
    elif e.b == nodeIdx:
      result.add e.a

proc twoNearest(g: GNG, x: Vec): tuple[first, second: int] =
  assert g.nodes.len >= 2

  var best1 = Inf
  var best2 = Inf
  var i1 = -1
  var i2 = -1

  for i, n in g.nodes:
    let d = sqDist(n.w, x)
    if d < best1:
      best2 = best1
      i2 = i1
      best1 = d
      i1 = i
    elif d < best2:
      best2 = d
      i2 = i

  result = (i1, i2)

proc removeNode(g: var GNG, idx: int) =
  # Remove all edges touching idx, and shift indices above idx down by one.
  var newEdges: seq[Edge]

  for e0 in g.edges:
    if e0.a == idx or e0.b == idx:
      continue

    var e = e0
    if e.a > idx:
      dec e.a
    if e.b > idx:
      dec e.b
    newEdges.add e

  g.edges = newEdges
  g.nodes.delete(idx)

proc removeOldEdgesAndIsolatedNodes(g: var GNG) =
  g.edges = g.edges.filterIt(it.age <= g.maxAge)

  # Remove isolated nodes from highest index to lowest so index shifts are safe.
  var isolated: seq[int]
  for i in 0 ..< g.nodes.len:
    if g.neighbors(i).len == 0:
      isolated.add i

  for k in countdown(isolated.high, 0):
    if g.nodes.len > 2:
      g.removeNode(isolated[k])

proc insertNode(g: var GNG) =
  if g.nodes.len < 2:
    return

  # q = node with maximum accumulated error
  var q = 0
  for i in 1 ..< g.nodes.len:
    if g.nodes[i].err > g.nodes[q].err:
      q = i

  let ns = g.neighbors(q)
  if ns.len == 0:
    return

  # f = neighbour of q with largest accumulated error
  var f = ns[0]
  for n in ns[1 .. ^1]:
    if g.nodes[n].err > g.nodes[f].err:
      f = n

  # r is inserted halfway between q and f
  var wr = newSeq[float64](g.nodes[q].w.len)
  for d in 0 ..< wr.len:
    wr[d] = 0.5 * (g.nodes[q].w[d] + g.nodes[f].w[d])

  let r = g.nodes.len
  g.nodes.add Node(w: wr, err: 0.0)

  # Remove q-f edge
  let idx = edgeIndex(g, q, f)
  if idx >= 0:
    g.edges.delete(idx)

  # Insert q-r and r-f
  g.edges.add Edge(a: q, b: r, age: 0)
  g.edges.add Edge(a: r, b: f, age: 0)

  # Reduce local errors as in Fritzke's algorithm
  g.nodes[q].err *= g.alpha
  g.nodes[f].err *= g.alpha
  g.nodes[r].err = g.nodes[q].err

proc trainOne(g: var GNG, x: Vec, step: int) =
  assert g.nodes.len >= 2
  assert x.len == g.nodes[0].w.len

  let (s1, s2) = g.twoNearest(x)

  # 1. Age all edges emanating from the winner.
  for i in 0 ..< g.edges.len:
    if g.edges[i].a == s1 or g.edges[i].b == s1:
      inc g.edges[i].age

  # 2. Accumulate squared quantization error at the winner.
  g.nodes[s1].err += sqDist(g.nodes[s1].w, x)

  # 3. Move winner strongly.
  g.nodes[s1].w.moveToward(x, g.epsWinner)

  # 4. Move direct topological neighbours weakly.
  let ns = g.neighbors(s1)
  for n in ns:
    g.nodes[n].w.moveToward(x, g.epsNeighbor)

  # 5. Connect winner and runner-up, or refresh their existing edge.
  g.addOrResetEdge(s1, s2)

  # 6. Remove stale topology.
  g.removeOldEdgesAndIsolatedNodes()

  # 7. Periodically insert a new node in the highest-error region.
  if step > 0 and step mod g.insertEvery == 0:
    g.insertNode()

  # 8. Global error decay.
  for i in 0 ..< g.nodes.len:
    g.nodes[i].err *= g.decay

proc initGNG(dim: int): GNG =
  assert dim > 0

  result.epsWinner = 0.20
  result.epsNeighbor = 0.006
  result.maxAge = 50
  result.insertEvery = 100
  result.alpha = 0.5
  result.decay = 0.995

  for _ in 0 ..< 2:
    var w = newSeq[float64](dim)
    for d in 0 ..< dim:
      w[d] = rand(1.0)
    result.nodes.add Node(w: w, err: 0.0)

proc gaussian(mu, sigma: float64): float64 =
  # Box-Muller transform.
  var u1 = max(rand(1.0), 1e-12)
  let u2 = rand(1.0)
  mu + sigma * sqrt(-2.0 * ln(u1)) * cos(2.0 * PI * u2)

proc sampleData(): Vec =
  # Three simple 2-D clusters.
  case rand(2)
  of 0:
    @[gaussian(-1.0, 0.22), gaussian(-0.5, 0.20)]
  of 1:
    @[gaussian(1.0, 0.18), gaussian(0.9, 0.18)]
  else:
    @[gaussian(0.2, 0.25), gaussian(-1.2, 0.15)]

proc quantizationError(g: GNG, samples: seq[Vec]): float64 =
  if samples.len == 0:
    return 0.0

  for x in samples:
    let (s1, _) = g.twoNearest(x)
    result += sqDist(g.nodes[s1].w, x)

  result /= float64(samples.len)

proc main() =
  randomize()

  var g = initGNG(2)

  const
    trainSteps = 15_000
    testSamples = 2_000

  for step in 1 .. trainSteps:
    let x = sampleData()
    g.trainOne(x, step)

    if step mod 1000 == 0:
      echo &"step={step:>5}  nodes={g.nodes.len:>3}  edges={g.edges.len:>3}"

  var test: seq[Vec]
  for _ in 0 ..< testSamples:
    test.add sampleData()

  echo ""
  echo "Final network"
  echo "-------------"
  echo "nodes: ", g.nodes.len
  echo "edges: ", g.edges.len
  echo &"mean squared quantization error: {g.quantizationError(test):.6f}"
  echo ""

  echo "Node positions:"
  for i, n in g.nodes:
    echo &"{i:>3}: ({n.w[0]:>8.4f}, {n.w[1]:>8.4f})  error={n.err:.6f}"

  echo ""
  echo "Edges:"
  for e in g.edges:
    echo &"{e.a:>3} -- {e.b:<3}  age={e.age}"

when isMainModule:
  main()
