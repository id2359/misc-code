#lang racket

;; =============================================================================
;; control-dsl-examples.rkt
;;
;; Runnable examples for the tiny Racket control-system DSL in control-dsl.rkt.
;;
;; The original source is an executable demonstration rather than a library: it
;; defines one plant and immediately calls (run).  To keep this examples file
;; independent and runnable, the same DSL core is placed in the `dsl` submodule.
;; Each example is isolated in its own submodule so its signal registry and
;; telemetry remain easy to read.
;;
;; Run one example with:
;;
;;   racket control-dsl-examples.rkt thermostat
;;   racket control-dsl-examples.rkt cruise
;;   racket control-dsl-examples.rkt tank
;;   racket control-dsl-examples.rkt cascade
;;
;; Run without an argument to see the list of examples.
;; =============================================================================

(module dsl racket
  (require (for-syntax racket/base syntax/parse))

  (provide signal
           connect
           block
           pid
           control-loop
           sig-ref
           sig-set!
           connections)

  ;; A signal is a mutable sample shared by the blocks that name it.
  (struct sig (name [val #:mutable]) #:transparent)
  (define (sig-ref s) (sig-val s))
  (define (sig-set! s v) (set-sig-val! s v))

  (define the-signals (make-hash))
  (define (intern-sig! name)
    (hash-ref! the-signals name (lambda () (sig name 0.0))))
  (define (all-signals)
    (sort (hash-values the-signals)
          (lambda (a b) (symbol<? (sig-name a) (sig-name b)))))

  ;; Compile-time registry used by `signal`, `connect`, and `block`.
  (begin-for-syntax
    (define declared (make-hasheq))
    (define (declared? id) (hash-has-key? declared id))

    (define-syntax-class real
      #:description "real number"
      (pattern n:number #:when (real? (syntax-e #'n))))

    (define-syntax-class integer
      #:description "integer"
      (pattern n:number #:when (exact-integer? (syntax-e #'n)))))

  (define-syntax (signal stx)
    (syntax-parse stx
      [(_ id:id)
       (hash-set! declared (syntax-e #'id) #t)
       #'(define id (intern-sig! 'id))]))

  ;; Connections are checked and recorded as diagram metadata.  Values actually
  ;; move because blocks read and write the shared signals in loop-body order.
  (define connections '())
  (define (add-connection! source destination)
    (set! connections (cons (list source destination) connections)))

  (define-syntax (connect stx)
    (syntax-parse stx
      [(_ source:id destination:id)
       (unless (declared? (syntax-e #'source))
         (raise-syntax-error 'connect "unknown source signal" stx #'source))
       (unless (declared? (syntax-e #'destination))
         (raise-syntax-error 'connect "unknown destination signal"
                             stx
                             #'destination))
       #'(add-connection! 'source 'destination)]))

  ;; A block snapshots its inputs, evaluates one Racket expression returning a
  ;; list, then writes the list elements to its output signals.
  (define-syntax (block stx)
    (syntax-parse stx
      [(_ name:id (input:id ...) (output:id ...) body:expr)
       (for ([out (in-list (syntax->list #'(output ...)))])
         (unless (declared? (syntax-e out))
           (raise-syntax-error 'block "undeclared output signal" stx out)))
       #'(define (name)
           (let ([input (sig-ref input)] ...)
             (define outputs (list->vector body))
             (for ([out-signal (in-list (list output ...))]
                   [i (in-naturals)])
               (sig-set! out-signal (vector-ref outputs i)))
             (void)))]))

  ;; Compile-time PID template.  The integral and previous-error signals are
  ;; persistent output-state signals and therefore are read with `sig-ref`.
  (define-syntax (pid stx)
    (syntax-parse stx
      [(_ kp:real ki:real kd:real dt:real error:expr integral:id previous:id)
       #'(let* ([old-integral (sig-ref integral)]
                [old-error (sig-ref previous)]
                [new-integral (+ old-integral (* error dt))]
                [derivative (/ (- error old-error) dt)]
                [control (+ (* kp error)
                            (* ki new-integral)
                            (* kd derivative))])
           (list control new-integral error))]))

  ;; Fixed-period simulation/control engine, including telemetry and watchdog.
  (define-syntax (control-loop stx)
    (syntax-parse stx
      [(_ name:id period:real steps:integer guard:id body:expr ...)
       #'(define (name)
           (define dt period)
           (define t 0.0)
           (for ([step (in-range steps)])
             body ...
             (printf "t=~a  " (~r t #:precision 3))
             (for ([sample (all-signals)])
               (printf "~a=~a  "
                       (sig-name sample)
                       (~r (sig-ref sample) #:precision 4)))
             (newline)
             (when (> (abs (sig-ref guard)) 100.0)
               (error 'control-loop
                      "WATCHDOG: ~a out of band at t=~a"
                      'guard
                      t))
             (set! t (+ t dt))))])))

;; =============================================================================
;; Example 1: thermostat controlling a first-order room-temperature model
;;
;; Demonstrates a simple proportional controller, actuator saturation, an
;; ambient-temperature input, and a plant with heat gain and heat loss.
;; =============================================================================
(module thermostat racket
  (require (submod ".." dsl))

  (define (clamp value low high)
    (min high (max low value)))

  (signal th-setpoint)
  (signal th-ambient)
  (signal th-temperature)
  (signal th-error)
  (signal th-heater)

  (connect th-setpoint th-error)
  (connect th-temperature th-error)
  (connect th-error th-heater)
  (connect th-heater th-temperature)
  (connect th-ambient th-temperature)

  (block th-compute-error (th-setpoint th-temperature) (th-error)
    (list (- th-setpoint th-temperature)))

  ;; Heater command is limited to the physical range 0.0 .. 1.0.
  (block th-controller (th-error) (th-heater)
    (list (clamp (* 0.50 th-error) 0.0 1.0)))

  ;; dT/dt = heat-input + heat-loss-to-ambient
  (block th-room (th-heater th-ambient) (th-temperature)
    (let* ([old-temperature (sig-ref th-temperature)]
           [heat-input (* 0.50 th-heater)]
           [heat-loss (/ (- th-ambient old-temperature) 45.0)]
           [new-temperature
            (+ old-temperature (* 1.0 (+ heat-input heat-loss)))])
      (list new-temperature)))

  (sig-set! th-setpoint 22.0)
  (sig-set! th-ambient 10.0)
  (sig-set! th-temperature 10.0)

  (control-loop run-thermostat 1.0 50 th-temperature
    (th-compute-error)
    (th-controller)
    (th-room))

  (displayln "THERMOSTAT: target 22 C, ambient 10 C")
  (run-thermostat))

;; =============================================================================
;; Example 2: PI cruise control for a simplified vehicle
;;
;; Demonstrates reuse of `pid`, output saturation, a constant road-load term,
;; and a first-order speed plant.
;; =============================================================================
(module cruise racket
  (require (submod ".." dsl))

  (define (clamp value low high)
    (min high (max low value)))

  (signal cruise-target-speed)
  (signal cruise-speed)
  (signal cruise-error)
  (signal cruise-throttle)
  (signal cruise-integral)
  (signal cruise-prev-error)
  (signal cruise-road-load)

  (connect cruise-target-speed cruise-error)
  (connect cruise-speed cruise-error)
  (connect cruise-error cruise-throttle)
  (connect cruise-throttle cruise-speed)
  (connect cruise-road-load cruise-speed)

  (block cruise-compute-error
         (cruise-target-speed cruise-speed)
         (cruise-error)
    (list (- cruise-target-speed cruise-speed)))

  ;; PI control: kd is zero.  The PID macro still maintains previous error,
  ;; which makes it easy to add derivative action later.
  (block cruise-controller
         (cruise-error)
         (cruise-throttle cruise-integral cruise-prev-error)
    (let ([result
           (pid 0.05 0.005 0.0 0.10
                cruise-error
                cruise-integral
                cruise-prev-error)])
      (list (clamp (first result) 0.0 1.0)
            (second result)
            (third result))))

  ;; acceleration = engine force - drag - road load
  (block cruise-vehicle
         (cruise-throttle cruise-road-load)
         (cruise-speed)
    (let* ([old-speed (sig-ref cruise-speed)]
           [acceleration (- (* 5.0 cruise-throttle)
                            (* 0.08 old-speed)
                            cruise-road-load)]
           [new-speed (max 0.0 (+ old-speed (* 0.10 acceleration)))])
      (list new-speed)))

  (sig-set! cruise-target-speed 20.0) ; metres per second
  (sig-set! cruise-speed 0.0)
  (sig-set! cruise-road-load 0.40)

  (control-loop run-cruise 0.10 200 cruise-speed
    (cruise-compute-error)
    (cruise-controller)
    (cruise-vehicle))

  (displayln "CRUISE CONTROL: target 20 m/s with constant road load")
  (run-cruise))

;; =============================================================================
;; Example 3: liquid-tank level regulation
;;
;; Demonstrates a nonlinear plant: gravity-driven outflow is proportional to
;; sqrt(level).  The PI controller commands a bounded inlet pump.
;; =============================================================================
(module tank racket
  (require (submod ".." dsl))

  (define (clamp value low high)
    (min high (max low value)))

  (signal tank-setpoint)
  (signal tank-level)
  (signal tank-error)
  (signal tank-pump-flow)
  (signal tank-integral)
  (signal tank-prev-error)
  (signal tank-outlet-factor)

  (connect tank-setpoint tank-error)
  (connect tank-level tank-error)
  (connect tank-error tank-pump-flow)
  (connect tank-pump-flow tank-level)
  (connect tank-outlet-factor tank-level)

  (block tank-compute-error (tank-setpoint tank-level) (tank-error)
    (list (- tank-setpoint tank-level)))

  (block tank-controller
         (tank-error)
         (tank-pump-flow tank-integral tank-prev-error)
    (let ([result
           (pid 0.90 0.20 0.0 0.10
                tank-error
                tank-integral
                tank-prev-error)])
      (list (clamp (first result) 0.0 3.0)
            (second result)
            (third result))))

  ;; d(level)/dt = inlet - outlet-factor * sqrt(level)
  (block tank-plant
         (tank-pump-flow tank-outlet-factor)
         (tank-level)
    (let* ([old-level (sig-ref tank-level)]
           [outflow (* tank-outlet-factor (sqrt (max 0.0 old-level)))]
           [new-level
            (max 0.0 (+ old-level (* 0.10 (- tank-pump-flow outflow))))])
      (list new-level)))

  (sig-set! tank-setpoint 6.0)
  (sig-set! tank-level 1.0)
  (sig-set! tank-outlet-factor 0.45)

  (control-loop run-tank 0.10 100 tank-level
    (tank-compute-error)
    (tank-controller)
    (tank-plant))

  (displayln "TANK LEVEL: target level 6, nonlinear gravity outflow")
  (run-tank))

;; =============================================================================
;; Example 4: cascaded position and velocity servo
;;
;; The outer P loop converts position error into a velocity reference.  The
;; inner PID loop converts velocity error into motor command.  This demonstrates
;; how the ordered block calls in `control-loop` express a dataflow schedule.
;; =============================================================================
(module cascade racket
  (require (submod ".." dsl))

  (define (clamp value low high)
    (min high (max low value)))

  (signal servo-position-reference)
  (signal servo-position)
  (signal servo-position-error)
  (signal servo-velocity-reference)
  (signal servo-velocity)
  (signal servo-velocity-error)
  (signal servo-motor-command)
  (signal servo-inner-integral)
  (signal servo-inner-prev-error)

  (connect servo-position-reference servo-position-error)
  (connect servo-position servo-position-error)
  (connect servo-position-error servo-velocity-reference)
  (connect servo-velocity-reference servo-velocity-error)
  (connect servo-velocity servo-velocity-error)
  (connect servo-velocity-error servo-motor-command)
  (connect servo-motor-command servo-velocity)
  (connect servo-velocity servo-position)

  (block servo-compute-position-error
         (servo-position-reference servo-position)
         (servo-position-error)
    (list (- servo-position-reference servo-position)))

  ;; Outer-loop P controller.  The velocity request is deliberately limited.
  (block servo-position-controller
         (servo-position-error)
         (servo-velocity-reference)
    (list (clamp (* 1.50 servo-position-error) -3.0 3.0)))

  (block servo-compute-velocity-error
         (servo-velocity-reference servo-velocity)
         (servo-velocity-error)
    (list (- servo-velocity-reference servo-velocity)))

  (block servo-velocity-controller
         (servo-velocity-error)
         (servo-motor-command
          servo-inner-integral
          servo-inner-prev-error)
    (let ([result
           (pid 0.80 0.60 0.05 0.02
                servo-velocity-error
                servo-inner-integral
                servo-inner-prev-error)])
      (list (clamp (first result) -2.0 2.0)
            (second result)
            (third result))))

  ;; Damped unit-mass servo: acceleration = motor gain * u - damping * v.
  (block servo-plant
         (servo-motor-command)
         (servo-position servo-velocity)
    (let* ([old-position (sig-ref servo-position)]
           [old-velocity (sig-ref servo-velocity)]
           [acceleration (- (* 4.0 servo-motor-command)
                            (* 1.20 old-velocity))]
           [new-velocity (+ old-velocity (* 0.02 acceleration))]
           [new-position (+ old-position (* 0.02 new-velocity))])
      (list new-position new-velocity)))

  (sig-set! servo-position-reference 5.0)
  (sig-set! servo-position 0.0)
  (sig-set! servo-velocity 0.0)

  (control-loop run-cascade 0.02 150 servo-position
    (servo-compute-position-error)
    (servo-position-controller)
    (servo-compute-velocity-error)
    (servo-velocity-controller)
    (servo-plant))

  (displayln "CASCADED SERVO: outer position loop, inner velocity loop")
  (run-cascade))

(module+ main
  (define arguments (vector->list (current-command-line-arguments)))

  (define (show-help)
    (displayln "Usage: racket control-dsl-examples.rkt EXAMPLE")
    (displayln "")
    (displayln "Examples:")
    (displayln "  thermostat  P control of a first-order heated room")
    (displayln "  cruise      PI cruise control with drag and road load")
    (displayln "  tank        PI control of a nonlinear liquid tank")
    (displayln "  cascade     cascaded position/velocity servo"))

  (cond
    [(null? arguments)
     (show-help)]
    [(not (= (length arguments) 1))
     (show-help)
     (exit 2)]
    [else
     (case (string->symbol (car arguments))
       [(thermostat)
        (dynamic-require '(submod ".." thermostat) #f)]
       [(cruise)
        (dynamic-require '(submod ".." cruise) #f)]
       [(tank)
        (dynamic-require '(submod ".." tank) #f)]
       [(cascade)
        (dynamic-require '(submod ".." cascade) #f)]
       [else
        (eprintf "Unknown example: ~a\n\n" (car arguments))
        (show-help)
        (exit 2)])]))
