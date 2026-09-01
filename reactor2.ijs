NB. Pattern Recognition with Application to Reactor Diagnostics
NB. J translation of Skomorokhov & Slepov, APL'98
NB.
NB. Conventions:
NB.   Spectra are stored as 2-D arrays: rows = samples, cols = frequency bins.
NB.   In the original APL paper, `a` and `b` were nested vectors of vectors.
NB.   In J, idiomatic style uses rectangular arrays + rank operators.
NB.
NB. Load data with:
NB.   data =. ".&> cutopen 1!:1 < 'data.txt'
NB. or whatever loader produces a 2-D numeric array.

NB. ============================================================
NB. Peak extraction
NB. ============================================================

NB. lmax X — boolean vector marking local maxima of X
NB. Same shape as X; first and last cells are always 0.
lmax =: 3 : 0
  n =. # y
  if. n < 3 do. n # 0 return. end.
  rot1 =. 1 |. y
  rot2 =. 2 |. y
  m =. (rot1 > y) *. rot1 > rot2
  0 , (}: }. m) , 0
)

NB. lmin X — boolean vector marking local minima of X
lmin =: 3 : 0
  n =. # y
  if. n < 3 do. n # 0 return. end.
  rot1 =. 1 |. y
  rot2 =. 2 |. y
  m =. (rot1 < y) *. rot1 < rot2
  0 , (}: }. m) , 0
)

NB. peaks X — list of boxed peak ranges, partitioned at local minima
peaks =: 3 : 0
  mi =. lmin y
  cuts =. 1 + I. mi
  ranges =. (}: cuts) ,. (}. cuts)
  (<"1) {.@({.~ ;. _3) y
)

NB. Simpler peaks: split at local minima
peakSplit =: 3 : 0
  mi =. lmin y
  ;: y ,&< mi  NB. placeholder; see python for full version
)

NB. peakWidth X — length of each peak segment (between adjacent local minima)
peakWidth =: 3 : 0
  mi =. I. lmin y
  if. 2 > # mi do. (# y) , 0 $ 0 return. end.
  (2 -~/\ mi)
)

NB. peakEnergy X — integral of each peak (sum of values in segment)
peakEnergy =: 3 : 0
  mi =. I. lmin y
  if. 2 > # mi do. (+/ y) , 0 $ 0 return. end.
  segs =. (2 <\ mi) <@({.~"0 1 _) y  NB. boxed segments
  +/&> segs
)

NB. ============================================================
NB. Smoothed second derivative
NB. ============================================================

NB. n deriv2 X — sliding-window LSQ quadratic, returns 2nd derivative
NB. Implementation: for each window of n consecutive points, fit
NB.   y = a0 + a1*t + a2*t^2  with t centered, then 2nd deriv = 2*a2.
deriv2 =: 4 : 0
  n =. x
  t =. (i. n) - (n - 1) % 2          NB. centered time axis
  M =. t ^/ 0 1 2                     NB. design matrix
  Minv =. %. M                        NB. pseudoinverse via solve
  windows =. n ]\ y
  coeffs =. windows +/ . * (|: Minv)  NB. one row per window: a0 a1 a2
  2 * 2 {"1 coeffs                    NB. 2 * a2
)

NB. ============================================================
NB. Multidimensional scaling
NB. ============================================================

NB. Fisher projection: returns optimal direction vector
NB.   (X Fisher Y) where X and Y are matrices, rows = samples
Fisher =: 4 : 0
  M1 =. (+/ x) % # x
  M2 =. (+/ y) % # y
  S1 =. (|: x - M1) +/ . * (x - M1)
  S2 =. (|: y - M2) +/ . * (y - M2)
  (M1 - M2) %. (S1 + S2)
)

NB. Euclidean distance between two vectors (atomic) or rank-1 cells
edist =: %:@(+/)@(*:@-)"1

NB. Distance from each row of X to vector v
distTo =: 4 : '%: +/"1 *: x -"1 y'

NB. Pairwise squared distances between rows of X
sqDistMatrix =: 3 : '+/"1 *: y -"1/ y'

NB. Orloci ordination: 2-D embedding using two most-outlying points.
NB. First axis = line through two points with maximum pairwise distance.
NB. Second axis = perpendicular through the point furthest from axis 1.
NB. Returns an (n,2) matrix of coordinates.
Orloci =: 3 : 0
  n =. # y
  NB. Pairwise squared distances: D[i,j] = sum((y[i] - y[j])^2)
  D =. +/"1 *: y -"1/ y
  ij =. n #: (i. >./) , D
  i =. 0 { ij
  j =. 1 { ij
  Y =. y -"1 i { y                 NB. shift origin to point i
  pj =. j { Y                       NB. axis-1 direction
  denom =. +/ pj * pj
  Acoef =. (Y +/ . * pj) % denom >. 1e_12
  NB. Squared residual distance from each point to axis-1 line
  resid =. +/"1 *: Y -"1 Acoef *"0 1 pj
  k =. resid i. >./ resid           NB. point furthest from line
  Y =. Y -"1 (k { Acoef) * pj       NB. orthogonal shift defining axis 2
  axis2 =. k { Y
  basis =. |: pj ,: axis2           NB. (features, 2)
  Y +/ . * basis
)

NB. ============================================================
NB. Clustering
NB. ============================================================

NB. K-means clustering
NB.   k kmeans X — X is matrix with rows as observations
NB. Returns: matrix of k cluster centers
kmeans =: 4 : 0
  k =. x
  X =. y
  M =. ({~ k ?@# #) X                  NB. random initial centers
  prev =. _
  while. -. M -: prev do.
    prev =. M
    D =. +/"1 *: X -"1/ M               NB. distance from each X to each center
    C =. (i. <./)"1 D                    NB. assignment vector
    M =. (k , {: $ X) $ ,/ ((i. k) {."1 |:) ((i. k) =/ C) +/ . * X
    NB. simpler: average rows by cluster label
    M =. (k , {: $ X) $ 0
    for_i. i. k do.
      mask =. C = i
      if. 0 < +/ mask do.
        M =. M ((+/ % #) mask # X)`[`(i;)} M
      end.
    end.
  end.
  M
)

NB. Cleaner K-means using key (/.)
kmeansClean =: 4 : 0
  k =. x
  X =. y
  M =. ({~ k ?@# #) X
  while. 1 do.
    D =. +/"1 *: X -"1/ M
    C =. (i. <./)"1 D
    Mnew =. C (+/ % #)/. X
    Mnew =. (k , {: $ X) {. Mnew         NB. pad if some cluster lost points
    if. M -: Mnew do. break. end.
    M =. Mnew
  end.
  M
)

NB. Classify rows of X by nearest center M
classify =: 4 : 0
  D =. +/"1 *: y -"1/ x
  (i. <./)"1 D
)

NB. ============================================================
NB. Supervised pattern recognition
NB. ============================================================

NB. K-nearest-neighbors
NB.   k kneib (X ; labels ; query) — X is training matrix, labels is integer vector,
NB.                                  query is a single vector to classify.
NB. Returns the predicted class label (integer).
kneib =: 4 : 0
  k =. x
  'X labels query' =. y
  d =. +/"1 *: X -"1 query
  nearestLabels =. k {. labels /: d
  counts =. #/.~ nearestLabels /:~ ~. nearestLabels
  classes =. ~. nearestLabels /:~ ~. nearestLabels
  classes {~ counts i. >./ counts
)

NB. Ho-Kashyap linear discriminant
NB. (X Ho Y) — X is class-1 matrix, Y is class-2 matrix
NB. Returns weight vector A such that
NB.   x'A > 0 implies class 1, < 0 implies class 2
Ho =: 4 : 0
  X =. x ,. 1                            NB. append bias column
  Y =. - y ,. 1                          NB. negate class-2 rows
  Z =. X , Y
  Zinv =. %. Z
  B =. (# Z) $ 1
  E0 =. (# B) $ 0
  for. i. 1000 do.                       NB. cap iterations
    A =. Zinv +/ . * B
    E =. (Z +/ . * A) - B
    if. (E0 -: E) +. *./ E > 0 do. break. end.
    B =. B + 0.5 * (E > 0) * E
    E0 =. E
  end.
  A
)

NB. ============================================================
NB. Stochastic Search with Adaptation
NB. ============================================================

NB. Pick n features at random without replacement, with prob distribution p.
NB. Returns vector of n distinct feature indices.
rnd =: 4 : 0
  n =. x
  p =. y
  result =. ''
  for. i. n do.
    cum =. +/\ p
    z =. 1 i.~ cum > ?@$ 0
    z =. z <. <: # p
    result =. result , z
    p =. p % 1 - z { p
    p =. 0 z} p
  end.
  result
)

NB. Number of mis-classifications under nearest-mean rule on selected features
NB. (a nerrCrit b)
nerrCrit =: 4 : 0
  ma =. (+/ % #) x
  mb =. (+/ % #) y
  da_a =. +/"1 *: x -"1 ma
  da_b =. +/"1 *: x -"1 mb
  db_a =. +/"1 *: y -"1 ma
  db_b =. +/"1 *: y -"1 mb
  (+/ da_a > da_b) + (+/ db_b > db_a)
)

NB. Fisher distance criterion
fishCrit =: 4 : 0
  d =. x Fisher y
  pa =. x +/ . * d
  pb =. y +/ . * d
  ma =. (+/ % #) pa
  mb =. (+/ % #) pb
  num =. *: ma - mb
  num % +/ (*: pa - ma) , (*: pb - mb)
)

NB. Stochastic Search with Adaptation (Fisher criterion baked in for simplicity)
NB. (n,r,R) ssaFisher (a ; b) — a and b are class matrices
NB.   n = number of features to pick per trial
NB.   r = trials per adaptation step
NB.   R = number of adaptation steps
NB. Returns boxed: (best feature indices ; final probability vector)
ssaFisher =: 4 : 0
  'n r R' =. x
  'a b' =. y
  nf =. {: $ a
  p =. nf $ 1 % nf
  s =. (1 % nf) % r
  bestScore =. _
  bestIdx =. n {. i. nf
  for. i. R do.
    trials =. (r , n) $ ,/ (n&rnd"_)"_1 r # ,: p
    scores =. ''
    for. row. i. r do.
      idx =. row { trials
      scores =. scores , (idx {"1 a) fishCrit (idx {"1 b)
    end.
    bestI =. scores i. >./ scores
    worstI =. scores i. <./ scores
    p =. p + s * 1 (bestI { trials)} nf $ 0
    p =. p - s * 1 (worstI { trials)} nf $ 0
    p =. 0 >. p
    p =. p % +/ p
    if. (bestI { scores) > bestScore do.
      bestScore =. bestI { scores
      bestIdx =. bestI { trials
    end.
  end.
  bestIdx ; p
)

NB. ============================================================
NB. Example session
NB. ============================================================
NB.
NB.   data =. ".&> cutopen 1!:1 < 'data.txt'
NB.   labels =. data {."1 _1                  NB. last column = sensor label
NB.   X =. data }."1 _1                       NB. drop label column
NB.   a =. (labels = 1) # X
NB.   b =. (labels = 2) # X
NB.
NB.   lmax 0 { a                              NB. local maxima of first spectrum
NB.   7 deriv2 0 { a                          NB. smoothed 2nd derivative
NB.   d =. (16 {"1 a) Fisher (16 {"1 b)       NB. Fisher direction on feature 16
NB.   M =. 2 kmeansClean a , b                NB. 2-means on full data
NB.   M classify a , b                         NB. assignments
NB.   5 kneib (a , b) ; (60 # 1) , (57 # 2) ; (0 { a)
NB.   w =. a Ho b                              NB. linear discriminant
NB.   r =. (20 20 30) ssaFisher a ; b          NB. feature selection
