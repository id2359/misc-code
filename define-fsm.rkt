#lang racket

(require (for-syntax racket/base syntax/parse))

;; ============================================================
;; Tiny State-Machine DSL
;; ============================================================
;; Transforms declarative transition tables into efficient
;; case-dispatch functions.

(define-syntax (define-fsm stx)
  (syntax-parse stx
    [(_ name:id
        #:start start:id
        [state:id ((evt:id -> tgt:id) ...)] ...)
     
     ;; Generate a transition function + a start-state constant
     #'(begin
         (define name-start (quote start))
         
         (define (name current-state input)
           (case current-state
             ;; One clause per state
             [(state) 
              (case input
                ;; One clause per transition
                [(evt) (quote tgt)] ...
                [else (error (quote name)
                             "invalid event ~a in state ~a"
                             input (quote state))])] ...
             [else (error (quote name)
                          "unknown state ~a"
                          current-state)])))]))

;; ------------------------------------------------------------
;; Example: A turnstile
;; ------------------------------------------------------------
(define-fsm turnstile
  #:start locked
  [locked   ((coin  -> unlocked)
            (push  -> locked))]
  [unlocked ((coin  -> unlocked)
             (push  -> locked))])

;; Usage
(turnstile 'locked 'coin)     ; => 'unlocked
(turnstile 'unlocked 'push)   ; => 'locked
(turnstile 'locked 'push)     ; => 'locked
turnstile-start               ; => 'locked

;; This raises a run-time error:
;; (turnstile 'locked 'bad-event)
