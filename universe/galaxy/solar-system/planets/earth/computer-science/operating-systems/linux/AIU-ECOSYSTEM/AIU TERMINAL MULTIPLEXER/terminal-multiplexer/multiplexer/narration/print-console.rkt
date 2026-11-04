#lang racket/base
(require "events.rkt")

(provide print-event
         print-line)

(define (indent-for depth)
  (if (and (integer? depth) (> depth 0))
      (make-string (* 2 depth) #\space)
      ""))

(define (has-value? v)
  (and v (not (equal? v ""))))

(define (field-part label v)
  (if (has-value? v) (format " | ~a: ~a" label v) ""))

(define (event-line e)
  (format "~a[~a +~as] ~a ~a | what: ~a~a~a"
          (indent-for (event-depth e))
          (event-utc e)
          (real->decimal-string (/ (event-mono-ms e) 1000.0) 3)
          (event-kind e)
          (event-who e)
          (event-what e)
          (field-part "why" (event-why e))
          (field-part "how" (event-how e))))

(define (print-event e)
  (displayln (event-line e))
  (flush-output))

(define (print-line s)
  (displayln s)
  (flush-output))
