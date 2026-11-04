#lang racket/base
(require "err.rkt")

(provide raise-error)

(define (checked-field name v)
  (if (and (string? v) (not (blank-string? v)))
      v
      (error 'raise-error "an mp-error field is blank: ~a" name)))

(define (raise-error what who where why
                     #:rule [rule #f]
                     #:detail [detail #f])
  (raise (mp-error (checked-field 'what what)
                   (checked-field 'who who)
                   (checked-field 'where where)
                   (checked-field 'why why)
                   rule
                   detail)))
