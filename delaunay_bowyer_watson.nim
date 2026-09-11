# delaunay_bowyer_watson.nim
# Bowyer-Watson Delaunay triangulation - fits Nim's value types + generics perfectly
# nim c -r delaunay_bowyer_watson.nim

import math, random, sequtils, algorithm, tables, strformat

type
  Point = object
    x*, y*: float64
  Edge = object
    a*, b*: int  # always a < b
  Triangle = object
    a*, b*, c*: int

proc mkEdge(a,b: int): Edge =
  if a < b: Edge(a:a,b:b) else: Edge(a:b,b:a)

proc `==`(e1,e2: Edge): bool = e1.a==e2.a and e1.b==e2.b

proc circumcircleContains(p: Point, t: Triangle, pts: seq[Point]): bool =
  let ax = pts[t.a].x
  let ay = pts[t.a].y
  let bx = pts[t.b].x
  let by = pts[t.b].y
  let cx = pts[t.c].x
  let cy = pts[t.c].y
  # Compute circumcenter using determinant formula
  let d = 2.0 * (ax*(by - cy) + bx*(cy - ay) + cx*(ay - by))
  if abs(d) < 1e-12: return false # degenerate
  let a2 = ax*ax + ay*ay
  let b2 = bx*bx + by*by
  let c2 = cx*cx + cy*cy
  let ux = (a2*(by - cy) + b2*(cy - ay) + c2*(ay - by)) / d
  let uy = (a2*(cx - bx) + b2*(ax - cx) + c2*(bx - ax)) / d
  let dx = ax - ux
  let dy = ay - uy
  let r2 = dx*dx + dy*dy
  let dpx = p.x - ux
  let dpy = p.y - uy
  result = dpx*dpx + dpy*dpy <= r2 + 1e-9

proc bowyerWatson(points: seq[Point]): seq[Triangle] =
  if points.len < 3: return
  # bounds for super-triangle
  var minX = points[0].x
  var minY = points[0].y
  var maxX = minX
  var maxY = minY
  for p in points:
    minX = min(minX, p.x); minY = min(minY, p.y)
    maxX = max(maxX, p.x); maxY = max(maxY, p.y)
  let dx = maxX - minX
  let dy = maxY - minY
  let delta = max(dx,dy) * 10.0

  var pts = points
  # super triangle far outside
  pts.add Point(x: minX - delta, y: minY - delta)
  pts.add Point(x: minX + dx/2, y: maxY + delta)
  pts.add Point(x: maxX + delta, y: minY - delta)
  let n = points.len
  let s0 = n; let s1 = n+1; let s2 = n+2

  var tris: seq[Triangle] = @[Triangle(a:s0,b:s1,c:s2)]

  for pi in 0..<n:
    let p = pts[pi]
    var bad: seq[Triangle]
    for t in tris:
      if circumcircleContains(p, t, pts):
        bad.add t
    # find boundary polygon of bad region
    var edgeCount = initTable[Edge,int]()
    for t in bad:
      for e in [mkEdge(t.a,t.b), mkEdge(t.b,t.c), mkEdge(t.c,t.a)]:
        edgeCount[e] = edgeCount.getOrDefault(e,0) + 1
    # remove bad
    tris = tris.filterIt(not (it in bad))
    # re-triangulate hole
    for e,cnt in edgeCount:
      if cnt == 1: # boundary edge
        tris.add Triangle(a: e.a, b: e.b, c: pi)

  # discard triangles using super vertices
  result = tris.filterIt(it.a < n and it.b < n and it.c < n)

when isMainModule:
  randomize(42)
  var pts: seq[Point]
  for i in 0..<30:
    pts.add Point(x: rand(100.0), y: rand(100.0))
  let mesh = bowyerWatson(pts)
  echo &"Points: {pts.len}, Triangles: {mesh.len}"
  for t in mesh[0..min(9, mesh.high)]:
    echo &"  tri {t.a}-{t.b}-{t.c} : ({pts[t.a].x:.1f},{pts[t.a].y:.1f}) ({pts[t.b].x:.1f},{pts[t.b].y:.1f}) ({pts[t.c].x:.1f},{pts[t.c].y:.1f})"
  echo "\nWhy Nim? Value types for Point/Triangle live on stack, no GC. Generic over float32/float64 with concepts is trivial. ARC keeps it real-time."
