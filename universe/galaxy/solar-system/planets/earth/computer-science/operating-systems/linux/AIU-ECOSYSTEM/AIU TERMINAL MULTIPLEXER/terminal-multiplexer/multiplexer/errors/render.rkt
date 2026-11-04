#lang racket/base
(require "err.rkt")

(provide render-error)

(define (rule-part rule)
  (if rule (format " | rule: ~a" rule) ""))

(define (render-error e)
  (format "ERROR ~a | who: ~a | where: ~a | why: ~a~a"
          (mp-error-what e)
          (mp-error-who e)
          (mp-error-where e)
          (mp-error-why e)
          (rule-part (mp-error-rule e))))
