#!/usr/bin/env -S guile -s
!#

(use-modules (ice-9 format))

(define command-registry '())

(define (register-command! name kind doc)
  (set! command-registry
        (append command-registry
                (list (list name kind doc)))))

(define-syntax define-command
  (syntax-rules (long short)
    ((_ (name arg ...) long doc body ...)
     (begin
       (register-command! 'name 'long doc)
       (define (name arg ...) body ...)))
    ((_ (name arg ...) short doc body ...)
     (begin
       (register-command! 'name 'short doc)
       (define (name arg ...) body ...)))))

(define-syntax when-let
  (syntax-rules ()
    ((_ (name expr) body ...)
     (let ((tmp expr))
       (if tmp
           (let ((name tmp))
             body ...)
           #f)))))

(define-syntax swap!
  (syntax-rules ()
    ((_ left right)
     (let ((tmp left))
       (set! left right)
       (set! right tmp)))))

(define-command (configure target json) long
  "Pretend long-running configure command."
  (format #t "configuring ~a with ~a~%" target json))

(define-command (ping target) short
  "Pretend short status command."
  (format #t "ping ~a~%" target))

(format #t "Guile command registry:~%")
(for-each
 (lambda (entry)
   (format #t "  ~a~%" entry))
 command-registry)

(format #t "~%Running commands:~%")
(configure "mid-csp/subarray/01" "{scan: true}")
(ping "mid-csp/master/01")

(format #t "~%Hygiene demo:~%")
(let ((tmp 'outside)
      (a 10)
      (b 20))
  (swap! a b)
  (format #t "  a=~a b=~a tmp=~a~%" a b tmp))

(format #t "~%Binding macro demo:~%")
(when-let (n (string->number "42"))
  (format #t "  parsed value => ~a~%" n))
