#lang racket/base

(require "err.rkt")

(define (err-line e)
  (format "ERR ~a at ~a: ~a: ~a; what to do: ~a"
          (err-who e) (err-where e) (err-kind e) (err-what e) (err-what-to-do e)))

(provide err-line)
