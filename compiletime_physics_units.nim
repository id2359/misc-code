# compiletime_physics_units.nim
# Demonstrates Nim's compile-time evaluation, static[T] type-level parameters,
# compile-time precomputation of scientific tables, and static assertions.
#
# Compile and run:
#   nim c -r compiletime_physics_units.nim

import math, strformat, strutils

type
  Quantity*[M, L, T: static[int]] = object
    ## A physical quantity with dimensions:
    ## M = Mass exponent (kg^M)
    ## L = Length exponent (m^L)
    ## T = Time exponent (s^T)
    val*: float

# --- Type Aliases for Standard SI Units ---
type
  Dimensionless* = Quantity[0, 0, 0]
  Length* = Quantity[0, 1, 0]
  Time* = Quantity[0, 0, 1]
  Mass* = Quantity[1, 0, 0]
  Velocity* = Quantity[0, 1, -1]
  Acceleration* = Quantity[0, 1, -2]
  Force* = Quantity[1, 1, -2]
  Energy* = Quantity[1, 2, -2]
  Power* = Quantity[1, 2, -3]
  Pressure* = Quantity[1, -1, -2]

# --- Value Constructors ---
proc meters*(v: float): Length {.inline.} = Length(val: v)
proc seconds*(v: float): Time {.inline.} = Time(val: v)
proc kilograms*(v: float): Mass {.inline.} = Mass(val: v)
proc newtons*(v: float): Force {.inline.} = Force(val: v)
proc joules*(v: float): Energy {.inline.} = Energy(val: v)

# --- Compile-time Unit String Formatter ---
proc formatUnit*[M, L, T: static[int]](): string =
  ## Evaluated at compile time or runtime to describe SI dimensional units.
  if M == 0 and L == 0 and T == 0: return ""
  if M == 1 and L == 1 and T == -2: return "N"
  if M == 1 and L == 2 and T == -2: return "J"
  if M == 1 and L == 2 and T == -3: return "W"
  if M == 1 and L == -1 and T == -2: return "Pa"
  if M == 0 and L == 1 and T == -1: return "m/s"
  if M == 0 and L == 1 and T == -2: return "m/s²"

  var parts: seq[string] = @[]
  if M != 0: parts.add(if M == 1: "kg" else: &"kg^{M}")
  if L != 0: parts.add(if L == 1: "m" else: &"m^{L}")
  if T != 0: parts.add(if T == 1: "s" else: &"s^{T}")
  result = parts.join("·")

proc `$`*[M, L, T: static[int]](q: Quantity[M, L, T]): string =
  const unit = formatUnit[M, L, T]()
  if unit.len > 0:
    &"{q.val:.4g} {unit}"
  else:
    &"{q.val:.4g}"

# --- Dimension-Preserving Arithmetic Operators ---
proc `+`*[M, L, T: static[int]](a, b: Quantity[M, L, T]): Quantity[M, L, T] {.inline.} =
  Quantity[M, L, T](val: a.val + b.val)

proc `-`*[M, L, T: static[int]](a, b: Quantity[M, L, T]): Quantity[M, L, T] {.inline.} =
  Quantity[M, L, T](val: a.val - b.val)

proc `*`*[M1, L1, T1, M2, L2, T2: static[int]](
    a: Quantity[M1, L1, T1], b: Quantity[M2, L2, T2]
): Quantity[M1 + M2, L1 + L2, T1 + T2] {.inline.} =
  ## Static arithmetic at compile time: dimensions add when multiplying
  Quantity[M1 + M2, L1 + L2, T1 + T2](val: a.val * b.val)

proc `/`*[M1, L1, T1, M2, L2, T2: static[int]](
    a: Quantity[M1, L1, T1], b: Quantity[M2, L2, T2]
): Quantity[M1 - M2, L1 - L2, T1 - T2] {.inline.} =
  ## Static arithmetic at compile time: dimensions subtract when dividing
  Quantity[M1 - M2, L1 - L2, T1 - T2](val: a.val / b.val)

proc `*`*[M, L, T: static[int]](scalar: float, q: Quantity[M, L, T]): Quantity[M, L, T] {.inline.} =
  Quantity[M, L, T](val: scalar * q.val)

proc `*`*[M, L, T: static[int]](q: Quantity[M, L, T], scalar: float): Quantity[M, L, T] {.inline.} =
  Quantity[M, L, T](val: q.val * scalar)

proc `/`*[M, L, T: static[int]](q: Quantity[M, L, T], scalar: float): Quantity[M, L, T] {.inline.} =
  Quantity[M, L, T](val: q.val / scalar)

# --- Compile-Time Gravitational & Orbital Precomputations ---
type
  CelestialBody* = object
    name*: string
    mass*: Mass
    radius*: Length
    surfaceGravity*: Acceleration
    escapeVelocity*: Velocity

const
  # Gravitational constant G in m^3 / (kg * s^2) -> Quantity[-1, 3, -2]
  GravitationalConstant* = Quantity[-1, 3, -2](val: 6.67430e-11)

func computeGravity*(mass: Mass, radius: Length): Acceleration =
  let rSquared = radius * radius
  let gTimesM = GravitationalConstant * mass
  gTimesM / rSquared

func computeEscapeSpeed*(mass: Mass, radius: Length): Velocity =
  let vSquaredVal = 2.0 * GravitationalConstant.val * mass.val / radius.val
  Velocity(val: sqrt(vSquaredVal))

# Compile-time celestial lookup table computed at compile time
func initCelestial(name: string, massKg: float, radiusM: float): CelestialBody =
  let m = massKg.kilograms
  let r = radiusM.meters
  CelestialBody(
    name: name,
    mass: m,
    radius: r,
    surfaceGravity: computeGravity(m, r),
    escapeVelocity: computeEscapeSpeed(m, r)
  )

# Entire array is evaluated and baked into ROM at compile time via `const`
const SolarSystemBodies*: array[4, CelestialBody] = [
  initCelestial("Earth", 5.972e24, 6.371e6),
  initCelestial("Moon", 7.342e22, 1.737e6),
  initCelestial("Mars", 6.417e23, 3.390e6),
  initCelestial("Jupiter", 1.898e27, 6.991e7)
]

# Compile-time static assertions ensuring dimensional consistency
static:
  let testDist = 100.0.meters
  let testTime = 10.0.seconds
  let testMass = 50.0.kilograms

  let testVel = testDist / testTime
  let testAcc = testVel / testTime
  let testForce = testMass * testAcc
  let testWork = testForce * testDist
  let testKineticEnergy = 0.5 * testMass * (testVel * testVel)

  doAssert typeof(testVel) is Velocity, "Velocity dimensional mismatch"
  doAssert typeof(testAcc) is Acceleration, "Acceleration dimensional mismatch"
  doAssert typeof(testForce) is Force, "Force dimensional mismatch"
  doAssert typeof(testWork) is Energy, "Work dimensional mismatch"
  doAssert typeof(testKineticEnergy) is Energy, "Kinetic Energy must have Energy dimensions"
  doAssert SolarSystemBodies[0].surfaceGravity.val > 9.7 and SolarSystemBodies[0].surfaceGravity.val < 9.9

when isMainModule:
  echo "=== Nim Compile-Time Evaluation & Static Dimensional Analysis ==="
  echo "All dimensional checks and planetary tables were verified at compile time.\n"

  echo "1. Physical Calculations with Guaranteed Dimensional Safety:"
  let carMass = 1500.0.kilograms
  let speed = (100.0 / 3.6).meters / 1.0.seconds # 100 km/h in m/s
  let stoppingDistance = 40.0.meters

  let kineticEnergy = 0.5 * carMass * (speed * speed)
  # Work = Force * Distance => Required Braking Force = Energy / Distance
  let requiredBrakingForce = kineticEnergy / stoppingDistance

  echo &"   Vehicle Mass:         {carMass}"
  echo &"   Cruising Speed:       {speed}"
  echo &"   Kinetic Energy:       {kineticEnergy}"
  echo &"   Stopping Distance:    {stoppingDistance}"
  echo &"   Braking Force Needed: {requiredBrakingForce}"

  echo "\n2. Precomputed Celestial Bodies (Baked into binary at compile-time):"
  echo "   ---------------------------------------------------------------------"
  echo "   Body      Mass (kg)      Radius (km)   Gravity (m/s²)  Escape (km/s)"
  echo "   ---------------------------------------------------------------------"
  for body in SolarSystemBodies:
    let rKm = body.radius.val / 1000.0
    let vEscKm = body.escapeVelocity.val / 1000.0
    echo &"   {body.name:<9} {body.mass.val:12.3e}   {rKm:10.1f}    {body.surfaceGravity.val:12.2f}    {vEscKm:10.2f}"
  echo "   ---------------------------------------------------------------------"

  echo "\nWhy Nim? `static[int]` generic parameters allow arithmetic in types, giving zero-cost"
  echo "dimensional safety. Any unit mismatch (e.g. Length + Time) fails at compile time!"
