#lang racket/base

(require "err.rkt")

(define (raise-error e)
  (raise (exn:fail:editor (err-what e) (current-continuation-marks) e)))

(define (error-of kind who where what what-to-do)
  (raise-error (err kind who where what what-to-do)))

(provide raise-error
         error-of)
