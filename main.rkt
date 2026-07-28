#lang racket

(require racket/format
         syntax/parse/define)

(provide (except-out (all-from-out racket) #%module-begin)
         (rename-out [finance-module-begin #%module-begin])
         capital
         price
         series
         buy
         sell
         units
         cash
         equity
         sma
         show-indicator
         rule
         if-crosses-above
         if-crosses-below
         holding-value
         report)

(define current-cash 0.0)
(define holdings (make-hash))
(define prices (make-hash))
(define histories (make-hash))

(define (->amount x)
  (exact->inexact x))

(define (reset-state!)
  (set! current-cash 0.0)
  (set! holdings (make-hash))
  (set! prices (make-hash))
  (set! histories (make-hash)))

(define (set-capital! amount)
  (set! current-cash (->amount amount)))

(define (set-price! asset amount)
  (define px (->amount amount))
  (hash-set! prices asset px)
  (hash-set! histories asset
             (append (hash-ref histories asset '()) (list px))))

(define (set-series! asset values)
  (define xs (map ->amount values))
  (when (null? xs)
    (error 'series "series for ~a cannot be empty" asset))
  (hash-set! histories asset xs)
  (hash-set! prices asset (last xs)))

(define (lookup-price asset)
  (hash-ref prices asset
            (lambda ()
              (error 'price "no price registered for asset ~a" asset))))

(define (lookup-history asset)
  (hash-ref histories asset
            (lambda ()
              (error 'history "no history registered for asset ~a" asset))))

(define (lookup-holding asset)
  (hash-ref holdings asset 0.0))

(define (units asset)
  (lookup-holding asset))

(define (cash)
  current-cash)

(define (equity)
  (portfolio-total))

(define (sma asset period)
  (define xs (lookup-history asset))
  (when (< (length xs) period)
    (error 'sma "not enough history for ~a period ~a" asset period))
  (/ (apply + (take-right xs period)) period))

(define (buy! asset units)
  (define qty (->amount units))
  (define px (lookup-price asset))
  (define cost (* qty px))
  (when (> cost current-cash)
    (error 'buy "insufficient cash for ~a: need ~a, have ~a"
           asset cost current-cash))
  (set! current-cash (- current-cash cost))
  (hash-set! holdings asset (+ (lookup-holding asset) qty)))

(define (sell! asset units)
  (define qty (->amount units))
  (define owned (lookup-holding asset))
  (when (> qty owned)
    (error 'sell "cannot sell ~a units of ~a; only have ~a"
           qty asset owned))
  (define px (lookup-price asset))
  (set! current-cash (+ current-cash (* qty px)))
  (hash-set! holdings asset (- owned qty)))

(define (holding-value! asset)
  (define qty (lookup-holding asset))
  (define px (lookup-price asset))
  (printf "~a => units ~a @ ~a => value ~a~n"
          asset (~r qty #:precision 4) (~r px #:precision 2) (~r (* qty px) #:precision 2)))

(define (portfolio-total)
  (+ current-cash
     (for/sum ([(asset qty) (in-hash holdings)])
       (* qty (lookup-price asset)))))

(define (report!)
  (printf "Finance report~n")
  (printf "  cash: ~a~n" (~r current-cash #:precision 2))
  (for ([asset (sort (hash-keys holdings) symbol<?)])
    (define qty (lookup-holding asset))
    (when (positive? qty)
      (holding-value! asset)))
  (printf "  total equity: ~a~n" (~r (portfolio-total) #:precision 2)))

(define (show-indicator! label value)
  (printf "  ~a: ~a~n" label (~r (->amount value) #:precision 4)))

(define-syntax-rule (finance-module-begin form ...)
  (#%module-begin
    (reset-state!)
    form ...
    (void)))

(define-syntax-parser capital
  [(_ amount:expr)
   #'(set-capital! amount)])

(define-syntax-parser price
  [(_ asset:id amount:expr)
   #'(set-price! 'asset amount)])

(define-syntax-parser series
  [(_ asset:id (value:expr ...))
   #'(set-series! 'asset (list value ...))])

(define-syntax-parser buy
  [(_ asset:id units:expr)
   #'(buy! 'asset units)])

(define-syntax-parser sell
  [(_ asset:id units:expr)
   #'(sell! 'asset units)])

(define-syntax-parser rule
  [(_ name:id body:expr ...+)
   #'(begin
       (printf "Rule ~a~n" 'name)
       body ...)])

(define-syntax-parser show-indicator
  [(_ label:str value:expr)
   #'(show-indicator! label value)])

(define-syntax-parser if-crosses-above
  [(_ asset:id fast:expr slow:expr body:expr ...+)
   #'(let* ([xs (lookup-history 'asset)]
            [f fast]
            [s slow])
       (when (< (length xs) (+ s 1))
         (error 'if-crosses-above "need at least slow+1 samples for ~a" 'asset))
       (define prev-xs (drop-right xs 1))
       (define prev-fast (/ (apply + (take-right prev-xs f)) f))
       (define prev-slow (/ (apply + (take-right prev-xs s)) s))
       (define now-fast (sma 'asset f))
       (define now-slow (sma 'asset s))
       (when (and (<= prev-fast prev-slow)
                  (> now-fast now-slow))
         body ...))])

(define-syntax-parser if-crosses-below
  [(_ asset:id fast:expr slow:expr body:expr ...+)
   #'(let* ([xs (lookup-history 'asset)]
            [f fast]
            [s slow])
       (when (< (length xs) (+ s 1))
         (error 'if-crosses-below "need at least slow+1 samples for ~a" 'asset))
       (define prev-xs (drop-right xs 1))
       (define prev-fast (/ (apply + (take-right prev-xs f)) f))
       (define prev-slow (/ (apply + (take-right prev-xs s)) s))
       (define now-fast (sma 'asset f))
       (define now-slow (sma 'asset s))
       (when (and (>= prev-fast prev-slow)
                  (< now-fast now-slow))
         body ...))])

(define-syntax-parser holding-value
  [(_ asset:id)
   #'(holding-value! 'asset)])

(define-syntax-parser report
  [(_)
   #'(report!)])
