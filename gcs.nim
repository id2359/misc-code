# gcs.nim
#
# Compact single-file implementation of Fritzke's Growing Cell Structures (GCS)
# for k = 2 (triangular cells).
#
# Compile & run:
#   nim c -r gcs_fixed.nim
#
# Trains on the same three 2-D Gaussian clusters used in the GNG example.

import math, random, sequtils, strformat, sets

type
  Vec = seq[float64]

  Node = object
    w: Vec
    err: float64          # accumulated local error / resource

  # Undirected edge (stored with a < b for uniqueness)
  Edge = object
    a, b: int

  GCS = object
    nodes: seq[Node]
    edges: seq[Edge]      # the 1-skeleton of the triangular mesh

    epsWinner: float64
    epsNeighbor: float64
    insertEvery: int
    alpha: float64        # error reduction on insertion
    decay: float64        # global error decay

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

proc sqDist(a, b: Vec): float64 =
  assert a.len == b.len
  for i in 0 ..< a.len:
    let d = a[i] - b[i]
    result += d * d

proc moveToward(w: var Vec, x: Vec, rate: float64) =
  assert w.len == x.len
  for i in 0 ..< w.len:
    w[i] += rate * (x[i] - w[i])

proc edgeKey(a, b: int): (int, int) =
  if a < b: (a, b) else: (b, a)

proc hasEdge(g: GCS, a, b: int): bool =
  let (u, v) = edgeKey(a, b)
  for e in g.edges:
    if e.a == u and e.b == v: return true
  false

proc addEdge(g: var GCS, a, b: int) =
  let (u, v) = edgeKey(a, b)
  if not g.hasEdge(u, v):
    g.edges.add Edge(a: u, b: v)

proc removeEdge(g: var GCS, a, b: int) =
  let (u, v) = edgeKey(a, b)
  for i in 0 ..< g.edges.len:
    if g.edges[i].a == u and g.edges[i].b == v:
      g.edges.delete(i)
      return

proc neighbors(g: GCS, idx: int): seq[int] =
  for e in g.edges:
    if e.a == idx: result.add e.b
    elif e.b == idx: result.add e.a

proc commonNeighbors(g: GCS, a, b: int): seq[int] =
  let na = g.neighbors(a).toHashSet
  for n in g.neighbors(b):
    if n in na and n != a and n != b:
      result.add n

# ------------------------------------------------------------------
# Core algorithm
# ------------------------------------------------------------------

proc nearest(g: GCS, x: Vec): int =
  assert g.nodes.len >= 1
  var best = Inf
  result = 0
  for i, n in g.nodes:
    let d = sqDist(n.w, x)
    if d < best:
      best = d
      result = i

proc insertNode(g: var GCS) =
  if g.nodes.len < 3: return

  # q = node with maximum error
  var q = 0
  for i in 1 ..< g.nodes.len:
    if g.nodes[i].err > g.nodes[q].err:
      q = i

  let ns = g.neighbors(q)
  if ns.len == 0: return

  # f = topological neighbour of q that is farthest in input space
  var f = ns[0]
  var maxD = sqDist(g.nodes[q].w, g.nodes[f].w)
  for n in ns[1 .. ^1]:
    let d = sqDist(g.nodes[q].w, g.nodes[n].w)
    if d > maxD:
      maxD = d
      f = n

  # r halfway between q and f
  var wr = newSeq[float64](g.nodes[q].w.len)
  for d in 0 ..< wr.len:
    wr[d] = 0.5 * (g.nodes[q].w[d] + g.nodes[f].w[d])

  let r = g.nodes.len
  g.nodes.add Node(w: wr, err: 0.0)

  # Topology update (preserve triangular mesh):
  # remove edge q–f, add q–r and r–f,
  # and connect r to every common neighbour of q and f
  g.removeEdge(q, f)
  g.addEdge(q, r)
  g.addEdge(r, f)

  for c in g.commonNeighbors(q, f):
    g.addEdge(r, c)

  # Error redistribution (classic Fritzke)
  # Original: reduce q and f by alpha, set r to average of reduced errors
  g.nodes[q].err *= g.alpha
  g.nodes[f].err *= g.alpha
  g.nodes[r].err = 0.5 * (g.nodes[q].err + g.nodes[f].err)

proc trainStep(g: var GCS, x: Vec) =
  let winner = g.nearest(x)
  let d = sqDist(g.nodes[winner].w, x)
  g.nodes[winner].err += d

  # move winner towards input
  g.nodes[winner].w.moveToward(x, g.epsWinner)

  # move topological neighbors
  for nb in g.neighbors(winner):
    g.nodes[nb].w.moveToward(x, g.epsNeighbor)

  # global decay
  for i in 0 ..< g.nodes.len:
    g.nodes[i].err *= g.decay

proc initGCS(dim: int, epsWinner = 0.1, epsNeighbor = 0.01,
             insertEvery = 100, alpha = 0.5, decay = 0.995): GCS =
  result.epsWinner = epsWinner
  result.epsNeighbor = epsNeighbor
  result.insertEvery = insertEvery
  result.alpha = alpha
  result.decay = decay

  # start with a single triangle in [0,1]^dim (scaled later by data)
  result.nodes = @[
    Node(w: @[0.0, 0.0], err: 0.0),
    Node(w: @[1.0, 0.0], err: 0.0),
    Node(w: @[0.5, 0.866], err: 0.0)
  ]
  # pad to dim if needed
  for i in 0 ..< result.nodes.len:
    while result.nodes[i].w.len < dim:
      result.nodes[i].w.add 0.0
    result.nodes[i].w.setLen(dim)

  result.edges = @[
    Edge(a: 0, b: 1),
    Edge(a: 1, b: 2),
    Edge(a: 0, b: 2)
  ]

# ------------------------------------------------------------------
# Test data: same three 2-D Gaussian clusters as GNG example
# ------------------------------------------------------------------

proc randNormal(mean, std: float64): float64 =
  # Box-Muller
  var u1 = rand(1.0)
  var u2 = rand(1.0)
  while u1 <= 0.0: u1 = rand(1.0)
  result = mean + std * sqrt(-2.0 * ln(u1)) * cos(2.0 * PI * u2)

proc sampleCluster(center: Vec, std: float64): Vec =
  result = newSeq[float64](center.len)
  for i in 0 ..< center.len:
    result[i] = randNormal(center[i], std)

proc generateTestData(nPerCluster: int = 500): seq[Vec] =
  let centers = @[
    @[0.0, 0.0],
    @[5.0, 5.0],
    @[0.0, 5.0]
  ]
  let std = 0.8
  for c in centers:
    for _ in 0 ..< nPerCluster:
      result.add sampleCluster(c, std)

proc quantizationError(g: GCS, data: seq[Vec]): float64 =
  var sum = 0.0
  for x in data:
    sum += sqDist(g.nodes[g.nearest(x)].w, x)
  sum / float64(data.len)

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------

proc main() =
  randomize(42) # deterministic seed for repeatable test run

  echo "=== Growing Cell Structures (GCS) k=2 demo ==="
  let data = generateTestData(500)
  echo &"Generated {data.len} points from 3 clusters"

  var gcs = initGCS(
    dim = 2,
    epsWinner = 0.1,
    epsNeighbor = 0.01,
    insertEvery = 100,
    alpha = 0.5,
    decay = 0.995
  )

  echo &"Initial: {gcs.nodes.len} nodes, {gcs.edges.len} edges (triangle)"

  let maxIter = 10000
  let maxNodes = 50

  for t in 1 .. maxIter:
    let x = data[rand(data.len - 1)]
    gcs.trainStep(x)

    if t mod gcs.insertEvery == 0 and gcs.nodes.len < maxNodes:
      gcs.insertNode()
      if t mod 1000 == 0:
        echo &" iter {t:5} -> nodes: {gcs.nodes.len:3} edges: {gcs.edges.len:3} qError: {gcs.quantizationError(data):.4f}"

  echo ""
  echo &"Final: {gcs.nodes.len} nodes, {gcs.edges.len} edges"
  echo &"Final quantization error: {gcs.quantizationError(data):.4f}"
  echo ""
  echo "Nodes (w, err):"
  for i, n in gcs.nodes:
    echo &"  {i:3}: w=[{n.w[0]:6.3f}, {n.w[1]:6.3f}] err={n.err:.4f} deg={gcs.neighbors(i).len}"

  echo ""
  echo "Sample edges (first 20):"
  for i, e in gcs.edges:
    if i >= 20:
      echo &"  ... and {gcs.edges.len - 20} more"
      break
    echo &"  {e.a} -- {e.b}"

  # Simple sanity check - nodes should have moved into clusters
  echo ""
  echo "Done. You can plot nodes vs data in Python/matplotlib if you want."

when isMainModule:
  main()
