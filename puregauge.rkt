#lang racket

;; This program simulates SU(GROUP) lattice gauge fields with the
;; simple Wilson action.
;; Converted to Racket from Creutz's C++ puregauge.cc

(define group 2)
(define dim 4)
(define size 8)
(define hits 10)
(define beta (make-parameter 2.3))

(define shape #(8 8 8 8))
(define shift #(1 8 64 512))

(define nsites (* size size size size))
(define nlinks (* dim nsites))
(define vectorlength (quotient nsites 2))

;; 48-bit LCG matching drand48
(define *rng-state* 80880398)

(define (srand48 seed)
  (set! *rng-state* (bitwise-and (+ 13070 (arithmetic-shift seed 16)) #xFFFFFFFFFFFF)))

(define (drand48)
  (let* ([a 25214903917]
         [c 11]
         [mask #xFFFFFFFFFFFF]
         [next (bitwise-and (+ (* a *rng-state*) c) mask)])
    (set! *rng-state* next)
    (/ (exact->inexact next) 281474976710656.0)))

;; Matrix operations: 2x2 complex matrix as #(m00 m01 m10 m11)
(define id-one (vector 1.0+0.0i 0.0+0.0i 0.0+0.0i 1.0+0.0i))
(define id-zero (vector 0.0+0.0i 0.0+0.0i 0.0+0.0i 0.0+0.0i))

(define (mat-mul a b)
  (let ([a00 (vector-ref a 0)] [a01 (vector-ref a 1)]
        [a10 (vector-ref a 2)] [a11 (vector-ref a 3)]
        [b00 (vector-ref b 0)] [b01 (vector-ref b 1)]
        [b10 (vector-ref b 2)] [b11 (vector-ref b 3)])
    (vector (+ (* a00 b00) (* a01 b10))
            (+ (* a00 b01) (* a01 b11))
            (+ (* a10 b00) (* a11 b10))
            (+ (* a10 b01) (* a11 b11)))))

(define (mat-add a b)
  (vector (+ (vector-ref a 0) (vector-ref b 0))
          (+ (vector-ref a 1) (vector-ref b 1))
          (+ (vector-ref a 2) (vector-ref b 2))
          (+ (vector-ref a 3) (vector-ref b 3))))

(define (conjugate-mat m)
  (vector (conjugate (vector-ref m 0))
          (conjugate (vector-ref m 2))
          (conjugate (vector-ref m 1))
          (conjugate (vector-ref m 3))))

(define (project m)
  (let* ([w00 (vector-ref m 0)]
         [w01 (vector-ref m 1)]
         [norm (sqrt (+ (expt (magnitude w00) 2)
                        (expt (magnitude w01) 2)))]
         [inv-norm (/ 1.0 norm)]
         [w00n (* w00 inv-norm)]
         [w01n (* w01 inv-norm)]
         [w10n (- (conjugate w01n))]
         [w11n (conjugate w00n)])
    (vector w00n w01n w10n w11n)))

(define (vtprod-elem a b)
  (let ([a00 (vector-ref a 0)] [a01 (vector-ref a 1)]
        [a10 (vector-ref a 2)] [a11 (vector-ref a 3)]
        [b00 (vector-ref b 0)] [b01 (vector-ref b 1)]
        [b10 (vector-ref b 2)] [b11 (vector-ref b 3)])
    (real-part (+ (* a00 b00) (* a01 b10) (* a10 b01) (* a11 b11)))))

(define (vtrace-elem m)
  (real-part (+ (vector-ref m 0) (vector-ref m 3))))

;; Global simulation data
(define ulinks (make-vector nlinks id-one))
(define parity (make-vector nsites 0))
(define table1 (make-vector vectorlength id-one))
(define table2 (make-vector vectorlength id-one))
(define mtemp (vector (make-vector vectorlength id-one)
                      (make-vector vectorlength id-one)
                      (make-vector vectorlength id-one)
                      (make-vector vectorlength id-one)
                      (make-vector vectorlength id-one)))
(define sold (make-vector vectorlength 0.0))
(define snew (make-vector vectorlength 0.0))
(define accepted (make-vector vectorlength 0))
(define myindex (make-vector vectorlength 0))

(define (cleanup msg)
  (displayln msg)
  (exit 0))

(define (split-coords s x)
  (let loop ([i (- dim 1)] [temp s])
    (cond
      [(> i 0)
       (let* ([sh (vector-ref shift i)]
              [q (quotient temp sh)]
              [r (remainder temp sh)])
         (vector-set! x i q)
         (loop (- i 1) r))]
      [else (vector-set! x 0 temp)])))

(define (siteindex x)
  (+ (vector-ref x 0)
     (* 8 (vector-ref x 1))
     (* 64 (vector-ref x 2))
     (* 512 (vector-ref x 3))))

(define (vshift n dx)
  (let ([y (make-vector dim 0)])
    (split-coords n y)
    (for ([i (in-range dim)])
      (let ([d (vector-ref dx i)])
        (unless (zero? d)
          (let ([yi (modulo (+ (vector-ref y i) d) (vector-ref shape i))])
            (vector-set! y i (if (< yi 0) (+ yi (vector-ref shape i)) yi))))))
    (siteindex y)))

(define (ishift n dir dist)
  (let ([dx (make-vector dim 0)])
    (vector-set! dx dir dist)
    (vshift n dx)))

(define (makeindex n ind)
  (let ([dx (make-vector dim 0)])
    (split-coords n dx)
    (let loop ([iv 0] [site 0])
      (when (< iv vectorlength)
        (if (zero? (vector-ref parity site))
            (begin
              (vector-set! ind iv (vshift site dx))
              (loop (+ iv 1) (+ site 1)))
            (loop iv (+ site 1)))))))

(define (vgroup g)
  (for ([iv (in-range vectorlength)])
    (vector-set! g iv (project (vector-ref g iv)))))

(define (vcopy g1 g2)
  (for ([iv (in-range vectorlength)])
    (vector-set! g2 iv (vector-ref g1 iv))))

(define (vprod g1 g2 g3)
  (for ([iv (in-range vectorlength)])
    (vector-set! g3 iv (mat-mul (vector-ref g1 iv) (vector-ref g2 iv)))))

(define (vsum g1 g2 g3)
  (for ([iv (in-range vectorlength)])
    (vector-set! g3 iv (mat-add (vector-ref g1 iv) (vector-ref g2 iv)))))

(define (vtprod g1 g2 s)
  (for ([iv (in-range vectorlength)])
    (vector-set! s iv (vtprod-elem (vector-ref g1 iv) (vector-ref g2 iv)))))

(define (vtrace g s)
  (for ([iv (in-range vectorlength)])
    (vector-set! s iv (vtrace-elem (vector-ref g iv)))))

(define (getlinks g lattice site link)
  (makeindex site myindex)
  (let ([sft (* nsites link)])
    (for ([iv (in-range vectorlength)])
      (vector-set! g iv (vector-ref lattice (+ (vector-ref myindex iv) sft))))))

(define (getconjugate g lattice site link)
  (makeindex site myindex)
  (let ([sft (* nsites link)])
    (for ([iv (in-range vectorlength)])
      (vector-set! g iv (conjugate-mat (vector-ref lattice (+ (vector-ref myindex iv) sft)))))))

(define (savelinks g lattice site link)
  (makeindex site myindex)
  (let ([sft (* nsites link)])
    (for ([iv (in-range vectorlength)])
      (vector-set! lattice (+ (vector-ref myindex iv) sft) (vector-ref g iv)))))

(define (metro old trial bias)
  (let ([expdeltas 0.0])
    (for ([iv (in-range vectorlength)])
      (let* ([sold-val (vector-ref sold iv)]
             [snew-val (vector-ref snew iv)]
             [temp (exp (* bias (- snew-val sold-val)))])
        (set! expdeltas (+ expdeltas temp))
        (vector-set! accepted iv (if (< (drand48) temp) 1 0))))
    (for ([iv (in-range vectorlength)])
      (when (= (vector-ref accepted iv) 1)
        (vector-set! sold iv (vector-ref snew iv))
        (vector-set! old iv (vector-ref trial iv))))
    (/ expdeltas (exact->inexact vectorlength))))

(define (ranmat g)
  (let ([idx (inexact->exact (floor (* vectorlength (drand48))))])
    (for ([iv (in-range vectorlength)])
      (when (>= idx vectorlength)
        (set! idx (- idx vectorlength)))
      (if (< (drand48) 0.5)
          (vector-set! g iv (vector-ref table1 idx))
          (vector-set! g iv (conjugate-mat (vector-ref table1 idx))))
      (set! idx (+ idx 1)))))

(define (vtable)
  (ranmat (vector-ref mtemp 0))
  (vprod table2 (vector-ref mtemp 0) table1)
  (vtrace table2 sold)
  (vtrace table1 snew)
  (metro table2 table1 (/ (* 6.0 (beta)) (exact->inexact group)))
  (vcopy table2 table1)
  (vcopy (vector-ref mtemp 0) table2)
  (vgroup table1))

(define (maketable)
  (for ([iv (in-range vectorlength)])
    (let ([b (/ (beta) (exact->inexact group))]
          [r1 (drand48)] [r2 (drand48)] [r3 (drand48)] [r4 (drand48)]
          [r5 (drand48)] [r6 (drand48)] [r7 (drand48)] [r8 (drand48)]
          [q1 (drand48)] [q2 (drand48)] [q3 (drand48)] [q4 (drand48)]
          [q5 (drand48)] [q6 (drand48)] [q7 (drand48)] [q8 (drand48)])
      (let ([t1 (vector (make-rectangular (+ b (- r1 0.5)) (- r5 0.5))
                        (make-rectangular (- r2 0.5) (- r6 0.5))
                        (make-rectangular (- r3 0.5) (- r7 0.5))
                        (make-rectangular (+ b (- r4 0.5)) (- r8 0.5)))]
            [t2 (vector (make-rectangular (+ b (- q1 0.5)) (- q5 0.5))
                        (make-rectangular (- q2 0.5) (- q6 0.5))
                        (make-rectangular (- q3 0.5) (- q7 0.5))
                        (make-rectangular (+ b (- q4 0.5)) (- q8 0.5)))])
        (vector-set! table1 iv t1)
        (vector-set! table2 iv t2))))
  (vgroup table1)
  (vgroup table2)
  (for ([i (in-range 50)])
    (vtable)))

(define (staple st lat site link)
  (for ([iv (in-range vectorlength)])
    (vector-set! st iv id-zero))
  (let ([site1 (ishift site link 1)])
    (for ([link1 (in-range dim)])
      (unless (= link1 link)
        (let ([site2 (ishift site link1 1)]
              [site4 (ishift site1 link1 -1)]
              [site5 (ishift site link1 -1)])
          (getlinks (vector-ref mtemp 0) lat site1 link1)
          (getconjugate (vector-ref mtemp 1) lat site2 link)
          (vprod (vector-ref mtemp 0) (vector-ref mtemp 1) (vector-ref mtemp 2))
          (getconjugate (vector-ref mtemp 0) lat site link1)
          (vprod (vector-ref mtemp 2) (vector-ref mtemp 0) (vector-ref mtemp 1))
          (vsum st (vector-ref mtemp 1) st)

          (getconjugate (vector-ref mtemp 0) lat site4 link1)
          (getconjugate (vector-ref mtemp 1) lat site5 link)
          (vprod (vector-ref mtemp 0) (vector-ref mtemp 1) (vector-ref mtemp 2))
          (getlinks (vector-ref mtemp 0) lat site5 link1)
          (vprod (vector-ref mtemp 2) (vector-ref mtemp 0) (vector-ref mtemp 1))
          (vsum st (vector-ref mtemp 1) st))))))

(define (monte lattice)
  (vtable)
  (let ([stot 0.0] [eds 0.0] [iacc 0])
    (for ([color (in-range 2)])
      (for ([link (in-range dim)])
        (staple (vector-ref mtemp 4) lattice color link)
        (getlinks (vector-ref mtemp 0) lattice color link)
        (vtprod (vector-ref mtemp 0) (vector-ref mtemp 4) sold)
        (for ([hit (in-range hits)])
          (ranmat (vector-ref mtemp 1))
          (vprod (vector-ref mtemp 0) (vector-ref mtemp 1) (vector-ref mtemp 2))
          (vtprod (vector-ref mtemp 2) (vector-ref mtemp 4) snew)
          (set! eds (+ eds (metro (vector-ref mtemp 0) (vector-ref mtemp 2) (/ (beta) (exact->inexact group)))))
          (for ([iv (in-range vectorlength)])
            (set! iacc (+ iacc (vector-ref accepted iv)))
            (set! stot (+ stot (vector-ref sold iv)))))
        (savelinks (vector-ref mtemp 0) lattice color link)))
    (let ([stot-val (/ stot (* 2.0 (- dim 1) nlinks group hits))]
          [acc-val (/ (exact->inexact iacc) (* nlinks hits))]
          [eds-val (/ eds (* 2.0 dim hits))])
      (printf "stot=~a, acc=~a, eds=~a~n"
              (real->decimal-string stot-val 6)
              (real->decimal-string acc-val 6)
              (real->decimal-string eds-val 6))
      stot-val)))

(define (overrelax lattice)
  (let ([stot 0.0] [eds 0.0] [iacc 0])
    (for ([color (in-range 2)])
      (for ([link (in-range dim)])
        (staple (vector-ref mtemp 4) lattice color link)
        (getlinks (vector-ref mtemp 0) lattice color link)
        (vcopy (vector-ref mtemp 4) (vector-ref mtemp 1))
        (vgroup (vector-ref mtemp 1))
        (vprod (vector-ref mtemp 0) (vector-ref mtemp 1) (vector-ref mtemp 2))
        (vprod (vector-ref mtemp 1) (vector-ref mtemp 2) (vector-ref mtemp 3))
        (for ([iv (in-range vectorlength)])
          (vector-set! (vector-ref mtemp 2) iv (conjugate-mat (vector-ref (vector-ref mtemp 3) iv))))
        (vtprod (vector-ref mtemp 0) (vector-ref mtemp 4) sold)
        (vtprod (vector-ref mtemp 2) (vector-ref mtemp 4) snew)
        (set! eds (+ eds (metro (vector-ref mtemp 0) (vector-ref mtemp 2) (/ (beta) (exact->inexact group)))))
        (for ([iv (in-range vectorlength)])
          (set! iacc (+ iacc (vector-ref accepted iv)))
          (set! stot (+ stot (vector-ref sold iv))))
        (savelinks (vector-ref mtemp 0) lattice color link)))
    (let ([stot-val (/ stot (* 2.0 (- dim 1) nlinks group))]
          [acc-val (/ (exact->inexact iacc) nlinks)]
          [eds-val (/ eds (* 2.0 dim))])
      (printf "stot=~a, acc=~a, eds=~a~n"
              (real->decimal-string stot-val 6)
              (real->decimal-string acc-val 6)
              (real->decimal-string eds-val 6))
      stot-val)))

(define (renorm l)
  (for ([octant (in-range (* 2 dim))])
    (let ([link (* octant vectorlength)])
      (for ([iv (in-range vectorlength)])
        (vector-set! l (+ link iv) (project (vector-ref l (+ link iv))))))))

(define (wilson-loop u x y)
  (let ([count 0] [result 0.0])
    (for ([color (in-range 2)])
      (for ([link1 (in-range dim)])
        (let ([start-link2 (if (= x y) (+ link1 1) 0)])
          (for ([link2 (in-range start-link2 dim)])
            (unless (= link1 link2)
              (set! count (+ count 1))
              (let ([corner (ishift (ishift color link1 x) link2 y)])
                (for ([iv (in-range vectorlength)])
                  (vector-set! (vector-ref mtemp 0) iv id-one)
                  (vector-set! (vector-ref mtemp 1) iv id-one)
                  (vector-set! (vector-ref mtemp 2) iv id-one)
                  (vector-set! (vector-ref mtemp 3) iv id-one))
                (for ([i (in-range x)])
                  (getlinks (vector-ref mtemp 4) u (ishift color link1 i) link1)
                  (vprod (vector-ref mtemp 0) (vector-ref mtemp 4) (vector-ref mtemp 0))
                  (getconjugate (vector-ref mtemp 4) u (ishift corner link1 (- (- 0 i) 1)) link1)
                  (vprod (vector-ref mtemp 2) (vector-ref mtemp 4) (vector-ref mtemp 2)))
                (for ([i (in-range y)])
                  (getlinks (vector-ref mtemp 4) u (ishift corner link2 (- i y)) link2)
                  (vprod (vector-ref mtemp 1) (vector-ref mtemp 4) (vector-ref mtemp 1))
                  (getconjugate (vector-ref mtemp 4) u (ishift color link2 (- (- y i) 1)) link2)
                  (vprod (vector-ref mtemp 3) (vector-ref mtemp 4) (vector-ref mtemp 3)))
                (vprod (vector-ref mtemp 0) (vector-ref mtemp 1) (vector-ref mtemp 0))
                (vprod (vector-ref mtemp 0) (vector-ref mtemp 2) (vector-ref mtemp 0))
                (vtprod (vector-ref mtemp 0) (vector-ref mtemp 3) sold)
                (for ([iv (in-range vectorlength)])
                  (set! result (+ result (vector-ref sold iv))))))))))
    (let ([res (/ result (* group vectorlength count))])
      (printf " ~a by ~a loop = ~a~n" x y (real->decimal-string res 6))
      res)))

(define (init)
  (srand48 1234)
  (for ([iv (in-range nsites)])
    (let ([x (make-vector dim 0)])
      (split-coords iv x)
      (let ([p 0])
        (for ([i (in-range dim)])
          (set! p (bitwise-xor p (vector-ref x i))))
        (vector-set! parity iv (bitwise-and p 1)))))
  (maketable)
  (displayln "initialization done"))

(define (main)
  (let ([args (current-command-line-arguments)])
    (when (> (vector-length args) 0)
      (beta (string->number (vector-ref args 0)))))
  (init)
  (printf "lattice size ~a by ~a by ~a by ~a~n" size size size size)
  (printf " vectorlength = ~a~n" vectorlength)
  (printf "group=SU(~a)   beta = ~a~n" group (real->decimal-string (beta) 4))
  (displayln "-----------------")

  (displayln "test monte")
  (for ([iter (in-range 5)])
    (let ([t0 (current-inexact-milliseconds)]
          [count 0])
      (for ([i (in-range 5)])
        (monte ulinks)
        (set! count (+ count 1)))
      (renorm ulinks)
      (let* ([t1 (current-inexact-milliseconds)]
             [elapsed (/ (- t1 t0) 1000.0)]
             [microsec (* (/ 1000000.0 (* count nlinks)) elapsed)])
        (printf "running at ~a microseconds per link~n" (real->decimal-string microsec 5))
        (wilson-loop ulinks 2 2))))

  (displayln "test overrelax")
  (for ([iter (in-range 5)])
    (let ([t0 (current-inexact-milliseconds)]
          [count 0])
      (for ([i (in-range 5)])
        (overrelax ulinks)
        (set! count (+ count 1)))
      (renorm ulinks)
      (let* ([t1 (current-inexact-milliseconds)]
             [elapsed (/ (- t1 t0) 1000.0)]
             [microsec (* (/ 1000000.0 (* count nlinks)) elapsed)])
        (printf "running at ~a microseconds per link~n" (real->decimal-string microsec 5)))))
  (cleanup "all done"))

(main)
