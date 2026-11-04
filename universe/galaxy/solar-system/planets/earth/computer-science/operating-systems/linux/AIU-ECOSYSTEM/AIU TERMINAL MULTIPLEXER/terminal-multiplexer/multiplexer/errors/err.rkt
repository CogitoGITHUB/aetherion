#lang racket/base

(define (blank-string? s)
  (and (string? s)
       (for/and ([c (in-string s)]) (char-whitespace? c))))

(provide (struct-out mp-error)
         blank-string?)

(struct mp-error (what who where why rule detail) #:transparent)

(define (error-complete? e)
  (and (string? (mp-error-what e)) (not (blank-string? (mp-error-what e)))
       (string? (mp-error-who e)) (not (blank-string? (mp-error-who e)))
       (string? (mp-error-where e)) (not (blank-string? (mp-error-where e)))
       (string? (mp-error-why e)) (not (blank-string? (mp-error-why e)))))
