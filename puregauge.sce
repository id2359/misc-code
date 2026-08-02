// This program simulates SU(GROUP) lattice gauge fields with the
// simple Wilson action.
// Converted to Scilab from Creutz's C++ puregauge.cc

GROUP = 2;
DIM = 4;
SIZE = 8;
HITS = 10;
beta_val = 2.3;

nsites = SIZE^4;
nlinks = DIM * nsites;
vectorlength = nsites / 2;

shape_arr = [SIZE, SIZE, SIZE, SIZE];
shift_arr = [1, 8, 64, 512];

global RNG_STATE;
RNG_STATE = 80880398;

function srand48_sci(seed)
    global RNG_STATE;
    RNG_STATE = pmodulo(13070 + seed * 65536, 281474976710656);
endfunction

function r = drand48_sci()
    global RNG_STATE;
    a = 25214903917;
    c = 11;
    m = 281474976710656;
    RNG_STATE = pmodulo(a * RNG_STATE + c, m);
    r = RNG_STATE / m;
endfunction

function r_vec = drand48_sci_vec(n)
    global RNG_STATE;
    a = 25214903917;
    c = 11;
    m = 281474976710656;
    r_vec = zeros(n, 1);
    st = RNG_STATE;
    for k = 1:n
        st = pmodulo(a * st + c, m);
        r_vec(k) = st / m;
    end
    RNG_STATE = st;
endfunction

// Precompute parity and even sites (0-indexed indices)
all_sites = (0:nsites-1)';
x3 = floor(all_sites / 512);
rem3 = pmodulo(all_sites, 512);
x2 = floor(rem3 / 64);
rem2 = pmodulo(rem3, 64);
x1 = floor(rem2 / 8);
x0 = pmodulo(rem2, 8);

parity_arr = pmodulo(x0 + x1 + x2 + x3, 2);
even_sites = all_sites(parity_arr == 0);

// Global link lattice stored as 4 complex vectors of length nlinks
global u00 u01 u10 u11;
u00 = ones(nlinks, 1);
u01 = zeros(nlinks, 1);
u10 = zeros(nlinks, 1);
u11 = ones(nlinks, 1);

// Global tables for random matrices
global t1_00 t1_01 t1_10 t1_11;
global t2_00 t2_01 t2_10 t2_11;
t1_00 = ones(vectorlength, 1); t1_01 = zeros(vectorlength, 1);
t1_10 = zeros(vectorlength, 1); t1_11 = ones(vectorlength, 1);
t2_00 = ones(vectorlength, 1); t2_01 = zeros(vectorlength, 1);
t2_10 = zeros(vectorlength, 1); t2_11 = ones(vectorlength, 1);

// Temps
global sold_arr snew_arr accepted_arr;
sold_arr = zeros(vectorlength, 1);
snew_arr = zeros(vectorlength, 1);
accepted_arr = zeros(vectorlength, 1);

function [c00, c01, c10, c11] = vmat_mul(a00, a01, a10, a11, b00, b01, b10, b11)
    c00 = a00 .* b00 + a01 .* b10;
    c01 = a00 .* b01 + a01 .* b11;
    c10 = a10 .* b00 + a11 .* b10;
    c11 = a10 .* b01 + a11 .* b11;
endfunction

function [c00, c01, c10, c11] = vmat_add(a00, a01, a10, a11, b00, b01, b10, b11)
    c00 = a00 + b00;
    c01 = a01 + b01;
    c10 = a10 + b10;
    c11 = a11 + b11;
endfunction

function [c00, c01, c10, c11] = vmat_conj(a00, a01, a10, a11)
    c00 = conj(a00);
    c01 = conj(a10);
    c10 = conj(a01);
    c11 = conj(a11);
endfunction

function [c00, c01, c10, c11] = vmat_project(a00, a01, a10, a11)
    norm_v = sqrt(abs(a00).^2 + abs(a01).^2);
    inv_norm = 1.0 ./ norm_v;
    c00 = a00 .* inv_norm;
    c01 = a01 .* inv_norm;
    c10 = -conj(c01);
    c11 = conj(c00);
endfunction

function res = vtprod_vec(a00, a01, a10, a11, b00, b01, b10, b11)
    res = real(a00 .* b00 + a01 .* b10 + a10 .* b01 + a11 .* b11);
endfunction

function res = vtrace_vec(a00, a01, a10, a11)
    res = real(a00 + a11);
endfunction

function ind_1based = makeindex_sci(n)
    n_x3 = floor(n / 512);
    rem3_n = pmodulo(n, 512);
    n_x2 = floor(rem3_n / 64);
    rem2_n = pmodulo(rem3_n, 64);
    n_x1 = floor(rem2_n / 8);
    n_x0 = pmodulo(rem2_n, 8);

    ev_x3 = floor(even_sites / 512);
    ev_rem3 = pmodulo(even_sites, 512);
    ev_x2 = floor(ev_rem3 / 64);
    ev_rem2 = pmodulo(ev_rem3, 64);
    ev_x1 = floor(ev_rem2 / 8);
    ev_x0 = pmodulo(ev_rem2, 8);

    y0 = pmodulo(ev_x0 + n_x0, 8);
    y1 = pmodulo(ev_x1 + n_x1, 8);
    y2 = pmodulo(ev_x2 + n_x2, 8);
    y3 = pmodulo(ev_x3 + n_x3, 8);

    ind_0based = y0 + 8 * y1 + 64 * y2 + 512 * y3;
    ind_1based = ind_0based + 1;
endfunction

function s_idx = ishift_sci(n, dir_idx, dist)
    n_x3 = floor(n / 512);
    rem3_n = pmodulo(n, 512);
    n_x2 = floor(rem3_n / 64);
    rem2_n = pmodulo(rem3_n, 64);
    n_x1 = floor(rem2_n / 8);
    n_x0 = pmodulo(rem2_n, 8);

    if dir_idx == 0 then n_x0 = pmodulo(n_x0 + dist, 8); end
    if dir_idx == 1 then n_x1 = pmodulo(n_x1 + dist, 8); end
    if dir_idx == 2 then n_x2 = pmodulo(n_x2 + dist, 8); end
    if dir_idx == 3 then n_x3 = pmodulo(n_x3 + dist, 8); end

    s_idx = n_x0 + 8 * n_x1 + 64 * n_x2 + 512 * n_x3;
endfunction

function [g00, g01, g10, g11] = getlinks_sci(site, link_idx)
    global u00 u01 u10 u11;
    ind = makeindex_sci(site) + nsites * link_idx;
    g00 = u00(ind);
    g01 = u01(ind);
    g10 = u10(ind);
    g11 = u11(ind);
endfunction

function [g00, g01, g10, g11] = getconjugate_sci(site, link_idx)
    global u00 u01 u10 u11;
    ind = makeindex_sci(site) + nsites * link_idx;
    [g00, g01, g10, g11] = vmat_conj(u00(ind), u01(ind), u10(ind), u11(ind));
endfunction

function savelinks_sci(g00, g01, g10, g11, site, link_idx)
    global u00 u01 u10 u11;
    ind = makeindex_sci(site) + nsites * link_idx;
    u00(ind) = g00;
    u01(ind) = g01;
    u10(ind) = g10;
    u11(ind) = g11;
endfunction

function [expdeltas, o00, o01, o10, o11] = metro_sci(o00, o01, o10, o11, t00, t01, t10, t11, bias)
    global sold_arr snew_arr accepted_arr;
    temp = exp(bias * (snew_arr - sold_arr));
    expdeltas = sum(temp) / vectorlength;

    r_vals = drand48_sci_vec(vectorlength);
    accepted_arr = (r_vals < temp);

    acc_idx = find(accepted_arr);
    if ~isempty(acc_idx) then
        sold_arr(acc_idx) = snew_arr(acc_idx);
        o00(acc_idx) = t00(acc_idx);
        o01(acc_idx) = t01(acc_idx);
        o10(acc_idx) = t10(acc_idx);
        o11(acc_idx) = t11(acc_idx);
    end
endfunction

function [g00, g01, g10, g11] = ranmat_sci()
    global t1_00 t1_01 t1_10 t1_11;
    r_start = drand48_sci();
    idx_start = floor(vectorlength * r_start) + 1;
    indices = pmodulo((idx_start-1 : idx_start+vectorlength-2)', vectorlength) + 1;

    r_choices = drand48_sci_vec(vectorlength);
    use_t1 = (r_choices < 0.5);

    [conj_t1_00, conj_t1_01, conj_t1_10, conj_t1_11] = vmat_conj(t1_00(indices), t1_01(indices), t1_10(indices), t1_11(indices));

    t1_sel_00 = t1_00(indices);
    t1_sel_01 = t1_01(indices);
    t1_sel_10 = t1_10(indices);
    t1_sel_11 = t1_11(indices);

    g00 = use_t1 .* t1_sel_00 + (~use_t1) .* conj_t1_00;
    g01 = use_t1 .* t1_sel_01 + (~use_t1) .* conj_t1_01;
    g10 = use_t1 .* t1_sel_10 + (~use_t1) .* conj_t1_10;
    g11 = use_t1 .* t1_sel_11 + (~use_t1) .* conj_t1_11;
endfunction

function vtable_sci()
    global t1_00 t1_01 t1_10 t1_11;
    global t2_00 t2_01 t2_10 t2_11;
    global sold_arr snew_arr;

    [m0_00, m0_01, m0_10, m0_11] = ranmat_sci();
    [tb1_00, tb1_01, tb1_10, tb1_11] = vmat_mul(t2_00, t2_01, t2_10, t2_11, m0_00, m0_01, m0_10, m0_11);

    sold_arr = vtrace_vec(t2_00, t2_01, t2_10, t2_11);
    snew_arr = vtrace_vec(tb1_00, tb1_01, tb1_10, tb1_11);

    [ed, t2_00, t2_01, t2_10, t2_11] = metro_sci(t2_00, t2_01, t2_10, t2_11, tb1_00, tb1_01, tb1_10, tb1_11, 6.0 * beta_val / GROUP);

    t1_00 = t2_00; t1_01 = t2_01; t1_10 = t2_10; t1_11 = t2_11;
    t2_00 = m0_00; t2_01 = m0_01; t2_10 = m0_10; t2_11 = m0_11;

    [t1_00, t1_01, t1_10, t1_11] = vmat_project(t1_00, t1_01, t1_10, t1_11);
endfunction

function maketable_sci()
    global t1_00 t1_01 t1_10 t1_11;
    global t2_00 t2_01 t2_10 t2_11;
    b = beta_val / GROUP;

    r = drand48_sci_vec(vectorlength * 16);
    r1 = r(1:vectorlength);
    r2 = r(vectorlength+1:2*vectorlength);
    r3 = r(2*vectorlength+1:3*vectorlength);
    r4 = r(3*vectorlength+1:4*vectorlength);
    r5 = r(4*vectorlength+1:5*vectorlength);
    r6 = r(5*vectorlength+1:6*vectorlength);
    r7 = r(6*vectorlength+1:7*vectorlength);
    r8 = r(7*vectorlength+1:8*vectorlength);

    q1 = r(8*vectorlength+1:9*vectorlength);
    q2 = r(9*vectorlength+1:10*vectorlength);
    q3 = r(10*vectorlength+1:11*vectorlength);
    q4 = r(11*vectorlength+1:12*vectorlength);
    q5 = r(12*vectorlength+1:13*vectorlength);
    q6 = r(13*vectorlength+1:14*vectorlength);
    q7 = r(14*vectorlength+1:15*vectorlength);
    q8 = r(15*vectorlength+1:16*vectorlength);

    t1_00 = (b + r1 - 0.5) + %i * (r5 - 0.5);
    t1_01 = (r2 - 0.5) + %i * (r6 - 0.5);
    t1_10 = (r3 - 0.5) + %i * (r7 - 0.5);
    t1_11 = (b + r4 - 0.5) + %i * (r8 - 0.5);

    t2_00 = (b + q1 - 0.5) + %i * (q5 - 0.5);
    t2_01 = (q2 - 0.5) + %i * (q6 - 0.5);
    t2_10 = (q3 - 0.5) + %i * (q7 - 0.5);
    t2_11 = (b + q4 - 0.5) + %i * (q8 - 0.5);

    [t1_00, t1_01, t1_10, t1_11] = vmat_project(t1_00, t1_01, t1_10, t1_11);
    [t2_00, t2_01, t2_10, t2_11] = vmat_project(t2_00, t2_01, t2_10, t2_11);

    for i = 1:50
        vtable_sci();
    end
endfunction

function [st00, st01, st10, st11] = staple_sci(site, link_idx)
    st00 = zeros(vectorlength, 1);
    st01 = zeros(vectorlength, 1);
    st10 = zeros(vectorlength, 1);
    st11 = zeros(vectorlength, 1);

    site1 = ishift_sci(site, link_idx, 1);
    for link1_idx = 0:DIM-1
        if link1_idx ~= link_idx then
            site2 = ishift_sci(site, link1_idx, 1);
            site4 = ishift_sci(site1, link1_idx, -1);
            site5 = ishift_sci(site, link1_idx, -1);

            [m0_00, m0_01, m0_10, m0_11] = getlinks_sci(site1, link1_idx);
            [m1_00, m1_01, m1_10, m1_11] = getconjugate_sci(site2, link_idx);
            [m2_00, m2_01, m2_10, m2_11] = vmat_mul(m0_00, m0_01, m0_10, m0_11, m1_00, m1_01, m1_10, m1_11);
            [m0_00, m0_01, m0_10, m0_11] = getconjugate_sci(site, link1_idx);
            [m1_00, m1_01, m1_10, m1_11] = vmat_mul(m2_00, m2_01, m2_10, m2_11, m0_00, m0_01, m0_10, m0_11);
            [st00, st01, st10, st11] = vmat_add(st00, st01, st10, st11, m1_00, m1_01, m1_10, m1_11);

            [m0_00, m0_01, m0_10, m0_11] = getconjugate_sci(site4, link1_idx);
            [m1_00, m1_01, m1_10, m1_11] = getconjugate_sci(site5, link_idx);
            [m2_00, m2_01, m2_10, m2_11] = vmat_mul(m0_00, m0_01, m0_10, m0_11, m1_00, m1_01, m1_10, m1_11);
            [m0_00, m0_01, m0_10, m0_11] = getlinks_sci(site5, link1_idx);
            [m1_00, m1_01, m1_10, m1_11] = vmat_mul(m2_00, m2_01, m2_10, m2_11, m0_00, m0_01, m0_10, m0_11);
            [st00, st01, st10, st11] = vmat_add(st00, st01, st10, st11, m1_00, m1_01, m1_10, m1_11);
        end
    end
endfunction

function stot = monte_sci()
    global sold_arr snew_arr accepted_arr;
    vtable_sci();
    stot = 0.0;
    eds = 0.0;
    iacc = 0;

    for color_idx = 0:1
        for link_idx = 0:DIM-1
            [mt4_00, mt4_01, mt4_10, mt4_11] = staple_sci(color_idx, link_idx);
            [mt0_00, mt0_01, mt0_10, mt0_11] = getlinks_sci(color_idx, link_idx);
            sold_arr = vtprod_vec(mt0_00, mt0_01, mt0_10, mt0_11, mt4_00, mt4_01, mt4_10, mt4_11);

            for hit = 1:HITS
                [mt1_00, mt1_01, mt1_10, mt1_11] = ranmat_sci();
                [mt2_00, mt2_01, mt2_10, mt2_11] = vmat_mul(mt0_00, mt0_01, mt0_10, mt0_11, mt1_00, mt1_01, mt1_10, mt1_11);
                snew_arr = vtprod_vec(mt2_00, mt2_01, mt2_10, mt2_11, mt4_00, mt4_01, mt4_10, mt4_11);

                [ed, mt0_00, mt0_01, mt0_10, mt0_11] = metro_sci(mt0_00, mt0_01, mt0_10, mt0_11, mt2_00, mt2_01, mt2_10, mt2_11, beta_val / GROUP);
                eds = eds + ed;
                iacc = iacc + sum(accepted_arr);
                stot = stot + sum(sold_arr);
            end
            savelinks_sci(mt0_00, mt0_01, mt0_10, mt0_11, color_idx, link_idx);
        end
    end
    stot = stot / (2.0 * (DIM - 1) * nlinks * GROUP * HITS);
    acc_val = iacc / (nlinks * HITS);
    eds_val = eds / (2.0 * DIM * HITS);
    printf("stot=%.6f, acc=%.6f, eds=%.6f\n", stot, acc_val, eds_val);
endfunction

function stot = overrelax_sci()
    global sold_arr snew_arr accepted_arr;
    stot = 0.0;
    eds = 0.0;
    iacc = 0;

    for color_idx = 0:1
        for link_idx = 0:DIM-1
            [mt4_00, mt4_01, mt4_10, mt4_11] = staple_sci(color_idx, link_idx);
            [mt0_00, mt0_01, mt0_10, mt0_11] = getlinks_sci(color_idx, link_idx);
            [mt1_00, mt1_01, mt1_10, mt1_11] = vmat_project(mt4_00, mt4_01, mt4_10, mt4_11);
            [mt2_00, mt2_01, mt2_10, mt2_11] = vmat_mul(mt0_00, mt0_01, mt0_10, mt0_11, mt1_00, mt1_01, mt1_10, mt1_11);
            [mt3_00, mt3_01, mt3_10, mt3_11] = vmat_mul(mt1_00, mt1_01, mt1_10, mt1_11, mt2_00, mt2_01, mt2_10, mt2_11);
            [mt2_00, mt2_01, mt2_10, mt2_11] = vmat_conj(mt3_00, mt3_01, mt3_10, mt3_11);

            sold_arr = vtprod_vec(mt0_00, mt0_01, mt0_10, mt0_11, mt4_00, mt4_01, mt4_10, mt4_11);
            snew_arr = vtprod_vec(mt2_00, mt2_01, mt2_10, mt2_11, mt4_00, mt4_01, mt4_10, mt4_11);

            [ed, mt0_00, mt0_01, mt0_10, mt0_11] = metro_sci(mt0_00, mt0_01, mt0_10, mt0_11, mt2_00, mt2_01, mt2_10, mt2_11, beta_val / GROUP);
            eds = eds + ed;
            iacc = iacc + sum(accepted_arr);
            stot = stot + sum(sold_arr);

            savelinks_sci(mt0_00, mt0_01, mt0_10, mt0_11, color_idx, link_idx);
        end
    end
    stot = stot / (2.0 * (DIM - 1) * nlinks * GROUP);
    acc_val = iacc / nlinks;
    eds_val = eds / (2.0 * DIM);
    printf("stot=%.6f, acc=%.6f, eds=%.6f\n", stot, acc_val, eds_val);
endfunction

function renorm_sci()
    global u00 u01 u10 u11;
    for octant = 0:2*DIM-1
        link_start = octant * vectorlength + 1;
        link_end = link_start + vectorlength - 1;
        [u00(link_start:link_end), u01(link_start:link_end), u10(link_start:link_end), u11(link_start:link_end)] = vmat_project(u00(link_start:link_end), u01(link_start:link_end), u10(link_start:link_end), u11(link_start:link_end));
    end
endfunction

function res = loop_sci(x_len, y_len)
    global sold_arr;
    count_val = 0;
    result_val = 0.0;

    for color_idx = 0:1
        for link1_idx = 0:DIM-1
            start_link2 = 0;
            if x_len == y_len then start_link2 = link1_idx + 1; end
            for link2_idx = start_link2:DIM-1
                if link1_idx ~= link2_idx then
                    count_val = count_val + 1;
                    corner = ishift_sci(ishift_sci(color_idx, link1_idx, x_len), link2_idx, y_len);

                    m0_00 = ones(vectorlength, 1); m0_01 = zeros(vectorlength, 1);
                    m0_10 = zeros(vectorlength, 1); m0_11 = ones(vectorlength, 1);

                    m1_00 = ones(vectorlength, 1); m1_01 = zeros(vectorlength, 1);
                    m1_10 = zeros(vectorlength, 1); m1_11 = ones(vectorlength, 1);

                    m2_00 = ones(vectorlength, 1); m2_01 = zeros(vectorlength, 1);
                    m2_10 = zeros(vectorlength, 1); m2_11 = ones(vectorlength, 1);

                    m3_00 = ones(vectorlength, 1); m3_01 = zeros(vectorlength, 1);
                    m3_10 = zeros(vectorlength, 1); m3_11 = ones(vectorlength, 1);

                    for i_step = 0:x_len-1
                        [m4_00, m4_01, m4_10, m4_11] = getlinks_sci(ishift_sci(color_idx, link1_idx, i_step), link1_idx);
                        [m0_00, m0_01, m0_10, m0_11] = vmat_mul(m0_00, m0_01, m0_10, m0_11, m4_00, m4_01, m4_10, m4_11);

                        [m4_00, m4_01, m4_10, m4_11] = getconjugate_sci(ishift_sci(corner, link1_idx, -i_step - 1), link1_idx);
                        [m2_00, m2_01, m2_10, m2_11] = vmat_mul(m2_00, m2_01, m2_10, m2_11, m4_00, m4_01, m4_10, m4_11);
                    end

                    for i_step = 0:y_len-1
                        [m4_00, m4_01, m4_10, m4_11] = getlinks_sci(ishift_sci(corner, link2_idx, i_step - y_len), link2_idx);
                        [m1_00, m1_01, m1_10, m1_11] = vmat_mul(m1_00, m1_01, m1_10, m1_11, m4_00, m4_01, m4_10, m4_11);

                        [m4_00, m4_01, m4_10, m4_11] = getconjugate_sci(ishift_sci(color_idx, link2_idx, y_len - 1 - i_step), link2_idx);
                        [m3_00, m3_01, m3_10, m3_11] = vmat_mul(m3_00, m3_01, m3_10, m3_11, m4_00, m4_01, m4_10, m4_11);
                    end

                    [m0_00, m0_01, m0_10, m0_11] = vmat_mul(m0_00, m0_01, m0_10, m0_11, m1_00, m1_01, m1_10, m1_11);
                    [m0_00, m0_01, m0_10, m0_11] = vmat_mul(m0_00, m0_01, m0_10, m0_11, m2_00, m2_01, m2_10, m2_11);
                    sold_arr = vtprod_vec(m0_00, m0_01, m0_10, m0_11, m3_00, m3_01, m3_10, m3_11);

                    result_val = result_val + sum(sold_arr);
                end
            end
        end
    end
    res = result_val / (GROUP * vectorlength * count_val);
    printf(" %d by %d loop = %g\n", x_len, y_len, res);
endfunction

function init_sim_sci()
    srand48_sci(1234);
    maketable_sci();
    printf("initialization done\n");
endfunction

function main_sci()
    init_sim_sci();
    printf("lattice size %d by %d by %d by %d\n", SIZE, SIZE, SIZE, SIZE);
    printf(" vectorlength = %d\n", vectorlength);
    printf("group=SU(%d)   beta = %6.4f\n", GROUP, beta_val);
    printf("-----------------\n");

    printf("test monte\n");
    for iter = 1:5
        t0 = timer();
        count_val = 0;
        for i_iter = 1:5
            monte_sci();
            count_val = count_val + 1;
        end
        renorm_sci();
        elapsed = timer();
        microsec = (1000000.0 / (count_val * nlinks)) * elapsed;
        printf("running at %g microseconds per link\n", microsec);
        loop_sci(2, 2);
    end

    printf("test overrelax\n");
    for iter = 1:5
        t0 = timer();
        count_val = 0;
        for i_iter = 1:5
            overrelax_sci();
            count_val = count_val + 1;
        end
        renorm_sci();
        elapsed = timer();
        microsec = (1000000.0 / (count_val * nlinks)) * elapsed;
        printf("running at %g microseconds per link\n", microsec);
    end

    printf("all done\n");
    exit(0);
endfunction

main_sci();
