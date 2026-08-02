#[ This program simulates SU(GROUP) lattice gauge fields with the
   simple Wilson action.
   Converted to Nim from Creutz's C++ puregauge.cc
]#

import os, strutils, math, times, strformat

const
  GROUP = 2
  DIM = 4
  SIZE = 8
  HITS = 10

var beta = 2.3

type
  Matrix = object
    real: array[GROUP, array[GROUP, float64]]
    imag: array[GROUP, array[GROUP, float64]]

proc drand48(): float64 {.importc: "drand48", header: "<stdlib.h>".}
proc srand48(seed: int) {.importc: "srand48", header: "<stdlib.h>".}

proc setIdentity(m: var Matrix, x: float64) =
  for i in 0 ..< GROUP:
    for j in 0 ..< GROUP:
      m.real[i][j] = if i == j: x else: 0.0
      m.imag[i][j] = 0.0

proc scale(m: var Matrix, x: float64) =
  for i in 0 ..< GROUP:
    for j in 0 ..< GROUP:
      m.real[i][j] *= x
      m.imag[i][j] *= x

proc matMul(lhs, rhs: Matrix): Matrix =
  for i in 0 ..< GROUP:
    for j in 0 ..< GROUP:
      for k in 0 ..< GROUP:
        result.real[i][j] += lhs.real[i][k] * rhs.real[k][j] - lhs.imag[i][k] * rhs.imag[k][j]
        result.imag[i][j] += lhs.real[i][k] * rhs.imag[k][j] + lhs.imag[i][k] * rhs.real[k][j]

proc matAdd(lhs, rhs: Matrix): Matrix =
  for i in 0 ..< GROUP:
    for j in 0 ..< GROUP:
      result.real[i][j] = lhs.real[i][j] + rhs.real[i][j]
      result.imag[i][j] = lhs.imag[i][j] + rhs.imag[i][j]

proc matSub(lhs, rhs: Matrix): Matrix =
  for i in 0 ..< GROUP:
    for j in 0 ..< GROUP:
      result.real[i][j] = lhs.real[i][j] - rhs.real[i][j]
      result.imag[i][j] = lhs.imag[i][j] - rhs.imag[i][j]

proc conjugate(g: Matrix): Matrix =
  for i in 0 ..< GROUP:
    for j in 0 ..< GROUP:
      result.real[i][j] = g.real[j][i]
      result.imag[i][j] = -g.imag[j][i]

proc thirdrow(g: var Matrix) =
  when GROUP >= 3:
    for i in 0 ..< 3:
      let j = (i + 1) mod 3
      let k = (i + 2) mod 3
      g.real[2][i] = g.real[0][j] * g.real[1][k] - g.imag[0][j] * g.imag[1][k] -
                     g.real[1][j] * g.real[0][k] + g.imag[1][j] * g.imag[0][k]
      g.imag[2][i] = -g.real[0][j] * g.imag[1][k] - g.imag[0][j] * g.real[1][k] +
                     g.real[1][j] * g.imag[0][k] + g.imag[1][j] * g.real[0][k]

proc determinant(m: Matrix, detr, deti: var float64) =
  var copy = m
  let im = GROUP - 1
  for i in 0 ..< im:
    let km = i + 1
    let temp = 1.0 / (copy.real[i][i] * copy.real[i][i] + copy.imag[i][i] * copy.imag[i][i])
    for k in km ..< GROUP:
      let dr = (copy.real[k][i] * copy.real[i][i] + copy.imag[k][i] * copy.imag[i][i]) * temp
      let di = (copy.imag[k][i] * copy.real[i][i] - copy.real[k][i] * copy.imag[i][i]) * temp
      for j in km ..< GROUP:
        copy.real[k][j] += -dr * copy.real[i][j] + di * copy.imag[i][j]
        copy.imag[k][j] += -dr * copy.imag[i][j] - di * copy.real[i][j]
  detr = copy.real[0][0]
  deti = copy.imag[0][0]
  for i in 1 ..< GROUP:
    let temp = detr * copy.real[i][i] - deti * copy.imag[i][i]
    deti = deti * copy.real[i][i] + detr * copy.imag[i][i]
    detr = temp

proc project(m: var Matrix) =
  let nmax = GROUP - (if GROUP < 4: 1 else: 0)
  for i in 0 ..< nmax:
    var temp = m.real[i][0] * m.real[i][0] + m.imag[i][0] * m.imag[i][0]
    for j in 1 ..< GROUP:
      temp += m.real[i][j] * m.real[i][j] + m.imag[i][j] * m.imag[i][j]
    temp = 1.0 / sqrt(temp)
    for j in 0 ..< GROUP:
      m.real[i][j] *= temp
      m.imag[i][j] *= temp
    for k in i + 1 ..< nmax:
      var adotbr = m.real[i][0] * m.real[k][0] + m.imag[i][0] * m.imag[k][0]
      var adotbi = m.real[i][0] * m.imag[k][0] - m.imag[i][0] * m.real[k][0]
      for j in 1 ..< GROUP:
        adotbr += m.real[i][j] * m.real[k][j] + m.imag[i][j] * m.imag[k][j]
        adotbi += m.real[i][j] * m.imag[k][j] - m.imag[i][j] * m.real[k][j]
      for j in 0 ..< GROUP:
        m.real[k][j] -= adotbr * m.real[i][j] - adotbi * m.imag[i][j]
        m.imag[k][j] -= adotbr * m.imag[i][j] + adotbi * m.real[i][j]

  case GROUP
  of 3:
    m.thirdrow()
  of 2:
    m.real[1][0] = -m.real[0][1]
    m.real[1][1] =  m.real[0][0]
    m.imag[1][0] =  m.imag[0][1]
    m.imag[1][1] = -m.imag[0][0]
  else:
    var x, y: float64
    m.determinant(x, y)
    for i in 0 ..< GROUP:
      let w = m.real[0][i] * x + m.imag[0][i] * y
      m.imag[0][i] = m.imag[0][i] * x - m.real[0][i] * y
      m.real[0][i] = w

var
  shape = [SIZE, SIZE, SIZE, SIZE]
  shift: array[DIM, int]
  nsites, nlinks, nplaquettes, vectorlength: int
  ulinks: seq[Matrix]
  table1, table2: seq[Matrix]
  mtemp: array[5, seq[Matrix]]
  sold, snew: seq[float64]
  accepted, myindex, myindex2, parity: seq[int]

proc cleanup(msg: string) =
  echo msg
  quit(0)

proc siteindex(x: array[DIM, int]): int =
  result = 0
  for i in 0 ..< DIM:
    result += shift[i] * x[i]

proc split(x: var array[DIM, int], s: int) =
  var temp = s
  if temp < 0 or temp >= nsites:
    cleanup("bad split")
  for i in countdown(DIM - 1, 1):
    x[i] = 0
    while temp >= shift[i]:
      temp -= shift[i]
      inc x[i]
  x[0] = temp

proc vshift(n: int, x: array[DIM, int]): int =
  var y: array[DIM, int]
  split(y, n)
  for i in 0 ..< DIM:
    if x[i] != 0:
      y[i] += x[i]
      while y[i] >= shape[i]:
        y[i] -= shape[i]
      while y[i] < 0:
        y[i] += shape[i]
  return siteindex(y)

proc ishift(n, dir, dist: int): int =
  var x: array[DIM, int]
  x[dir] = dist
  return vshift(n, x)

proc makeindex(n: int, ind: var seq[int]) =
  var x: array[DIM, int]
  split(x, n)
  var site = 0
  for iv in 0 ..< vectorlength:
    while parity[site] != 0:
      inc site
    ind[iv] = vshift(site, x)
    inc site

proc vgroup(g: var seq[Matrix]) =
  for iv in 0 ..< vectorlength:
    g[iv].project()

proc vcopy(g1: seq[Matrix], g2: var seq[Matrix]) =
  for iv in 0 ..< vectorlength:
    g2[iv] = g1[iv]

proc vprod(g1, g2: seq[Matrix], g3: var seq[Matrix]) =
  for iv in 0 ..< vectorlength:
    g3[iv] = matMul(g1[iv], g2[iv])

proc vsum(g1, g2: seq[Matrix], g3: var seq[Matrix]) =
  for i in 0 ..< GROUP:
    for j in 0 ..< GROUP:
      for iv in 0 ..< vectorlength:
        g3[iv].real[i][j] = g1[iv].real[i][j] + g2[iv].real[i][j]
        g3[iv].imag[i][j] = g1[iv].imag[i][j] + g2[iv].imag[i][j]

proc vtprod(g1, g2: seq[Matrix], s: var seq[float64]) =
  for iv in 0 ..< vectorlength:
    s[iv] = 0.0
  for i in 0 ..< GROUP:
    for j in 0 ..< GROUP:
      for iv in 0 ..< vectorlength:
        s[iv] += g1[iv].real[i][j] * g2[iv].real[j][i] - g1[iv].imag[i][j] * g2[iv].imag[j][i]

proc vtrace(g: seq[Matrix], s: var seq[float64]) =
  for iv in 0 ..< vectorlength:
    s[iv] = g[iv].real[0][0]
  for i in 1 ..< GROUP:
    for iv in 0 ..< vectorlength:
      s[iv] += g[iv].real[i][i]

proc getlinks(g: var seq[Matrix], lattice: seq[Matrix], site, link: int) =
  makeindex(site, myindex)
  let sft = nsites * link
  for iv in 0 ..< vectorlength:
    g[iv] = lattice[myindex[iv] + sft]

proc getconjugate(g: var seq[Matrix], lattice: seq[Matrix], site, link: int) =
  makeindex(site, myindex)
  let sft = nsites * link
  for iv in 0 ..< vectorlength:
    g[iv] = conjugate(lattice[myindex[iv] + sft])

proc savelinks(g: seq[Matrix], lattice: var seq[Matrix], site, link: int) =
  makeindex(site, myindex)
  let sft = nsites * link
  for iv in 0 ..< vectorlength:
    lattice[myindex[iv] + sft] = g[iv]

proc metro(old: var seq[Matrix], trial: seq[Matrix], bias: float64): float64 =
  var expdeltas = 0.0
  for iv in 0 ..< vectorlength:
    let temp = exp(bias * (snew[iv] - sold[iv]))
    expdeltas += temp
    accepted[iv] = if drand48() < temp: 1 else: 0

  for iv in 0 ..< vectorlength:
    if accepted[iv] != 0:
      sold[iv] = snew[iv]
      old[iv] = trial[iv]
  return expdeltas / float64(vectorlength)

proc ranmat(g: var seq[Matrix]) =
  var index = int(float64(vectorlength) * drand48())
  for iv in 0 ..< vectorlength:
    if index >= vectorlength:
      index -= vectorlength
    if drand48() < 0.5:
      g[iv] = table1[index]
    else:
      g[iv] = conjugate(table1[index])
    inc index

proc vtable() =
  ranmat(mtemp[0])
  vprod(table2, mtemp[0], table1)
  vtrace(table2, sold)
  vtrace(table1, snew)
  discard metro(table2, table1, 6.0 * beta / float64(GROUP))
  vcopy(table2, table1)
  vcopy(mtemp[0], table2)
  vgroup(table1)

proc maketable() =
  for iv in 0 ..< vectorlength:
    var t1, t2: Matrix
    t1.setIdentity(beta / float64(GROUP))
    t2.setIdentity(beta / float64(GROUP))
    for i in 0 ..< GROUP:
      for j in 0 ..< GROUP:
        t1.real[i][j] += drand48() - 0.5
        t1.imag[i][j] += drand48() - 0.5
        t2.real[i][j] += drand48() - 0.5
        t2.imag[i][j] += drand48() - 0.5
    table1[iv] = t1
    table2[iv] = t2
  vgroup(table1)
  vgroup(table2)
  for i in 0 ..< 50:
    vtable()

proc staple(st: var seq[Matrix], lat: seq[Matrix], site, link: int) =
  for iv in 0 ..< vectorlength:
    st[iv].setIdentity(0.0)
  let site1 = ishift(site, link, 1)
  for link1 in 0 ..< DIM:
    if link1 != link:
      let site2 = ishift(site, link1, 1)
      let site4 = ishift(site1, link1, -1)
      let site5 = ishift(site, link1, -1)

      getlinks(mtemp[0], lat, site1, link1)
      getconjugate(mtemp[1], lat, site2, link)
      vprod(mtemp[0], mtemp[1], mtemp[2])
      getconjugate(mtemp[0], lat, site, link1)
      vprod(mtemp[2], mtemp[0], mtemp[1])
      vsum(st, mtemp[1], st)

      getconjugate(mtemp[0], lat, site4, link1)
      getconjugate(mtemp[1], lat, site5, link)
      vprod(mtemp[0], mtemp[1], mtemp[2])
      getlinks(mtemp[0], lat, site5, link1)
      vprod(mtemp[2], mtemp[0], mtemp[1])
      vsum(st, mtemp[1], st)

proc monte(lattice: var seq[Matrix]): float64 =
  vtable()
  var stot = 0.0
  var eds = 0.0
  var iacc = 0
  for color in 0 .. 1:
    for link in 0 ..< DIM:
      staple(mtemp[4], lattice, color, link)
      getlinks(mtemp[0], lattice, color, link)
      vtprod(mtemp[0], mtemp[4], sold)
      for hit in 0 ..< HITS:
        ranmat(mtemp[1])
        vprod(mtemp[0], mtemp[1], mtemp[2])
        vtprod(mtemp[2], mtemp[4], snew)
        eds += metro(mtemp[0], mtemp[2], beta / float64(GROUP))
        for iv in 0 ..< vectorlength:
          iacc += accepted[iv]
          stot += sold[iv]
      savelinks(mtemp[0], lattice, color, link)
  stot = stot / (2.0 * float64(DIM - 1) * float64(nlinks) * float64(GROUP) * float64(HITS))
  let acc = float64(iacc) / (float64(nlinks) * float64(HITS))
  eds = eds / (2.0 * float64(DIM) * float64(HITS))
  echo &"stot={stot:.6f}, acc={acc:.6f}, eds={eds:.6f}"
  return stot

proc overrelax(lattice: var seq[Matrix]): float64 =
  if GROUP > 3:
    cleanup("overrelax needs GROUP<=3 or more temporaries")
  var stot = 0.0
  var eds = 0.0
  var iacc = 0
  for color in 0 .. 1:
    for link in 0 ..< DIM:
      staple(mtemp[4], lattice, color, link)
      getlinks(mtemp[0], lattice, color, link)
      vcopy(mtemp[4], mtemp[1])
      vgroup(mtemp[1])
      vprod(mtemp[0], mtemp[1], mtemp[2])
      vprod(mtemp[1], mtemp[2], mtemp[3])
      for iv in 0 ..< vectorlength:
        mtemp[2][iv] = conjugate(mtemp[3][iv])
      vtprod(mtemp[0], mtemp[4], sold)
      vtprod(mtemp[2], mtemp[4], snew)
      eds += metro(mtemp[0], mtemp[2], beta / float64(GROUP))
      for iv in 0 ..< vectorlength:
        iacc += accepted[iv]
        stot += sold[iv]
      savelinks(mtemp[0], lattice, color, link)
  stot = stot / (2.0 * float64(DIM - 1) * float64(nlinks) * float64(GROUP))
  let acc = float64(iacc) / float64(nlinks)
  eds = eds / (2.0 * float64(DIM))
  echo &"stot={stot:.6f}, acc={acc:.6f}, eds={eds:.6f}"
  return stot

proc renorm(l: var seq[Matrix]) =
  for octant in 0 ..< 2 * DIM:
    let link = octant * vectorlength
    for iv in 0 ..< vectorlength:
      l[link + iv].project()

proc loop(u: seq[Matrix], x, y: int): float64 =
  var count = 0
  var result = 0.0
  var uVar = u
  for color in 0 .. 1:
    for link1 in 0 ..< DIM:
      let startLink2 = if x == y: link1 + 1 else: 0
      for link2 in startLink2 ..< DIM:
        if link1 != link2:
          inc count
          var corner = ishift(color, link1, x)
          corner = ishift(corner, link2, y)
          for iv in 0 ..< vectorlength:
            mtemp[0][iv].setIdentity(1.0)
            mtemp[1][iv].setIdentity(1.0)
            mtemp[2][iv].setIdentity(1.0)
            mtemp[3][iv].setIdentity(1.0)
          for i in 0 ..< x:
            getlinks(mtemp[4], uVar, ishift(color, link1, i), link1)
            vprod(mtemp[0], mtemp[4], mtemp[0])
            getconjugate(mtemp[4], uVar, ishift(corner, link1, -i - 1), link1)
            vprod(mtemp[2], mtemp[4], mtemp[2])
          for i in 0 ..< y:
            getlinks(mtemp[4], uVar, ishift(corner, link2, i - y), link2)
            vprod(mtemp[1], mtemp[4], mtemp[1])
            getconjugate(mtemp[4], uVar, ishift(color, link2, y - i - 1), link2)
            vprod(mtemp[3], mtemp[4], mtemp[3])
          vprod(mtemp[0], mtemp[1], mtemp[0])
          vprod(mtemp[0], mtemp[2], mtemp[0])
          vtprod(mtemp[0], mtemp[3], sold)
          for iv in 0 ..< vectorlength:
            result += sold[iv]
  result = result / (float64(GROUP) * float64(vectorlength) * float64(count))
  echo &" {x} by {y} loop = {result:g}"
  return result

proc init() =
  srand48(1234)
  nsites = 1
  for i in 0 ..< DIM:
    nsites *= shape[i]
    if (shape[i] and 1) != 0:
      cleanup("bad dimensions")
  nlinks = DIM * nsites
  nplaquettes = DIM * (DIM - 1) * nsites div 2
  vectorlength = nsites div 2

  ulinks = newSeq[Matrix](nlinks)
  parity = newSeq[int](nsites)
  table1 = newSeq[Matrix](vectorlength)
  table2 = newSeq[Matrix](vectorlength)
  for i in 0 ..< 5:
    mtemp[i] = newSeq[Matrix](vectorlength)
  sold = newSeq[float64](vectorlength)
  snew = newSeq[float64](vectorlength)
  accepted = newSeq[int](vectorlength)
  myindex = newSeq[int](vectorlength)
  myindex2 = newSeq[int](vectorlength)

  shift[0] = 1
  for i in 1 ..< DIM:
    shift[i] = shift[i - 1] * shape[i - 1]

  for iv in 0 ..< nlinks:
    ulinks[iv].setIdentity(1.0)

  var x: array[DIM, int]
  for iv in 0 ..< nsites:
    split(x, iv)
    parity[iv] = 0
    for i in 0 ..< DIM:
      parity[iv] = parity[iv] xor x[i]
    parity[iv] = parity[iv] and 1

  maketable()
  echo "initialization done"

proc main() =
  if paramCount() > 0:
    beta = parseFloat(paramStr(1))
  init()
  stdout.write "lattice size ", shape[0]
  for i in 1 ..< DIM:
    stdout.write " by ", shape[i]
  echo ""
  echo " vectorlength = ", vectorlength
  echo &"group=SU({GROUP})   beta = {beta:6.4f}"
  echo "-----------------"

  echo "test monte"
  for iter in 0 ..< 5:
    let mytime = cpuTime()
    var count = 0
    for i in 0 ..< 5:
      discard monte(ulinks)
      inc count
    renorm(ulinks)
    var elapsed = cpuTime() - mytime
    elapsed = (1000000.0 / (1.0 * float64(count) * float64(nlinks))) * elapsed
    echo &"running at {elapsed:g} microseconds per link"
    discard loop(ulinks, 2, 2)

  echo "test overrelax"
  for iter in 0 ..< 5:
    let mytime = cpuTime()
    var count = 0
    for i in 0 ..< 5:
      discard overrelax(ulinks)
      inc count
    renorm(ulinks)
    var elapsed = cpuTime() - mytime
    elapsed = (1000000.0 / (1.0 * float64(count) * float64(nlinks))) * elapsed
    echo &"running at {elapsed:g} microseconds per link"

  cleanup("all done")

main()
