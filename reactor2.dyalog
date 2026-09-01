:Namespace reactor
⍝ Pattern Recognition with Application to Reactor Diagnostics
⍝ Skomorokhov & Slepov, APL'98 — Dyalog APL port.
⍝
⍝ Loads with:
⍝     ]load reactor
⍝
⍝ Usage:
⍝     reactor.lmax 1 2 1 3 2 4 1
⍝     reactor.runDemo 'data.txt'
⍝
⍝ Data conventions:
⍝   Spectra are stored as matrices: rows = samples, cols = frequency bins.
⍝   The paper used nested vectors of vectors; matrix form is cleaner in
⍝   modern Dyalog and works directly with +⌿, ⌹, +.× etc.

    ⎕IO←1
    ⎕ML←1


    ⍝ ─────────────────────────────────────────────────────────
    ⍝ Peak extraction
    ⍝ ─────────────────────────────────────────────────────────

    ∇ Z←lmax X;mid
      ⍝ Boolean mask of strict interior local maxima of vector X.
      :If 3>≢X
          Z←(≢X)⍴0
          :Return
      :EndIf
      mid←1↓¯1↓X
      Z←0,(mid>¯2↓X)∧mid>2↓X
      Z←Z,0
    ∇


    ∇ Z←lmin X;mid
      ⍝ Boolean mask of strict interior local minima of vector X.
      :If 3>≢X
          Z←(≢X)⍴0
          :Return
      :EndIf
      mid←1↓¯1↓X
      Z←0,(mid<¯2↓X)∧mid<2↓X
      Z←Z,0
    ∇


    ∇ P←peaks X
      ⍝ Partition vector X into peak segments at local minima.
      ⍝ Returns nested vector of segments.
      P←(~lmin X)⊂X
    ∇


    ∇ W←peakWidths X
      ⍝ Width (in points) of each peak segment.
      W←≢¨peaks X
    ∇


    ∇ E←peakEnergies X
      ⍝ Energy (sum of values) of each peak segment.
      E←+/¨peaks X
    ∇


    ⍝ ─────────────────────────────────────────────────────────
    ⍝ Smoothed second derivative — sliding LSQ quadratic
    ⍝ ─────────────────────────────────────────────────────────

    ∇ Y←N deriv2 X;t;M;Mp;starts;windows;n
      ⍝ For each window of N consecutive points, fit y = a₀+a₁t+a₂t²
      ⍝ with t centered, then return ∂²y/∂t² = 2·a₂.
      ⍝ N must be odd and ≤ ≢X.
      n←≢X
      t←(⍳N)-(N+1)÷2
      M←t∘.*0 1 2
      Mp←⌹M
      starts←⍳1+n-N
      windows←X[starts∘.+¯1+⍳N]
      Y←2×windows+.×Mp[3;]
    ∇


    ⍝ ─────────────────────────────────────────────────────────
    ⍝ Fisher projection
    ⍝ ─────────────────────────────────────────────────────────

    ∇ Sm←scatter X;m;C
      ⍝ Within-class scatter matrix: (X-mean)' (X-mean).
      m←(+⌿X)÷≢X
      C←X-⍤1⊢m
      Sm←(⍉C)+.×C
    ∇


    ∇ D←A FisherDir B;ma;mb;Sa;Sb;n;reg;I
      ⍝ Fisher's optimal projection direction.
      ⍝ Maximises (m_a-m_b)² / (s_a²+s_b²).
      ⍝ Adds a small ridge for numerical stability when p>>n.
      ma←(+⌿A)÷≢A
      mb←(+⌿B)÷≢B
      Sa←scatter A
      Sb←scatter B
      n←⊃⍴Sa
      I←∘.=⍨⍳n
      reg←0.001×(+/1 1⍉Sa+Sb)÷n
      D←(ma-mb)⌹(Sa+Sb)+reg×I
    ∇


    ∇ R←FisherProject AB;A;B;d
      ⍝ Project two class matrices onto Fisher direction.
      ⍝ Right argument: 2-element nested (A B).
      ⍝ Returns 2-element nested (proj_A proj_B).
      (A B)←AB
      d←A FisherDir B
      R←(A+.×d)(B+.×d)
    ∇


    ∇ C←orloci X;n;diff;D;flat;ij;i;j;Y;pj;denom;Acoef;resid;k;axis2;basis
      ⍝ Orloci ordination: 2-D embedding using two most-outlying points.
      ⍝ Axis 1 connects the two points with maximum pairwise distance.
      ⍝ Axis 2 is perpendicular through the point furthest from axis 1.
      ⍝
      ⍝ X is a matrix, rows = samples. Returns (≢X, 2) coordinate matrix.
      ⍝ The basis vectors aren't orthonormalised — coordinates are
      ⍝ projections onto the (non-unit) axis directions, matching the
      ⍝ paper's formulation.
      n←≢X
      ⍝ Pairwise squared distances via outer subtraction
      D←{+/((⍉X)-X[⍵;]∘.×n⍴1)*2}¨⍳n
      D←↑D                                    ⍝ promote to n×n matrix
      flat←,D
      ij←(⍴D)⊤¯1+flat⍳⌈/flat
      i←1+⊃ij
      j←1+1⊃ij
      ⍝ Shift origin to point i
      Y←X-⍤1⊢X[i;]
      pj←Y[j;]                                ⍝ axis-1 direction
      denom←+/pj×pj
      Acoef←(Y+.×pj)÷denom⌈1E¯12              ⍝ projection coefficients on axis ij
      ⍝ Squared distance from each point to axis-1 line
      resid←+/(Y-Acoef∘.×pj)*2
      k←resid⍳⌈/resid
      ⍝ Orthogonal shift defining axis 2: subtract scalar*vector from each row
      Y←Y-⍤1⊢Acoef[k]×pj
      axis2←Y[k;]
      basis←⍉↑pj axis2                        ⍝ features × 2
      C←Y+.×basis
    ∇


    ⍝ ─────────────────────────────────────────────────────────
    ⍝ Clustering
    ⍝ ─────────────────────────────────────────────────────────

    ∇ R←chainDistances X;diff
      ⍝ Euclidean distance between consecutive rows of X.
      diff←(1↓[1]X)-¯1↓[1]X
      R←0.5*⍨+/diff×diff
    ∇


    ∇ d←sqDistRowToCenters Args;row;centers
      ⍝ Squared distance from one row to each row of centers matrix.
      ⍝ Args is (row centers).
      (row centers)←Args
      d←+⌿((⍉centers)-row∘.×(⊃⍴centers)⍴1)*2
    ∇


    ∇ d←sqDistMatrix Args;X;centers;i;n;K
      ⍝ For matrix X (n rows) and centers (K rows of same width),
      ⍝ return n×K matrix of squared distances.
      (X centers)←Args
      n←≢X
      K←≢centers
      d←(n,K)⍴0
      i←0
      :While i<n
          i←i+1
          d[i;]←sqDistRowToCenters X[i;]centers
      :EndWhile
    ∇


    ∇ M←K kmean X;n;assign;Mnew;d;i;mask;count
      ⍝ K-means on matrix X (rows = samples). Returns matrix of K centers.
      n←≢X
      M←X[K?n;]
      Mnew←M+1
      :While ~M≡Mnew
          M←Mnew
          d←sqDistMatrix X M
          assign←⍬
          i←0
          :While i<n
              i←i+1
              assign,←d[i;]⍳⌊/d[i;]
          :EndWhile
          Mnew←M
          i←0
          :While i<K
              i←i+1
              mask←assign=i
              count←+/mask
              :If 0<count
                  Mnew[i;]←(+⌿mask⌿X)÷count
              :EndIf
          :EndWhile
      :EndWhile
      M←Mnew
    ∇


    ∇ C←M classify X;d;n;i
      ⍝ Assign each row of X to nearest row of M.
      d←sqDistMatrix X M
      n←≢X
      C←⍬
      i←0
      :While i<n
          i←i+1
          C,←d[i;]⍳⌊/d[i;]
      :EndWhile
    ∇


    ⍝ ─────────────────────────────────────────────────────────
    ⍝ Supervised classification
    ⍝ ─────────────────────────────────────────────────────────

    ∇ pred←K kneib Args;X;y;query;diff;d;nearest;classes;votes
      ⍝ K-nearest-neighbours.
      ⍝ Args is (X y query):
      ⍝   X     — training matrix
      ⍝   y     — integer label vector
      ⍝   query — single vector to classify
      (X y query)←Args
      diff←(⍉X)-query∘.×(≢X)⍴1
      d←+⌿diff*2
      nearest←y[K↑⍋d]
      classes←∪nearest
      votes←+⌿classes∘.=nearest
      pred←classes[votes⍳⌈/votes]
    ∇


    ∇ W←A Ho B;Z;Zinv;margin;prev;err;iter
      ⍝ Ho-Kashyap linear discriminant.
      ⍝ Returns weight vector W (length = 1 + #features) such that
      ⍝     (x,1)+.×W > 0  ⇒  class A,    < 0  ⇒  class B
      ⍝
      ⍝ Requires #samples ≥ #features+1 so that Z is tall — generate
      ⍝ enough training data via data.py to satisfy this. With wide Z,
      ⍝ ⌹Z raises LENGTH ERROR because the classical pseudo-inverse is
      ⍝ defined only for the overdetermined case.
      Z←(A,1)⍪-B,1
      Zinv←⌹Z
      margin←(≢Z)⍴1
      prev←0×margin
      iter←0
      :Repeat
          W←Zinv+.×margin
          err←(Z+.×W)-margin
          :If (prev≡err)∨∧/err>0
              :Leave
          :EndIf
          margin←margin+0.5×0⌈err
          prev←err
          iter←iter+1
      :Until iter≥1000
    ∇


    ⍝ ─────────────────────────────────────────────────────────
    ⍝ Stochastic Search with Adaptation
    ⍝ ─────────────────────────────────────────────────────────

    ∇ idx←n rnd p;remaining;cum;pick;total
      ⍝ Sample n distinct indices according to probability vector p.
      ⍝ Without replacement: pick one, zero its prob, renormalise, repeat.
      idx←⍬
      total←+/p
      :If total≤0
          idx←n↑⍳≢p
          :Return
      :EndIf
      remaining←p÷total
      :While n>≢idx
          cum←+\remaining
          pick←1++/cum<?0
          :If pick>≢p
              pick←≢p
          :EndIf
          idx,←pick
          remaining[pick]←0
          total←+/remaining
          :If 0<total
              remaining←remaining÷total
          :EndIf
      :EndWhile
    ∇


    ∇ score←A fishScore B;d;pa;pb;ma;mb;num;den
      ⍝ Fisher score = between-class² / within-class scatter
      ⍝ on the 1-D Fisher-projected values. Higher = better.
      d←A FisherDir B
      pa←A+.×d
      pb←B+.×d
      ma←(+/pa)÷≢pa
      mb←(+/pb)÷≢pb
      num←(ma-mb)*2
      den←(+/(pa-ma)*2)++/(pb-mb)*2
      score←num÷den⌈1E¯12
    ∇


    ∇ result←Params ssaFisher Data;A;B;n;r;R;p;step;bestScore;bestIdx;trials;scores;best;worst;i;j;sub;k
      ⍝ Stochastic Search with Adaptation (Fisher criterion).
      ⍝
      ⍝ Params: 3-element vector (n r R)
      ⍝   n — features per trial
      ⍝   r — trials per adaptation step
      ⍝   R — number of adaptation steps
      ⍝
      ⍝ Data: 2-element nested (A B), the two class matrices.
      ⍝
      ⍝ Returns 3-element nested:
      ⍝     (best-feature-indices  best-score  final-probability-vector)
      (A B)←Data
      (n r R)←Params
      k←⊃⌽⍴A
      p←k⍴÷k
      step←(÷k)÷r
      bestScore←¯1E20
      bestIdx←⍳n
      i←0
      :While i<R
          i←i+1
          trials←(r,n)⍴0
          j←0
          :While j<r
              j←j+1
              trials[j;]←n rnd p
          :EndWhile
          scores←⍬
          j←0
          :While j<r
              j←j+1
              sub←trials[j;]
              scores,←(A[;sub])fishScore(B[;sub])
          :EndWhile
          best←scores⍳⌈/scores
          worst←scores⍳⌊/scores
          p[trials[best;]]←p[trials[best;]]+step
          p[trials[worst;]]←p[trials[worst;]]-step
          p←0⌈p
          p←p÷+/p
          :If (scores[best])>bestScore
              bestScore←scores[best]
              bestIdx←trials[best;]
          :EndIf
      :EndWhile
      result←bestIdx bestScore p
    ∇


    ⍝ ─────────────────────────────────────────────────────────
    ⍝ Data loading and demo
    ⍝ ─────────────────────────────────────────────────────────

    ∇ AB←loadData path;text;lines;rows;d;L;X;ncol
      ⍝ Load whitespace-separated text data (last column = integer label).
      ⍝ Returns 2-element nested (A B), one matrix per class.
      ⍝
      ⍝ Implementation note: ⎕CSV in Dyalog defaults to comma separators
      ⍝ and trips on multiple spaces, so we read the file as text with
      ⍝ ⎕NGET and parse each line with ⎕VFI (verify-and-fix-input).
      text←⊃⎕NGET path 1                     ⍝ read as vector of lines
      lines←(0<≢¨text)/text                   ⍝ drop empty lines
      rows←{⊃⌽⎕VFI ⍵}¨lines                   ⍝ each line → numeric vector
      d←↑rows                                  ⍝ promote to matrix
      ncol←⊃⌽⍴d
      L←d[;ncol]
      X←d[;⍳ncol-1]
      AB←((L=1)⌿X)((L=2)⌿X)
    ∇


    ∇ runDemo path;AB;A;B;spec;n_max;n_seg;d2;projs;pa;pb;centers;truth;acc;w;ssaResult;coords;Aco;Bco
      ⍝ End-to-end smoke test using data.txt produced by data.py.
      AB←loadData path
      (A B)←AB
      ⎕←'Loaded A: ',(⍕⍴A),'   B: ',⍕⍴B

      spec←A[1;]
      n_max←+/lmax spec
      n_seg←≢peaks spec
      ⎕←''
      ⎕←'First spectrum: ',(⍕n_max),' local maxima,  ',(⍕n_seg),' peak segments'

      d2←7 deriv2 spec
      ⎕←'2nd derivative range: ',(⍕⌊/d2),' to ',⍕⌈/d2

      projs←FisherProject A B
      pa←⊃projs
      pb←2⊃projs
      ⎕←''
      ⎕←'Fisher: mean(pa)=',(⍕(+/pa)÷≢pa),'   mean(pb)=',⍕(+/pb)÷≢pb

      coords←orloci A⍪B
      Aco←coords[⍳≢A;]
      Bco←coords[(≢A)+⍳≢B;]
      ⎕←''
      ⎕←'Orloci: A centroid=',⍕((+⌿Aco)÷≢Aco)
      ⎕←'        B centroid=',⍕((+⌿Bco)÷≢Bco)

      centers←2 kmean A⍪B
      truth←((≢A)⍴1),(≢B)⍴2
      acc←(+/truth=centers classify A⍪B)÷≢truth
      ⎕←''
      ⎕←'K-means accuracy (or 1−acc): ',⍕acc⌈1-acc

      w←A Ho B
      ⎕←''
      ⎕←'Ho-Kashyap: A correct=',(⍕+/0<(A,1)+.×w),'/',(⍕≢A),'   B correct=',(⍕+/0>(B,1)+.×w),'/',⍕≢B

      ssaResult←(2 20 30)ssaFisher A B
      ⎕←''
      ⎕←'SSA best features: ',(⍕⊃ssaResult),'   Fisher score: ',⍕2⊃ssaResult
    ∇

:EndNamespace
