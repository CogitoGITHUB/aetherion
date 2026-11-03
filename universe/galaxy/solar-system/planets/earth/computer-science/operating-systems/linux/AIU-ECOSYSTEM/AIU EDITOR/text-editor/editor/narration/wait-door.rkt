#lang racket/base

(require racket/string
         "events.rkt"
         "narration.rkt"
         "../errors/raise.rkt")

(define (wait-for who what why on-event)
  (if (or (blank? why) (blank? on-event))
      (error-of 'err-blank-why who "the wait door"
                "a wait was announced without a reason, or without the event that ends it"
                "say why the wait happens and name the event that ends it")
      (say 'ev-wait who (format "waiting for ~a: ~a; it ends on ~a" what why on-event))))

(define (wait-done who what on-event)
  (say 'ev-wait-done who (format "the wait for ~a ended on ~a" what on-event)))

(define (blank? s)
  (or (not (string? s)) (string=? (string-trim s) "")))

(provide wait-for
         wait-done)
