# concepts_geometric_algebra.nim
# Demonstrates Nim's structural subtyping (Concepts) for zero-overhead
# compile-time polymorphism without vtables, inheritance, or heap allocation.
#
# Compile and run:
#   nim c -r concepts_geometric_algebra.nim

import math, strformat

type
  Point2D* = object
    x*, y*: float

  BoundingBox* = object
    minX*, minY*, maxX*, maxY*: float

proc initBoundingBox*(minX, minY, maxX, maxY: float): BoundingBox =
  BoundingBox(minX: minX, minY: minY, maxX: maxX, maxY: maxY)

proc area*(bb: BoundingBox): float =
  max(0.0, bb.maxX - bb.minX) * max(0.0, bb.maxY - bb.minY)

proc contains*(bb: BoundingBox, p: Point2D): bool =
  p.x >= bb.minX and p.x <= bb.maxX and p.y >= bb.minY and p.y <= bb.maxY

proc contains*(outer, inner: BoundingBox): bool =
  inner.minX >= outer.minX and inner.maxX <= outer.maxX and
  inner.minY >= outer.minY and inner.maxY <= outer.maxY

proc combine*(a, b: BoundingBox): BoundingBox =
  BoundingBox(
    minX: min(a.minX, b.minX),
    minY: min(a.minY, b.minY),
    maxX: max(a.maxX, b.maxX),
    maxY: max(a.maxY, b.maxY)
  )

# ==============================================================================
# Nim Concepts (Structural Interfaces)
# ==============================================================================

type
  Shape* = concept s
    ## Any type that can compute its surface area and perimeter.
    s.area() is float
    s.perimeter() is float

  Transformable* = concept t
    ## Any geometric type that supports 2D translation and uniform scaling.
    t.translate(1.0, 1.0) is typeof(t)
    t.scale(2.0) is typeof(t)

  Bounded* = concept b
    ## Any type that has an axis-aligned bounding box.
    b.boundingBox() is BoundingBox

  Renderable* = concept r
    ## Any type that can produce an ASCII representation.
    r.render() is string

# ==============================================================================
# Concrete Types Satisfying Concepts
# ==============================================================================

type
  Circle* = object
    center*: Point2D
    radius*: float

  Rectangle* = object
    origin*: Point2D
    width*, height*: float

  CompoundShape*[S1, S2] = object
    shape1*: S1
    shape2*: S2

# --- Circle Implementation ---
proc initCircle*(x, y, r: float): Circle =
  Circle(center: Point2D(x: x, y: y), radius: r)

proc area*(c: Circle): float =
  PI * c.radius * c.radius

proc perimeter*(c: Circle): float =
  2.0 * PI * c.radius

proc boundingBox*(c: Circle): BoundingBox =
  initBoundingBox(
    c.center.x - c.radius, c.center.y - c.radius,
    c.center.x + c.radius, c.center.y + c.radius
  )

proc translate*(c: Circle, dx, dy: float): Circle =
  Circle(center: Point2D(x: c.center.x + dx, y: c.center.y + dy), radius: c.radius)

proc scale*(c: Circle, factor: float): Circle =
  Circle(center: c.center, radius: c.radius * factor)

proc render*(c: Circle): string =
  &"Circle(at=({c.center.x:.1f}, {c.center.y:.1f}), r={c.radius:.1f})"

# --- Rectangle Implementation ---
proc initRectangle*(x, y, w, h: float): Rectangle =
  Rectangle(origin: Point2D(x: x, y: y), width: w, height: h)

proc area*(r: Rectangle): float =
  r.width * r.height

proc perimeter*(r: Rectangle): float =
  2.0 * (r.width + r.height)

proc boundingBox*(r: Rectangle): BoundingBox =
  initBoundingBox(r.origin.x, r.origin.y, r.origin.x + r.width, r.origin.y + r.height)

proc translate*(r: Rectangle, dx, dy: float): Rectangle =
  Rectangle(origin: Point2D(x: r.origin.x + dx, y: r.origin.y + dy), width: r.width, height: r.height)

proc scale*(r: Rectangle, factor: float): Rectangle =
  Rectangle(origin: r.origin, width: r.width * factor, height: r.height * factor)

proc render*(r: Rectangle): string =
  &"Rectangle(at=({r.origin.x:.1f}, {r.origin.y:.1f}), size={r.width:.1f}x{r.height:.1f})"

# --- CompoundShape Implementation (Generic composition of any two shapes) ---
proc initCompound*[S1, S2](s1: S1, s2: S2): CompoundShape[S1, S2] =
  CompoundShape[S1, S2](shape1: s1, shape2: s2)

proc area*[S1: Shape, S2: Shape](cs: CompoundShape[S1, S2]): float =
  cs.shape1.area() + cs.shape2.area()

proc perimeter*[S1: Shape, S2: Shape](cs: CompoundShape[S1, S2]): float =
  cs.shape1.perimeter() + cs.shape2.perimeter()

proc boundingBox*[S1: Bounded, S2: Bounded](cs: CompoundShape[S1, S2]): BoundingBox =
  cs.shape1.boundingBox().combine(cs.shape2.boundingBox())

proc translate*[S1: Transformable, S2: Transformable](
    cs: CompoundShape[S1, S2], dx, dy: float
): CompoundShape[S1, S2] =
  CompoundShape[S1, S2](
    shape1: cs.shape1.translate(dx, dy),
    shape2: cs.shape2.translate(dx, dy)
  )

proc scale*[S1: Transformable, S2: Transformable](
    cs: CompoundShape[S1, S2], factor: float
): CompoundShape[S1, S2] =
  CompoundShape[S1, S2](
    shape1: cs.shape1.scale(factor),
    shape2: cs.shape2.scale(factor)
  )

proc render*[S1: Renderable, S2: Renderable](cs: CompoundShape[S1, S2]): string =
  &"Compound({cs.shape1.render()} + {cs.shape2.render()})"

# ==============================================================================
# Generic Algorithms Powered by Concept Constraints
# ==============================================================================

proc totalArea*[T: Shape](shapes: openArray[T]): float =
  ## Calculate aggregate area over any collection of objects matching Shape.
  for s in shapes:
    result += s.area()

proc fitsInside*[Inner: Bounded, Outer: Bounded](inner: Inner, outer: Outer): bool =
  ## Determine whether the bounding box of one item fits completely within another.
  outer.boundingBox().contains(inner.boundingBox())

proc transformAll*[T: Transformable](items: openArray[T], dx, dy, factor: float): seq[T] =
  ## Batch-scale and translate any homogeneous collection of Transformable items.
  for item in items:
    result.add item.scale(factor).translate(dx, dy)

proc inspectShape*[T: Shape and Bounded and Renderable](item: T) =
  ## Concept composition: requires Shape AND Bounded AND Renderable.
  let bb = item.boundingBox()
  echo &"  [Render]    {item.render()}"
  echo &"  [Area]      {item.area():.2f}"
  echo &"  [Perimeter] {item.perimeter():.2f}"
  echo &"  [Bounds]    ({bb.minX:.1f}, {bb.minY:.1f}) to ({bb.maxX:.1f}, {bb.maxY:.1f})"

when isMainModule:
  echo "=== Nim Concepts: Zero-Overhead Structural Subtyping ==="

  echo "\n1. Individual Shape Inspection (using composed concept constraints):"
  let c1 = initCircle(0.0, 0.0, 5.0)
  let r1 = initRectangle(10.0, 10.0, 4.0, 6.0)

  echo "Circle:"
  inspectShape(c1)

  echo "\nRectangle:"
  inspectShape(r1)

  echo "\n2. Generic Compound Shape (Composed of Circle and Rectangle):"
  let comp = initCompound(c1, r1)
  inspectShape(comp)

  echo "\n3. Generic Operations on Collections:"
  let circles = [initCircle(0, 0, 1.0), initCircle(2, 2, 2.0), initCircle(5, 5, 3.0)]
  echo &"Total Circle Area: {totalArea(circles):.2f}"

  let transformedCircles = transformAll(circles, dx = 10.0, dy = 0.0, factor = 2.0)
  echo "After transformAll (scaled 2x, translated +10x):"
  for tc in transformedCircles:
    echo &"  {tc.render()} (area = {tc.area():.2f})"

  echo "\n4. Spatial Containment via Bounded concept:"
  let boundingArena = initRectangle(-20.0, -20.0, 60.0, 60.0)
  echo &"Does Arena contain Circle c1?   {fitsInside(c1, boundingArena)}"
  echo &"Does Arena contain Compound?    {fitsInside(comp, boundingArena)}"
  let tinyBox = initRectangle(0.0, 0.0, 1.0, 1.0)
  echo &"Does TinyBox contain Circle c1? {fitsInside(c1, tinyBox)}"

  echo "\nWhy Nim? Concepts enable compile-time duck typing. Unlike C++ virtual classes"
  echo "or Java interfaces, values stay flat on the stack without dynamic dispatch or GC overhead!"
