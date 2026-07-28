#lang racket

(require racket/format
         syntax/parse/define)

(define command-registry (make-hash))

(define-syntax-parser define-command
  [(_ (name:id arg:id ...)
      (~seq #:kind kind:id)
      (~seq #:doc doc:str)
      body:expr ...+)
   #:fail-unless (member (syntax-e #'kind) '(long short))
   "expected #:kind to be long or short"
   #'(begin
       (hash-set! command-registry 'name (hash "kind" 'kind "doc" doc))
       (define (name arg ...) body ...))])

(define-command (configure target json)
  #:kind long
  #:doc "Pretend long-running configure command."
  (printf "configuring ~a with ~a~n" target json))

(define-command (ping target)
  #:kind short
  #:doc "Pretend short status command."
  (printf "ping ~a~n" target))

(printf "Racket command registry:~n")
(for ([(name meta) (in-hash command-registry)])
  (printf "  ~a => ~a~n" name meta))

(printf "~nRunning commands:~n")
(configure "mid-csp/subarray/01" "{scan: true}")
(ping "mid-csp/master/01")

(printf "~nMacro-specific advantage demo:~n")
(printf "  Uncomment the bad example in this file to see syntax-parse reject it early.~n")

#|
(define-command (broken target)
  #:kind medium
  #:doc "This fails at macro-expansion time with a targeted error."
  (printf "never runs: ~a~n" target))
|#
