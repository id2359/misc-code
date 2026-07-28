#!/usr/bin/env -S guile -s
!#

(use-modules (ice-9 format))

(define-syntax when
  (syntax-rules ()
    ((_ test body ...)
     (if test
         (begin body ...)
         #f))))

(define-syntax unless
  (syntax-rules ()
    ((_ test body ...)
     (if test
         #f
         (begin body ...)))))

(define-syntax when-let
  (syntax-rules ()
    ((_ (name expr) body ...)
     (let ((tmp expr))
       (if tmp
           (let ((name tmp))
             body ...)
           #f)))))

(define-syntax while
  (syntax-rules ()
    ((_ test body ...)
     (let loop ()
       (when test
         body ...
         (loop))))))

(define-syntax swap!
  (syntax-rules ()
    ((_ left right)
     (let ((tmp left))
       (set! left right)
       (set! right tmp)))))

(define (banner title)
  (format #t "~%== ~a ==~%" title))

(define (show label value)
  (format #t "~a => ~s~%" label value))

(banner "1. Simple source-to-source rewriting")
(unless (> 2 3)
  (format #t "unless expanded into an if/begin form and ran this body.~%"))

(banner "2. Binding introduction with a macro")
(when-let (digits (string->number "4096"))
  (show "Parsed number" digits)
  (show "Twice the number" (* 2 digits)))

(when-let (missing (string->number "not-a-number"))
  (show "This never prints" missing))

(banner "3. Code generation for a control structure")
(let ((n 0)
      (total 0))
  (while (< n 5)
    (set! total (+ total n))
    (set! n (+ n 1)))
  (show "Sum of 0..4" total))

(banner "4. Hygiene: macro temporaries do not capture your variables")
(let ((tmp 'outer-name)
      (x 10)
      (y 99))
  (swap! x y)
  (show "x after swap!" x)
  (show "y after swap!" y)
  (show "outer tmp is untouched" tmp))

(banner "5. Macros build new language forms")
(format #t "Macros transformed Scheme syntax before runtime, not just values at runtime.~%")
