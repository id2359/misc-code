# This program simulates SU(GROUP) lattice gauge fields with the
# simple Wilson action.
# Converted to Raku from Creutz's C++ puregauge.cc

use v6;

constant GROUP = 2;
constant DIM = 4;
constant SIZE = 8;
constant HITS = 10;

my num $beta = 2.3e0;

class Matrix {
    has num @.real[GROUP; GROUP];
    has num @.imag[GROUP; GROUP];

    method set-identity(num $x) {
        loop (my int $i = 0; $i < GROUP; $i++) {
            loop (my int $j = 0; $j < GROUP; $j++) {
                @!real[$i;$j] = $i == $j ?? $x !! 0.0e0;
                @!imag[$i;$j] = 0.0e0;
            }
        }
    }

    method copy-from(Matrix $src) {
        loop (my int $i = 0; $i < GROUP; $i++) {
            loop (my int $j = 0; $j < GROUP; $j++) {
                @!real[$i;$j] = $src.real[$i;$j];
                @!imag[$i;$j] = $src.imag[$i;$j];
            }
        }
    }

    method conjugate-from(Matrix $src) {
        loop (my int $i = 0; $i < GROUP; $i++) {
            loop (my int $j = 0; $j < GROUP; $j++) {
                @!real[$i;$j] = $src.real[$j;$i];
                @!imag[$i;$j] = -$src.imag[$j;$i];
            }
        }
    }

    method project() {
        my num $norm = sqrt(@!real[0;0] * @!real[0;0] + @!imag[0;0] * @!imag[0;0] + @!real[0;1] * @!real[0;1] + @!imag[0;1] * @!imag[0;1]);
        my num $inv = 1.0e0 / $norm;
        @!real[0;0] *= $inv;
        @!imag[0;0] *= $inv;
        @!real[0;1] *= $inv;
        @!imag[0;1] *= $inv;

        if GROUP == 2 {
            @!real[1;0] = -@!real[0;1];
            @!real[1;1] =  @!real[0;0];
            @!imag[1;0] =  @!imag[0;1];
            @!imag[1;1] = -@!imag[0;0];
        }
    }
}

sub mat-mul(Matrix $lhs, Matrix $rhs, Matrix $res) {
    my num $r00 = $lhs.real[0;0] * $rhs.real[0;0] - $lhs.imag[0;0] * $rhs.imag[0;0] + $lhs.real[0;1] * $rhs.real[1;0] - $lhs.imag[0;1] * $rhs.imag[1;0];
    my num $i00 = $lhs.real[0;0] * $rhs.imag[0;0] + $lhs.imag[0;0] * $rhs.real[0;0] + $lhs.real[0;1] * $rhs.imag[1;0] + $lhs.imag[0;1] * $rhs.real[1;0];
    my num $r01 = $lhs.real[0;0] * $rhs.real[0;1] - $lhs.imag[0;0] * $rhs.imag[0;1] + $lhs.real[0;1] * $rhs.real[1;1] - $lhs.imag[0;1] * $rhs.imag[1;1];
    my num $i01 = $lhs.real[0;0] * $rhs.imag[0;1] + $lhs.imag[0;0] * $rhs.real[0;1] + $lhs.real[0;1] * $rhs.imag[1;1] + $lhs.imag[0;1] * $rhs.real[1;1];
    my num $r10 = $lhs.real[1;0] * $rhs.real[0;0] - $lhs.imag[1;0] * $rhs.imag[0;0] + $lhs.real[1;1] * $rhs.real[1;0] - $lhs.imag[1;1] * $rhs.imag[1;0];
    my num $i10 = $lhs.real[1;0] * $rhs.imag[0;0] + $lhs.imag[1;0] * $rhs.real[0;0] + $lhs.real[1;1] * $rhs.imag[1;0] + $lhs.imag[1;1] * $rhs.real[1;0];
    my num $r11 = $lhs.real[1;0] * $rhs.real[0;1] - $lhs.imag[1;0] * $rhs.imag[0;1] + $lhs.real[1;1] * $rhs.real[1;1] - $lhs.imag[1;1] * $rhs.imag[1;1];
    my num $i11 = $lhs.real[1;0] * $rhs.imag[0;1] + $lhs.imag[1;0] * $rhs.real[0;1] + $lhs.real[1;1] * $rhs.imag[1;1] + $lhs.imag[1;1] * $rhs.real[1;1];

    $res.real[0;0] = $r00; $res.imag[0;0] = $i00;
    $res.real[0;1] = $r01; $res.imag[0;1] = $i01;
    $res.real[1;0] = $r10; $res.imag[1;0] = $i10;
    $res.real[1;1] = $r11; $res.imag[1;1] = $i11;
}

sub mat-add(Matrix $lhs, Matrix $rhs, Matrix $res) {
    loop (my int $i = 0; $i < GROUP; $i++) {
        loop (my int $j = 0; $j < GROUP; $j++) {
            $res.real[$i;$j] = $lhs.real[$i;$j] + $rhs.real[$i;$j];
            $res.imag[$i;$j] = $lhs.imag[$i;$j] + $rhs.imag[$i;$j];
        }
    }
}

# Linear Congruential Generator matching drand48
my Int $rng-state = 0x04D2330E; # srand48(1234) => (1234 << 16) | 0x330E

sub srand48(Int $seed) {
    $rng-state = ($seed +< 16) +| 0x330E;
}

sub drand48() returns num {
    $rng-state = ($rng-state * 0x5DEECE66D + 0xB) +& 0xFFFFFFFFFFFF;
    return $rng-state.Num / 281474976710656.0e0;
}

my @shape = [SIZE, SIZE, SIZE, SIZE];
my @shift = [0, 0, 0, 0];
my int $nsites = SIZE * SIZE * SIZE * SIZE;
my int $nlinks = DIM * $nsites;
my int $vectorlength = $nsites div 2;

my @ulinks = (0 ..^ $nlinks).map: { Matrix.new };
my int @parity = 0 xx $nsites;
my @table1 = (0 ..^ $vectorlength).map: { Matrix.new };
my @table2 = (0 ..^ $vectorlength).map: { Matrix.new };
my @mtemp = (0 ..^ 5).map: { (0 ..^ $vectorlength).map: { Matrix.new } };
my num @sold = 0.0e0 xx $vectorlength;
my num @snew = 0.0e0 xx $vectorlength;
my int @accepted = 0 xx $vectorlength;
my int @myindex = 0 xx $vectorlength;

sub split-coords(int $s, @x) {
    my int $temp = $s;
    loop (my int $i = DIM - 1; $i > 0; $i--) {
        @x[$i] = 0;
        while $temp >= @shift[$i] {
            $temp -= @shift[$i];
            @x[$i]++;
        }
    }
    @x[0] = $temp;
}

sub siteindex(@x) returns int {
    my int $res = 0;
    loop (my int $i = 0; $i < DIM; $i++) {
        $res += @shift[$i] * @x[$i];
    }
    return $res;
}

sub vshift(int $n, @x) returns int {
    my @y = 0, 0, 0, 0;
    split-coords($n, @y);
    loop (my int $i = 0; $i < DIM; $i++) {
        if @x[$i] != 0 {
            @y[$i] += @x[$i];
            while @y[$i] >= @shape[$i] { @y[$i] -= @shape[$i]; }
            while @y[$i] < 0 { @y[$i] += @shape[$i]; }
        }
    }
    return siteindex(@y);
}

sub ishift(int $n, int $dir, int $dist) returns int {
    my @x = 0, 0, 0, 0;
    @x[$dir] = $dist;
    return vshift($n, @x);
}

sub makeindex(int $n, @ind) {
    my @x = 0, 0, 0, 0;
    split-coords($n, @x);
    my int $site = 0;
    loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
        while @parity[$site] != 0 { $site++; }
        @ind[$iv] = vshift($site, @x);
        $site++;
    }
}

sub vgroup(@g) {
    loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
        @g[$iv].project();
    }
}

sub vcopy(@g1, @g2) {
    loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
        @g2[$iv].copy-from(@g1[$iv]);
    }
}

sub vprod(@g1, @g2, @g3) {
    loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
        mat-mul(@g1[$iv], @g2[$iv], @g3[$iv]);
    }
}

sub vsum(@g1, @g2, @g3) {
    loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
        mat-add(@g1[$iv], @g2[$iv], @g3[$iv]);
    }
}

sub vtprod(@g1, @g2, @s) {
    loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
        my $m1 = @g1[$iv];
        my $m2 = @g2[$iv];
        @s[$iv] = ($m1.real[0;0]*$m2.real[0;0] - $m1.imag[0;0]*$m2.imag[0;0]) +
                  ($m1.real[0;1]*$m2.real[1;0] - $m1.imag[0;1]*$m2.imag[1;0]) +
                  ($m1.real[1;0]*$m2.real[0;1] - $m1.imag[1;0]*$m2.imag[0;1]) +
                  ($m1.real[1;1]*$m2.real[1;1] - $m1.imag[1;1]*$m2.imag[1;1]);
    }
}

sub vtrace(@g, @s) {
    loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
        @s[$iv] = @g[$iv].real[0;0] + @g[$iv].real[1;1];
    }
}

sub getlinks(@g, @lat, int $site, int $link) {
    makeindex($site, @myindex);
    my int $sft = $nsites * $link;
    loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
        @g[$iv].copy-from(@lat[@myindex[$iv] + $sft]);
    }
}

sub getconjugate(@g, @lat, int $site, int $link) {
    makeindex($site, @myindex);
    my int $sft = $nsites * $link;
    loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
        @g[$iv].conjugate-from(@lat[@myindex[$iv] + $sft]);
    }
}

sub savelinks(@g, @lat, int $site, int $link) {
    makeindex($site, @myindex);
    my int $sft = $nsites * $link;
    loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
        @lat[@myindex[$iv] + $sft].copy-from(@g[$iv]);
    }
}

sub metro(@old, @trial, num $bias) returns num {
    my num $expdeltas = 0.0e0;
    loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
        my num $temp = exp($bias * (@snew[$iv] - @sold[$iv]));
        $expdeltas += $temp;
        @accepted[$iv] = drand48() < $temp ?? 1 !! 0;
    }
    loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
        if @accepted[$iv] != 0 {
            @sold[$iv] = @snew[$iv];
            @old[$iv].copy-from(@trial[$iv]);
        }
    }
    return $expdeltas / $vectorlength.Num;
}

sub ranmat(@g) {
    my int $idx = (drand48() * $vectorlength).Int;
    loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
        if $idx >= $vectorlength { $idx -= $vectorlength; }
        if drand48() < 0.5e0 {
            @g[$iv].copy-from(@table1[$idx]);
        } else {
            @g[$iv].conjugate-from(@table1[$idx]);
        }
        $idx++;
    }
}

sub vtable() {
    ranmat(@mtemp[0]);
    vprod(@table2, @mtemp[0], @table1);
    vtrace(@table2, @sold);
    vtrace(@table1, @snew);
    metro(@table2, @table1, 6.0e0 * $beta / GROUP.Num);
    vcopy(@table2, @table1);
    vcopy(@mtemp[0], @table2);
    vgroup(@table1);
}

sub maketable() {
    my $t1 = Matrix.new;
    my $t2 = Matrix.new;
    loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
        $t1.set-identity($beta / GROUP.Num);
        $t2.set-identity($beta / GROUP.Num);
        loop (my int $i = 0; $i < GROUP; $i++) {
            loop (my int $j = 0; $j < GROUP; $j++) {
                $t1.real[$i;$j] += drand48() - 0.5e0;
                $t1.imag[$i;$j] += drand48() - 0.5e0;
                $t2.real[$i;$j] += drand48() - 0.5e0;
                $t2.imag[$i;$j] += drand48() - 0.5e0;
            }
        }
        @table1[$iv].copy-from($t1);
        @table2[$iv].copy-from($t2);
    }
    vgroup(@table1);
    vgroup(@table2);
    loop (my int $i = 0; $i < 50; $i++) {
        vtable();
    }
}

sub staple(@st, @lat, int $site, int $link) {
    loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
        @st[$iv].set-identity(0.0e0);
    }
    my int $site1 = ishift($site, $link, 1);
    loop (my int $link1 = 0; $link1 < DIM; $link1++) {
        if $link1 != $link {
            my int $site2 = ishift($site, $link1, 1);
            my int $site4 = ishift($site1, $link1, -1);
            my int $site5 = ishift($site, $link1, -1);

            getlinks(@mtemp[0], @lat, $site1, $link1);
            getconjugate(@mtemp[1], @lat, $site2, $link);
            vprod(@mtemp[0], @mtemp[1], @mtemp[2]);
            getconjugate(@mtemp[0], @lat, $site, $link1);
            vprod(@mtemp[2], @mtemp[0], @mtemp[1]);
            vsum(@st, @mtemp[1], @st);

            getconjugate(@mtemp[0], @lat, $site4, $link1);
            getconjugate(@mtemp[1], @lat, $site5, $link);
            vprod(@mtemp[0], @mtemp[1], @mtemp[2]);
            getlinks(@mtemp[0], @lat, $site5, $link1);
            vprod(@mtemp[2], @mtemp[0], @mtemp[1]);
            vsum(@st, @mtemp[1], @st);
        }
    }
}

sub monte(@lat) returns num {
    vtable();
    my num $stot = 0.0e0;
    my num $eds = 0.0e0;
    my int $iacc = 0;
    loop (my int $color = 0; $color < 2; $color++) {
        loop (my int $link = 0; $link < DIM; $link++) {
            staple(@mtemp[4], @lat, $color, $link);
            getlinks(@mtemp[0], @lat, $color, $link);
            vtprod(@mtemp[0], @mtemp[4], @sold);
            loop (my int $hit = 0; $hit < HITS; $hit++) {
                ranmat(@mtemp[1]);
                vprod(@mtemp[0], @mtemp[1], @mtemp[2]);
                vtprod(@mtemp[2], @mtemp[4], @snew);
                $eds += metro(@mtemp[0], @mtemp[2], $beta / GROUP.Num);
                loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
                    $iacc += @accepted[$iv];
                    $stot += @sold[$iv];
                }
            }
            savelinks(@mtemp[0], @lat, $color, $link);
        }
    }
    $stot = $stot / (2.0e0 * (DIM - 1).Num * $nlinks.Num * GROUP.Num * HITS.Num);
    my num $acc = $iacc.Num / ($nlinks.Num * HITS.Num);
    $eds = $eds / (2.0e0 * DIM.Num * HITS.Num);
    printf("stot=%.6f, acc=%.6f, eds=%.6f\n", $stot, $acc, $eds);
    return $stot;
}

sub overrelax(@lat) returns num {
    my num $stot = 0.0e0;
    my num $eds = 0.0e0;
    my int $iacc = 0;
    loop (my int $color = 0; $color < 2; $color++) {
        loop (my int $link = 0; $link < DIM; $link++) {
            staple(@mtemp[4], @lat, $color, $link);
            getlinks(@mtemp[0], @lat, $color, $link);
            vcopy(@mtemp[4], @mtemp[1]);
            vgroup(@mtemp[1]);
            vprod(@mtemp[0], @mtemp[1], @mtemp[2]);
            vprod(@mtemp[1], @mtemp[2], @mtemp[3]);
            loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
                @mtemp[2][$iv].conjugate-from(@mtemp[3][$iv]);
            }
            vtprod(@mtemp[0], @mtemp[4], @sold);
            vtprod(@mtemp[2], @mtemp[4], @snew);
            $eds += metro(@mtemp[0], @mtemp[2], $beta / GROUP.Num);
            loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
                $iacc += @accepted[$iv];
                $stot += @sold[$iv];
            }
            savelinks(@mtemp[0], @lat, $color, $link);
        }
    }
    $stot = $stot / (2.0e0 * (DIM - 1).Num * $nlinks.Num * GROUP.Num);
    my num $acc = $iacc.Num / $nlinks.Num;
    $eds = $eds / (2.0e0 * DIM.Num);
    printf("stot=%.6f, acc=%.6f, eds=%.6f\n", $stot, $acc, $eds);
    return $stot;
}

sub renorm(@lat) {
    loop (my int $octant = 0; $octant < 2 * DIM; $octant++) {
        my int $link = $octant * $vectorlength;
        loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
            @lat[$link + $iv].project();
        }
    }
}

sub wilson-loop(@u, int $x, int $y) returns num {
    my int $count = 0;
    my num $result = 0.0e0;
    loop (my int $color = 0; $color < 2; $color++) {
        loop (my int $link1 = 0; $link1 < DIM; $link1++) {
            my int $start-link2 = $x == $y ?? $link1 + 1 !! 0;
            loop (my int $link2 = $start-link2; $link2 < DIM; $link2++) {
                if $link1 != $link2 {
                    $count++;
                    my int $corner = ishift($color, $link1, $x);
                    $corner = ishift($corner, $link2, $y);
                    loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
                        @mtemp[0][$iv].set-identity(1.0e0);
                        @mtemp[1][$iv].set-identity(1.0e0);
                        @mtemp[2][$iv].set-identity(1.0e0);
                        @mtemp[3][$iv].set-identity(1.0e0);
                    }
                    loop (my int $i = 0; $i < $x; $i++) {
                        getlinks(@mtemp[4], @u, ishift($color, $link1, $i), $link1);
                        vprod(@mtemp[0], @mtemp[4], @mtemp[0]);
                        getconjugate(@mtemp[4], @u, ishift($corner, $link1, -$i - 1), $link1);
                        vprod(@mtemp[2], @mtemp[4], @mtemp[2]);
                    }
                    loop (my int $i = 0; $i < $y; $i++) {
                        getlinks(@mtemp[4], @u, ishift($corner, $link2, $i - $y), $link2);
                        vprod(@mtemp[1], @mtemp[4], @mtemp[1]);
                        getconjugate(@mtemp[4], @u, ishift($color, $link2, $y - $i - 1), $link2);
                        vprod(@mtemp[3], @mtemp[4], @mtemp[3]);
                    }
                    vprod(@mtemp[0], @mtemp[1], @mtemp[0]);
                    vprod(@mtemp[0], @mtemp[2], @mtemp[0]);
                    vtprod(@mtemp[0], @mtemp[3], @sold);
                    loop (my int $iv = 0; $iv < $vectorlength; $iv++) {
                        $result += @sold[$iv];
                    }
                }
            }
        }
    }
    $result = $result / (GROUP.Num * $vectorlength.Num * $count.Num);
    printf(" %d by %d loop = %g\n", $x, $y, $result);
    return $result;
}

sub MAIN($arg-beta?) {
    if $arg-beta.defined {
        $beta = $arg-beta.Num;
    }
    srand48(1234);

    @shift[0] = 1;
    loop (my int $i = 1; $i < DIM; $i++) {
        @shift[$i] = @shift[$i - 1] * @shape[$i - 1];
    }
    loop (my int $iv = 0; $iv < $nlinks; $iv++) {
        @ulinks[$iv].set-identity(1.0e0);
    }
    my @coords = 0, 0, 0, 0;
    loop (my int $iv = 0; $iv < $nsites; $iv++) {
        split-coords($iv, @coords);
        @parity[$iv] = 0;
        loop (my int $i = 0; $i < DIM; $i++) {
            @parity[$iv] = @parity[$iv] +^ @coords[$i];
        }
        @parity[$iv] = @parity[$iv] +& 1;
    }

    maketable();
    say "initialization done";
    print "lattice size ", @shape[0];
    loop (my int $i = 1; $i < DIM; $i++) {
        print " by ", @shape[$i];
    }
    say "";
    say " vectorlength = ", $vectorlength;
    printf("group=SU(%d)   beta = %6.4f\n", GROUP, $beta);
    say "-----------------";

    say "test monte";
    loop (my int $iter = 0; $iter < 5; $iter++) {
        my $t0 = now;
        my int $count = 0;
        loop (my int $i = 0; $i < 5; $i++) {
            monte(@ulinks);
            $count++;
        }
        renorm(@ulinks);
        my $elapsed = now - $t0;
        my num $microsec = (1000000.0e0 / ($count.Num * $nlinks.Num)) * $elapsed.Num;
        printf("running at %g microseconds per link\n", $microsec);
        wilson-loop(@ulinks, 2, 2);
    }

    say "test overrelax";
    loop (my int $iter = 0; $iter < 5; $iter++) {
        my $t0 = now;
        my int $count = 0;
        loop (my int $i = 0; $i < 5; $i++) {
            overrelax(@ulinks);
            $count++;
        }
        renorm(@ulinks);
        my $elapsed = now - $t0;
        my num $microsec = (1000000.0e0 / ($count.Num * $nlinks.Num)) * $elapsed.Num;
        printf("running at %g microseconds per link\n", $microsec);
    }

    say "all done";
}
