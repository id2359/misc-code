/* This program simulates SU(GROUP) lattice gauge fields with the
   simple Wilson action.
   Converted to Odin from Creutz's C++ puregauge.cc
*/

package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:time"
import "core:c"

GROUP :: 2
DIM :: 4
SIZE :: 8
HITS :: 10

beta: f64 = 2.3

foreign import libc "system:c"

@(default_calling_convention="c")
foreign libc {
    drand48 :: proc() -> f64 ---
    srand48 :: proc(seed: c.long) ---
}

Matrix :: struct {
    real: [GROUP][GROUP]f64,
    imag: [GROUP][GROUP]f64,
}

set_identity :: proc(m: ^Matrix, x: f64) {
    for i in 0..<GROUP {
        for j in 0..<GROUP {
            m.real[i][j] = x if i == j else 0.0
            m.imag[i][j] = 0.0
        }
    }
}

mat_mul :: proc(lhs, rhs: ^Matrix) -> Matrix {
    res: Matrix
    for i in 0..<GROUP {
        for j in 0..<GROUP {
            for k in 0..<GROUP {
                res.real[i][j] += lhs.real[i][k] * rhs.real[k][j] - lhs.imag[i][k] * rhs.imag[k][j]
                res.imag[i][j] += lhs.real[i][k] * rhs.imag[k][j] + lhs.imag[i][k] * rhs.real[k][j]
            }
        }
    }
    return res
}

conjugate :: proc(m: ^Matrix) -> Matrix {
    res: Matrix
    for i in 0..<GROUP {
        for j in 0..<GROUP {
            res.real[i][j] = m.real[j][i]
            res.imag[i][j] = -m.imag[j][i]
        }
    }
    return res
}

project :: proc(m: ^Matrix) {
    nmax := GROUP - (1 if GROUP < 4 else 0)
    for i in 0..<nmax {
        temp := m.real[i][0] * m.real[i][0] + m.imag[i][0] * m.imag[i][0]
        for j in 1..<GROUP {
            temp += m.real[i][j] * m.real[i][j] + m.imag[i][j] * m.imag[i][j]
        }
        inv_norm := 1.0 / math.sqrt(temp)
        for j in 0..<GROUP {
            m.real[i][j] *= inv_norm
            m.imag[i][j] *= inv_norm
        }
        for k in i + 1..<nmax {
            adotbr := m.real[i][0] * m.real[k][0] + m.imag[i][0] * m.imag[k][0]
            adotbi := m.real[i][0] * m.imag[k][0] - m.imag[i][0] * m.real[k][0]
            for j in 1..<GROUP {
                adotbr += m.real[i][j] * m.real[k][j] + m.imag[i][j] * m.imag[k][j]
                adotbi += m.real[i][j] * m.imag[k][j] - m.imag[i][j] * m.real[k][j]
            }
            for j in 0..<GROUP {
                m.real[k][j] -= adotbr * m.real[i][j] - adotbi * m.imag[i][j]
                m.imag[k][j] -= adotbr * m.imag[i][j] + adotbi * m.real[i][j]
            }
        }
    }
    switch GROUP {
    case 2:
        m.real[1][0] = -m.real[0][1]
        m.real[1][1] =  m.real[0][0]
        m.imag[1][0] =  m.imag[0][1]
        m.imag[1][1] = -m.imag[0][0]
    }
}

shape := [DIM]int{SIZE, SIZE, SIZE, SIZE}
shift: [DIM]int
nsites, nlinks, nplaquettes, vectorlength: int

ulinks: []Matrix
table1, table2: []Matrix
mtemp: [5][]Matrix
sold, snew: []f64
accepted, myindex, parity: []int

cleanup :: proc(msg: string) {
    fmt.println(msg)
    os.exit(0)
}

split :: proc(x: ^[DIM]int, s: int) {
    temp := s
    if temp < 0 || temp >= nsites {
        cleanup("bad split")
    }
    for i := DIM - 1; i > 0; i -= 1 {
        x[i] = 0
        for temp >= shift[i] {
            temp -= shift[i]
            x[i] += 1
        }
    }
    x[0] = temp
}

siteindex :: proc(x: ^[DIM]int) -> int {
    res := 0
    for i in 0..<DIM {
        res += shift[i] * x[i]
    }
    return res
}

vshift :: proc(n: int, x: ^[DIM]int) -> int {
    y: [DIM]int
    split(&y, n)
    for i in 0..<DIM {
        if x[i] != 0 {
            y[i] += x[i]
            for y[i] >= shape[i] { y[i] -= shape[i] }
            for y[i] < 0 { y[i] += shape[i] }
        }
    }
    return siteindex(&y)
}

ishift :: proc(n, dir, dist: int) -> int {
    x: [DIM]int
    x[dir] = dist
    return vshift(n, &x)
}

makeindex :: proc(n: int, ind: []int) {
    x: [DIM]int
    split(&x, n)
    site := 0
    for iv in 0..<vectorlength {
        for parity[site] != 0 {
            site += 1
        }
        ind[iv] = vshift(site, &x)
        site += 1
    }
}

vgroup :: proc(g: []Matrix) {
    for iv in 0..<vectorlength {
        project(&g[iv])
    }
}

vcopy :: proc(g1, g2: []Matrix) {
    for iv in 0..<vectorlength {
        g2[iv] = g1[iv]
    }
}

vprod :: proc(g1, g2, g3: []Matrix) {
    for iv in 0..<vectorlength {
        g3[iv] = mat_mul(&g1[iv], &g2[iv])
    }
}

vsum :: proc(g1, g2, g3: []Matrix) {
    for i in 0..<GROUP {
        for j in 0..<GROUP {
            for iv in 0..<vectorlength {
                g3[iv].real[i][j] = g1[iv].real[i][j] + g2[iv].real[i][j]
                g3[iv].imag[i][j] = g1[iv].imag[i][j] + g2[iv].imag[i][j]
            }
        }
    }
}

vtprod :: proc(g1, g2: []Matrix, s: []f64) {
    for iv in 0..<vectorlength {
        s[iv] = 0.0
    }
    for i in 0..<GROUP {
        for j in 0..<GROUP {
            for iv in 0..<vectorlength {
                s[iv] += g1[iv].real[i][j] * g2[iv].real[j][i] - g1[iv].imag[i][j] * g2[iv].imag[j][i]
            }
        }
    }
}

vtrace :: proc(g: []Matrix, s: []f64) {
    for iv in 0..<vectorlength {
        s[iv] = g[iv].real[0][0]
    }
    for i in 1..<GROUP {
        for iv in 0..<vectorlength {
            s[iv] += g[iv].real[i][i]
        }
    }
}

getlinks :: proc(g: []Matrix, lattice: []Matrix, site, link: int) {
    makeindex(site, myindex)
    sft := nsites * link
    for iv in 0..<vectorlength {
        g[iv] = lattice[myindex[iv] + sft]
    }
}

getconjugate :: proc(g: []Matrix, lattice: []Matrix, site, link: int) {
    makeindex(site, myindex)
    sft := nsites * link
    for iv in 0..<vectorlength {
        g[iv] = conjugate(&lattice[myindex[iv] + sft])
    }
}

savelinks :: proc(g: []Matrix, lattice: []Matrix, site, link: int) {
    makeindex(site, myindex)
    sft := nsites * link
    for iv in 0..<vectorlength {
        lattice[myindex[iv] + sft] = g[iv]
    }
}

metro :: proc(old, trial: []Matrix, bias: f64) -> f64 {
    expdeltas := 0.0
    for iv in 0..<vectorlength {
        temp := math.exp(bias * (snew[iv] - sold[iv]))
        expdeltas += temp
        accepted[iv] = 1 if drand48() < temp else 0
    }
    for iv in 0..<vectorlength {
        if accepted[iv] != 0 {
            sold[iv] = snew[iv]
            old[iv] = trial[iv]
        }
    }
    return expdeltas / f64(vectorlength)
}

ranmat :: proc(g: []Matrix) {
    idx := int(f64(vectorlength) * drand48())
    for iv in 0..<vectorlength {
        if idx >= vectorlength { idx -= vectorlength }
        if drand48() < 0.5 {
            g[iv] = table1[idx]
        } else {
            g[iv] = conjugate(&table1[idx])
        }
        idx += 1
    }
}

vtable :: proc() {
    ranmat(mtemp[0])
    vprod(table2, mtemp[0], table1)
    vtrace(table2, sold)
    vtrace(table1, snew)
    _ = metro(table2, table1, 6.0 * beta / f64(GROUP))
    vcopy(table2, table1)
    vcopy(mtemp[0], table2)
    vgroup(table1)
}

maketable :: proc() {
    for iv in 0..<vectorlength {
        temp1, temp2: Matrix
        set_identity(&temp1, beta / f64(GROUP))
        set_identity(&temp2, beta / f64(GROUP))
        for i in 0..<GROUP {
            for j in 0..<GROUP {
                temp1.real[i][j] += drand48() - 0.5
                temp1.imag[i][j] += drand48() - 0.5
                temp2.real[i][j] += drand48() - 0.5
                temp2.imag[i][j] += drand48() - 0.5
            }
        }
        table1[iv] = temp1
        table2[iv] = temp2
    }
    vgroup(table1)
    vgroup(table2)
    for i in 0..<50 {
        vtable()
    }
}

staple :: proc(st, lat: []Matrix, site, link: int) {
    for iv in 0..<vectorlength {
        set_identity(&st[iv], 0.0)
    }
    site1 := ishift(site, link, 1)
    for link1 in 0..<DIM {
        if link1 != link {
            site2 := ishift(site, link1, 1)
            site4 := ishift(site1, link1, -1)
            site5 := ishift(site, link1, -1)

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
        }
    }
}

monte :: proc(lattice: []Matrix) -> f64 {
    vtable()
    stot := 0.0
    eds := 0.0
    iacc := 0
    for color in 0..=1 {
        for link in 0..<DIM {
            staple(mtemp[4], lattice, color, link)
            getlinks(mtemp[0], lattice, color, link)
            vtprod(mtemp[0], mtemp[4], sold)
            for hit in 0..<HITS {
                ranmat(mtemp[1])
                vprod(mtemp[0], mtemp[1], mtemp[2])
                vtprod(mtemp[2], mtemp[4], snew)
                eds += metro(mtemp[0], mtemp[2], beta / f64(GROUP))
                for iv in 0..<vectorlength {
                    iacc += accepted[iv]
                    stot += sold[iv]
                }
            }
            savelinks(mtemp[0], lattice, color, link)
        }
    }
    stot = stot / (2.0 * f64(DIM - 1) * f64(nlinks) * f64(GROUP) * f64(HITS))
    acc := f64(iacc) / (f64(nlinks) * f64(HITS))
    eds = eds / (2.0 * f64(DIM) * f64(HITS))
    fmt.printf("stot=%.6f, acc=%.6f, eds=%.6f\n", stot, acc, eds)
    return stot
}

overrelax :: proc(lattice: []Matrix) -> f64 {
    if GROUP > 3 { cleanup("overrelax needs GROUP<=3 or more temporaries") }
    stot := 0.0
    eds := 0.0
    iacc := 0
    for color in 0..=1 {
        for link in 0..<DIM {
            staple(mtemp[4], lattice, color, link)
            getlinks(mtemp[0], lattice, color, link)
            vcopy(mtemp[4], mtemp[1])
            vgroup(mtemp[1])
            vprod(mtemp[0], mtemp[1], mtemp[2])
            vprod(mtemp[1], mtemp[2], mtemp[3])
            for iv in 0..<vectorlength {
                mtemp[2][iv] = conjugate(&mtemp[3][iv])
            }
            vtprod(mtemp[0], mtemp[4], sold)
            vtprod(mtemp[2], mtemp[4], snew)
            eds += metro(mtemp[0], mtemp[2], beta / f64(GROUP))
            for iv in 0..<vectorlength {
                iacc += accepted[iv]
                stot += sold[iv]
            }
            savelinks(mtemp[0], lattice, color, link)
        }
    }
    stot = stot / (2.0 * f64(DIM - 1) * f64(nlinks) * f64(GROUP))
    acc := f64(iacc) / f64(nlinks)
    eds = eds / (2.0 * f64(DIM))
    fmt.printf("stot=%f, acc=%f, eds=%f\n", stot, acc, eds)
    return stot
}

renorm :: proc(l: []Matrix) {
    for octant in 0..<2 * DIM {
        link := octant * vectorlength
        for iv in 0..<vectorlength {
            project(&l[link + iv])
        }
    }
}

loop :: proc(u: []Matrix, x, y: int) -> f64 {
    count := 0
    result := 0.0
    for color in 0..=1 {
        for link1 in 0..<DIM {
            start_link2 := link1 + 1 if x == y else 0
            for link2 in start_link2..<DIM {
                if link1 != link2 {
                    count += 1
                    corner := ishift(color, link1, x)
                    corner = ishift(corner, link2, y)
                    for iv in 0..<vectorlength {
                        set_identity(&mtemp[0][iv], 1.0)
                        set_identity(&mtemp[1][iv], 1.0)
                        set_identity(&mtemp[2][iv], 1.0)
                        set_identity(&mtemp[3][iv], 1.0)
                    }
                    for i in 0..<x {
                        getlinks(mtemp[4], u, ishift(color, link1, i), link1)
                        vprod(mtemp[0], mtemp[4], mtemp[0])
                        getconjugate(mtemp[4], u, ishift(corner, link1, -i - 1), link1)
                        vprod(mtemp[2], mtemp[4], mtemp[2])
                    }
                    for i in 0..<y {
                        getlinks(mtemp[4], u, ishift(corner, link2, i - y), link2)
                        vprod(mtemp[1], mtemp[4], mtemp[1])
                        getconjugate(mtemp[4], u, ishift(color, link2, y - i - 1), link2)
                        vprod(mtemp[3], mtemp[4], mtemp[3])
                    }
                    vprod(mtemp[0], mtemp[1], mtemp[0])
                    vprod(mtemp[0], mtemp[2], mtemp[0])
                    vtprod(mtemp[0], mtemp[3], sold)
                    for iv in 0..<vectorlength {
                        result += sold[iv]
                    }
                }
            }
        }
    }
    result = result / (f64(GROUP) * f64(vectorlength) * f64(count))
    fmt.printf(" %d by %d loop = %g\n", x, y, result)
    return result
}

init_sim :: proc() {
    srand48(1234)
    nsites = 1
    for i in 0..<DIM {
        nsites *= shape[i]
        if (shape[i] & 1) != 0 { cleanup("bad dimensions") }
    }
    nlinks = DIM * nsites
    nplaquettes = DIM * (DIM - 1) * nsites / 2
    vectorlength = nsites / 2

    ulinks = make([]Matrix, nlinks)
    parity = make([]int, nsites)
    table1 = make([]Matrix, vectorlength)
    table2 = make([]Matrix, vectorlength)
    for i in 0..<5 {
        mtemp[i] = make([]Matrix, vectorlength)
    }
    sold = make([]f64, vectorlength)
    snew = make([]f64, vectorlength)
    accepted = make([]int, vectorlength)
    myindex = make([]int, vectorlength)

    shift[0] = 1
    for i in 1..<DIM {
        shift[i] = shift[i - 1] * shape[i - 1]
    }
    for iv in 0..<nlinks {
        set_identity(&ulinks[iv], 1.0)
    }

    x: [DIM]int
    for iv in 0..<nsites {
        split(&x, iv)
        parity[iv] = 0
        for i in 0..<DIM {
            parity[iv] ~= x[i]
        }
        parity[iv] &= 1
    }
    maketable()
    fmt.println("initialization done")
}

main :: proc() {
    if len(os.args) > 1 {
        val, ok := strconv.parse_f64(os.args[1])
        if ok { beta = val }
    }
    init_sim()
    fmt.printf("lattice size %d", shape[0])
    for i in 1..<DIM {
        fmt.printf(" by %d", shape[i])
    }
    fmt.printf("\n vectorlength = %d\n", vectorlength)
    fmt.printf("group=SU(%d)   beta = %6.4f\n", GROUP, beta)
    fmt.println("-----------------")

    fmt.println("test monte")
    for iter in 0..<5 {
        start_time := time.now()
        count := 0
        for i in 0..<5 {
            monte(ulinks)
            count += 1
        }
        renorm(ulinks)
        elapsed := time.duration_seconds(time.since(start_time))
        microsec := (1000000.0 / (f64(count) * f64(nlinks))) * elapsed
        fmt.printf("running at %g microseconds per link\n", microsec)
        loop(ulinks, 2, 2)
    }

    fmt.println("test overrelax")
    for iter in 0..<5 {
        start_time := time.now()
        count := 0
        for i in 0..<5 {
            overrelax(ulinks)
            count += 1
        }
        renorm(ulinks)
        elapsed := time.duration_seconds(time.since(start_time))
        microsec := (1000000.0 / (f64(count) * f64(nlinks))) * elapsed
        fmt.printf("running at %g microseconds per link\n", microsec)
    }
    cleanup("all done")
}
