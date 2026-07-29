#lang racket
;; =============================================================================
;;  control-dsl.rkt  —  A tiny block-diagram DSL for a control system, built
;;  with Racket macros.  Shows four ways macros simplify plant-control code:
;;    1. A declarative signal/block notation that reads like a block diagram.
;;    2. Compile-time wiring checks (unknown / misspelled ports are errors
;;       before the program ever runs).
;;    3. A `control-loop` macro that owns cross-cutting concerns — sample
;;       period, read→compute→write phasing, telemetry logging, and a
;;       watchdog — so individual blocks stay pure.
;;    4. A `pid` template macro whose literal gains let the expander generate
;;       closed-form, inlined update code (no per-tick dispatch).
;; =============================================================================
(require (for-syntax racket/base syntax/parse))

;; -----------------------------------------------------------------------------
;; Runtime: a "signal" is a mutable sample.  In real code this would be a
;; double-buffer, a DMA slot, or a lock-free queue — the DSL is agnostic.
;; -----------------------------------------------------------------------------
(struct sig (name [val #:mutable]) #:transparent)
(define (sig-ref s) (sig-val s))
(define (sig-set! s v) (set-sig-val! s v))
(define the-signals (make-hash))
(define (intern-sig! name) (hash-ref! the-signals name (λ () (sig name 0.0))))
(define (all-signals)
  (sort (hash-values the-signals) (λ (a b) (symbol<? (sig-name a) (sig-name b)))))

;; -----------------------------------------------------------------------------
;; 1) Compile-time registry of declared signals.  Macros expand top-to-bottom,
;;    so a `signal` declared above a `connect`/`block` is already known when
;;    the latter expands.
;; -----------------------------------------------------------------------------
(begin-for-syntax
  (define declared (make-hasheq))
  (define (declared? id) (hash-has-key? declared id))
  ;; literal-number syntax classes (not built into syntax-parse)
  (define-syntax-class real
    #:description "real number"
    (pattern n:number #:when (real? (syntax-e #'n))))
  (define-syntax-class integer
    #:description "integer"
    (pattern n:number #:when (exact-integer? (syntax-e #'n)))))

;; Declare a signal port: expands to a runtime definition AND registers the
;; name at compile time for later cross-checking.
(define-syntax (signal stx)
  (syntax-parse stx
    [(_ id:id)
     (hash-set! declared (syntax-e #'id) #t)
     #'(define id (intern-sig! 'id))]))

;; -----------------------------------------------------------------------------
;; 2) `connect` — wires src -> dst with a COMPILE-TIME existence check.
;;    (connect refernece error)  is a compile error pointed at the typo.
;; -----------------------------------------------------------------------------
(define connections '())
(define (add-connection! s d) (set! connections (cons (list s d) connections)))

(define-syntax (connect stx)
  (syntax-parse stx
    [(_ src:id dst:id)
     (unless (declared? (syntax-e #'src))
       (raise-syntax-error 'connect "unknown source signal" stx #'src))
     (unless (declared? (syntax-e #'dst))
       (raise-syntax-error 'connect "unknown destination signal" stx #'dst))
     #'(add-connection! 'src 'dst)]))

;; -----------------------------------------------------------------------------
;; 3) `block` — a computation: snapshot input signals, return a list of output
;;    values (one per declared output).  Outputs are checked declared at
;;    compile time.  The body is plain Racket, so any math/library drops in.
;;    NOTE: a signal used as an output must NOT also be listed as an input in
;;    the same block — that would shadow the output's struct.  Read persistent
;;    state via sig-ref on the struct instead (see `controller` below).
;; -----------------------------------------------------------------------------
(define-syntax (block stx)
  (syntax-parse stx
    [(_ name:id (in:id ...) (out:id ...) body:expr)
     (for ([o (in-list (syntax->list #'(out ...)))])
       (unless (declared? (syntax-e o))
         (raise-syntax-error 'block "undeclared output signal" stx o)))
     #'(define (name)
         (let ([in (sig-ref in)] ...)            ; snapshot inputs (numbers)
           (define outs (list->vector body))     ; body -> list of out values
           (for ([o (in-list (list out ...))]    ; out = sig structs (not inputs)
                 [i (in-naturals)])
             (sig-set! o (vector-ref outs i)))
           (void)))]))

;; -----------------------------------------------------------------------------
;; 4) `pid` — a template macro.  Gains are literals known at expansion time, so
;;    the generated arithmetic is closed-form and inlinable.  It reads the
;;    persistent integrator/prev-error STATE signals itself (they are outputs
;;    of the block, hence not passed as inputs), and returns a 3-element list:
;;    (control-effort new-integral new-prev-error).
;; -----------------------------------------------------------------------------
(define-syntax (pid stx)
  (syntax-parse stx
    [(_ kp:real ki:real kd:real dt:real e:expr int:id prev:id)
     #'(let* ([i0 (sig-ref int)]                 ; persistent state signals
              [p0 (sig-ref prev)]
              [new-i (+ i0 (* e dt))]
              [deriv (/ (- e p0) dt)]
              [u (+ (* kp e) (* ki new-i) (* kd deriv))])
         (list u new-i e))]))

;; -----------------------------------------------------------------------------
;; 5) `control-loop` — the cross-cutting engine.  One macro owns: the sample
;;    period, the compute phasing, per-tick telemetry, a watchdog that aborts
;;    if the guarded signal leaves a safe band, and the step cap.  None of this
;;    appears in the individual block definitions.
;; -----------------------------------------------------------------------------
(define-syntax (control-loop stx)
  (syntax-parse stx
    [(_ name:id period:real steps:integer guard:id body:expr ...)
     #'(define (name)
         (define dt period)
         (define t 0.0)
         (for ([step (in-range steps)])
           body ...                                ; compute phase (dataflow order)
           (printf "t=~a  " (~r t #:precision 3))  ; telemetry (cross-cutting)
           (for ([s (all-signals)])
             (printf "~a=~a  " (sig-name s) (~r (sig-ref s) #:precision 4)))
           (newline)
           (when (> (abs (sig-ref guard)) 100.0)  ; watchdog (cross-cutting)
             (error 'control-loop "WATCHDOG: ~a out of band at t=~a" 'guard t))
           (set! t (+ t dt))))]))

;; =============================================================================
;;  THE PLANT, IN THE DSL  —  reads almost like a block diagram in text form.
;;  Plant: a double integrator  x'' = u   (Euler, dt = 0.01).
;; =============================================================================
(signal reference)    ; setpoint
(signal error)        ; reference - position
(signal voltage)      ; controller output -> actuator
(signal integral)     ; PID integrator state (persistent)
(signal prev-err)     ; PID previous-error state (persistent)
(signal position)     ; plant output
(signal velocity)     ; plant internal state

(connect reference error)
(connect position error)

;; error = reference - position
(block compute-error (reference position) (error)
  (list (- reference position)))

;; controller: PID on the error; writes voltage and updates its own state.
(block controller (error) (voltage integral prev-err)
  (pid 4.0 0.3 1.0 0.01 error integral prev-err))

;; plant: dv = u*dt ; dx = v*dt   (double integrator, Euler)
(block plant (voltage) (position velocity)
  (let* ([v (+ (sig-ref velocity) (* 0.01 voltage))]
         [x (+ (sig-ref position) (* 0.01 v))])
    (list x v)))

;; step setpoint at t = 0
(sig-set! reference 1.0)

(control-loop run 0.01 80 position
  (compute-error) (controller) (plant))

(run)
