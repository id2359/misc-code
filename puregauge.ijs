NB. This program simulates SU(GROUP) lattice gauge fields with the
NB. simple Wilson action.
NB. Converted to J from Creutz's C++ puregauge.cc

GROUP =: 2
DIM =: 4
SIZE =: 8
HITS =: 10

beta =: 2.3

nsites =: SIZE * SIZE * SIZE * SIZE
nlinks =: DIM * nsites
vectorlength =: nsites % 2

shape =: SIZE, SIZE, SIZE, SIZE
shift =: 1 8 64 512

RNG_STATE =: 80880398

srand48 =: 3 : 0
  RNG_STATE =: 281474976710656 | 13070 + 65536 * y
  i. 0
)

drand48 =: 3 : 0
  RNG_STATE =: 281474976710656 | 11 + 25214903917 * RNG_STATE
  RNG_STATE % 281474976710656
)

coords =: 8 8 8 8 #: i. nsites
parity =: 2 | +/"1 coords
even_sites =: (0 = parity) # i. nsites

ulinks =: (nlinks, 2, 2) $ 1 0 0 1
table1 =: (vectorlength, 2, 2) $ 1 0 0 1
table2 =: (vectorlength, 2, 2) $ 1 0 0 1

mtemp0 =: (vectorlength, 2, 2) $ 1 0 0 1
mtemp1 =: (vectorlength, 2, 2) $ 1 0 0 1
mtemp2 =: (vectorlength, 2, 2) $ 1 0 0 1
mtemp3 =: (vectorlength, 2, 2) $ 1 0 0 1
mtemp4 =: (vectorlength, 2, 2) $ 1 0 0 1

sold =: vectorlength $ 0.0
snew =: vectorlength $ 0.0
accepted =: vectorlength $ 0

project_elem =: 3 : 0
  row0 =. 0 { y
  norm =. % %: +/ (| row0) ^ 2
  w00 =. (0 { row0) * norm
  w01 =. (1 { row0) * norm
  w10 =. - + w01
  w11 =. + w00
  2 2 $ w00, w01, w10, w11
)

project =: project_elem"2

vgroup =: 3 : 0
  project y
)

vtrace =: 3 : '9 o. (0 {"1 (0 {"1 y)) + (1 {"1 (1 {"1 y))'

vtprod =: 4 : 0
  +/"1 +/"1 (9 o. x * (|:"2 y))
)

makeindex =: 3 : 0
  dx =. 8 8 8 8 #: y
  even_coords =. 8 8 8 8 #: even_sites
  8 8 8 8 #. "1 (8 | even_coords +"1 dx)
)

ishift =: 3 : 0
  nb =. 0 { y
  dir =. 1 { y
  dist =. 2 { y
  dx =. 0 0 0 0
  dx =. dist (3 - dir) } dx
  y_coords =. 8 8 8 8 #: nb
  8 8 8 8 #. 8 | y_coords + dx
)

getlinks =: 4 : 0
  idx =. makeindex x
  sft =. nsites * y
  (idx + sft) { ulinks
)

getconjugate =: 4 : 0
  idx =. makeindex x
  sft =. nsites * y
  +|:"2 ((idx + sft) { ulinks)
)

savelinks =: 3 : 0
  g =. 0 {:: y
  site =. 1 {:: y
  link =. 2 {:: y
  idx =. makeindex site
  sft =. nsites * link
  ulinks =: g (idx + sft) } ulinks
  i. 0
)

metro =: 3 : 0
  old =. 0 {:: y
  trial =. 1 {:: y
  bias =. 2 {:: y
  sold_in =. 3 {:: y
  snew_in =. 4 {:: y

  temp =. ^ bias * (snew_in - sold_in)
  expdeltas =. +/ temp

  r_vals =. drand48 "0 (i. vectorlength)
  acc =. r_vals < temp
  accepted =: acc

  acc_idx =. acc # i. vectorlength
  if. 0 < # acc_idx do.
    sold_in =. (acc_idx { snew_in) acc_idx } sold_in
    old =. (acc_idx { trial) acc_idx } old
  end.

  (expdeltas % vectorlength) ; old ; sold_in ; acc
)

ranmat =: 3 : 0
  idx =. <. vectorlength * drand48 0
  res =. (vectorlength, 2, 2) $ 0
  loop_iv =. 0
  while. loop_iv < vectorlength do.
    if. idx >= vectorlength do. idx =. idx - vectorlength end.
    t_mat =. idx { table1
    if. (drand48 0) < 0.5 do.
      res =. t_mat loop_iv } res
    else.
      res =. (+|: t_mat) loop_iv } res
    end.
    idx =. idx + 1
    loop_iv =. loop_iv + 1
  end.
  res
)

vtable =: 3 : 0
  m0 =. ranmat 0
  table1_new =. table2 +/ . * "2 m0
  sold_t =. vtrace table2
  snew_t =. vtrace table1_new
  m_res =. metro table2 ; table1_new ; (6.0 * beta % GROUP) ; sold_t ; snew_t
  table2 =: 1 {:: m_res
  table1 =: table2
  table2 =: m0
  table1 =: vgroup table1
  i. 0
)

maketable =: 3 : 0
  t1_list =. (vectorlength, 2, 2) $ 0.0
  t2_list =. (vectorlength, 2, 2) $ 0.0
  b =. beta % GROUP
  iv =. 0
  while. iv < vectorlength do.
    r1 =. drand48 0; r2 =. drand48 0; r3 =. drand48 0; r4 =. drand48 0; r5 =. drand48 0; r6 =. drand48 0; r7 =. drand48 0; r8 =. drand48 0
    t1 =. 2 2 $ (b + r1 - 0.5) j. (r5 - 0.5) , (r2 - 0.5) j. (r6 - 0.5) , (r3 - 0.5) j. (r7 - 0.5) , (b + r4 - 0.5) j. (r8 - 0.5)

    q1 =. drand48 0; q2 =. drand48 0; q3 =. drand48 0; q4 =. drand48 0; q5 =. drand48 0; q6 =. drand48 0; q7 =. drand48 0; q8 =. drand48 0
    t2 =. 2 2 $ (b + q1 - 0.5) j. (q5 - 0.5) , (q2 - 0.5) j. (q6 - 0.5) , (q3 - 0.5) j. (q7 - 0.5) , (b + q4 - 0.5) j. (q8 - 0.5)

    t1_list =. t1 iv } t1_list
    t2_list =. t2 iv } t2_list
    iv =. iv + 1
  end.
  table1 =: vgroup t1_list
  table2 =: vgroup t2_list
  for_i. i. 50 do.
    vtable 0
  end.
  i. 0
)

staple =: 4 : 0
  site =. x
  link =. y
  st =. (vectorlength, 2, 2) $ 0
  site1 =. ishift site, link, 1
  for_link1. i. DIM do.
    if. link1 ~: link do.
      site2 =. ishift site, link1, 1
      site4 =. ishift site1, link1, _1
      site5 =. ishift site, link1, _1

      m0_s =. site1 getlinks link1
      m1_s =. site2 getconjugate link
      m2_s =. m0_s +/ . * "2 m1_s
      m0_s =. site getconjugate link1
      m1_s =. m2_s +/ . * "2 m0_s
      st =. st + m1_s

      m0_s =. site4 getconjugate link1
      m1_s =. site5 getconjugate link
      m2_s =. m0_s +/ . * "2 m1_s
      m0_s =. site5 getlinks link1
      m1_s =. m2_s +/ . * "2 m0_s
      st =. st + m1_s
    end.
  end.
  st
)

monte =: 3 : 0
  vtable 0
  stot =. 0.0
  eds =. 0.0
  iacc =. 0
  for_color. 0 1 do.
    for_link. i. DIM do.
      mtemp4 =: color staple link
      mtemp0 =: color getlinks link
      sold =: mtemp0 vtprod mtemp4
      for_hit. i. HITS do.
        mtemp1 =: ranmat 0
        mtemp2 =: mtemp0 +/ . * "2 mtemp1
        snew =: mtemp2 vtprod mtemp4
        m_out =. metro mtemp0 ; mtemp2 ; (beta % GROUP) ; sold ; snew
        eds =. eds + 0 {:: m_out
        mtemp0 =: 1 {:: m_out
        sold =: 2 {:: m_out
        acc_v =. 3 {:: m_out
        iacc =. iacc + +/ acc_v
        stot =. stot + +/ sold
      end.
      savelinks mtemp0 ; color ; link
    end.
  end.
  stot =. stot % (2.0 * (DIM - 1) * nlinks * GROUP * HITS)
  acc_val =. iacc % (nlinks * HITS)
  eds =. eds % (2.0 * DIM * HITS)
  echo 'stot=' , (": stot) , ', acc=' , (": acc_val) , ', eds=' , (": eds)
  stot
)

overrelax =: 3 : 0
  stot =. 0.0
  eds =. 0.0
  iacc =. 0
  for_color. 0 1 do.
    for_link. i. DIM do.
      mtemp4 =: color staple link
      mtemp0 =: color getlinks link
      mtemp1 =: vgroup mtemp4
      mtemp2 =: mtemp0 +/ . * "2 mtemp1
      mtemp3 =: mtemp1 +/ . * "2 mtemp2
      mtemp2 =: +|:"2 mtemp3
      sold =: mtemp0 vtprod mtemp4
      snew =: mtemp2 vtprod mtemp4
      m_out =. metro mtemp0 ; mtemp2 ; (beta % GROUP) ; sold ; snew
      eds =. eds + 0 {:: m_out
      mtemp0 =: 1 {:: m_out
      sold =. 2 {:: m_out
      acc_v =. 3 {:: m_out
      iacc =. iacc + +/ acc_v
      stot =. stot + +/ sold
      savelinks mtemp0 ; color ; link
    end.
  end.
  stot =. stot % (2.0 * (DIM - 1) * nlinks * GROUP)
  acc_val =. iacc % nlinks
  eds =. eds % (2.0 * DIM)
  echo 'stot=' , (": stot) , ', acc=' , (": acc_val) , ', eds=' , (": eds)
  stot
)

renorm =: 3 : 0
  for_octant. i. (2 * DIM) do.
    link_idx =. octant * vectorlength
    slice_idx =. link_idx + i. vectorlength
    sub_l =. slice_idx { ulinks
    sub_l =. vgroup sub_l
    ulinks =: sub_l slice_idx } ulinks
  end.
  i. 0
)

wilson_loop =: 4 : 0
  x_len =. x
  y_len =. y
  count =. 0
  result =. 0.0
  for_color. 0 1 do.
    for_link1. i. DIM do.
      start_link2 =. (x_len = y_len) * (link1 + 1)
      link2_list =. (start_link2 + i. (DIM - start_link2))
      for_link2. link2_list do.
        if. link1 ~: link2 do.
          count =. count + 1
          corner =. ishift (ishift color, link1, x_len), link2, y_len
          m0_l =. (vectorlength, 2, 2) $ 1 0 0 1
          m1_l =. (vectorlength, 2, 2) $ 1 0 0 1
          m2_l =. (vectorlength, 2, 2) $ 1 0 0 1
          m3_l =. (vectorlength, 2, 2) $ 1 0 0 1

          for_i. i. x_len do.
            m4_l =. (ishift color, link1, i) getlinks link1
            m0_l =. m0_l +/ . * "2 m4_l
            m4_l =. (ishift corner, link1, (_1 - i)) getconjugate link1
            m2_l =. m2_l +/ . * "2 m4_l
          end.

          for_i. i. y_len do.
            m4_l =. (ishift corner, link2, (i - y_len)) getlinks link2
            m1_l =. m1_l +/ . * "2 m4_l
            m4_l =. (ishift color, link2, (y_len - 1 - i)) getconjugate link2
            m3_l =. m3_l +/ . * "2 m4_l
          end.

          m0_l =. m0_l +/ . * "2 m1_l
          m0_l =. m0_l +/ . * "2 m2_l
          res_s =. m0_l vtprod m3_l
          result =. result + +/ res_s
        end.
      end.
    end.
  end.
  result =. result % (GROUP * vectorlength * count)
  echo ' ' , (": x_len) , ' by ' , (": y_len) , ' loop = ' , (": result)
  result
)

init_sim =: 3 : 0
  srand48 1234
  coords =: 8 8 8 8 #: i. nsites
  parity =: 2 | +/"1 coords
  even_sites =: (0 = parity) # i. nsites
  maketable 0
  echo 'initialization done'
  i. 0
)

main =: 3 : 0
  if. 2 < # ARGV do.
    beta =: "1 > 2 { ARGV
  end.
  init_sim 0
  echo 'lattice size 8 by 8 by 8 by 8'
  echo ' vectorlength = 2048'
  echo 'group=SU(2)   beta = 2.3000'
  echo '-----------------'

  echo 'test monte'
  for_iter. i. 5 do.
    t0 =. 6!:1 ''
    for_i. i. 5 do.
      monte 0
    end.
    renorm 0
    t1 =. 6!:1 ''
    elapsed =. t1 - t0
    microsec =. (1e6 % (5 * nlinks)) * elapsed
    echo 'running at ' , (": microsec) , ' microseconds per link'
    2 wilson_loop 2
  end.

  echo 'test overrelax'
  for_iter. i. 5 do.
    t0 =. 6!:1 ''
    for_i. i. 5 do.
      overrelax 0
    end.
    renorm 0
    t1 =. 6!:1 ''
    elapsed =. t1 - t0
    microsec =. (1e6 % (5 * nlinks)) * elapsed
    echo 'running at ' , (": microsec) , ' microseconds per link'
  end.

  echo 'all done'
  exit 0
)

main 0
