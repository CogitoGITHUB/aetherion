#lang racket/base
(require "../errors/err.rkt"
         "../errors/raise.rkt")

(provide (struct-out cancel-state)
         make-cancel
         cancel!
         cancelled?
         cancel-why
         check-cancel!
         cancellable)

(struct cancel-state (flag why) #:mutable)

(define (make-cancel)
  (cancel-state #f #f))

(define (cancel! c why)
  (when (blank-string? why)
    (raise-error "a cancellation reason was blank"
                 "machine/cancel cancel!"
                 "the cancel state"
                 "no reason was given; someone must be able to say why work stopped"
                 #:rule 'cancel/why-mandatory))
  (set-cancel-state-flag! c #t)
  (set-cancel-state-why! c why))

(define (cancelled? c)
  (cancel-state-flag c))

(define (cancel-why c)
  (cancel-state-why c))

(define (check-cancel! c where)
  (when (cancelled? c)
    (raise-error "the work was cancelled"
                 "machine/cancel check-cancel!"
                 where
                 (cancel-why c)
                 #:rule 'cancel/cancelled)))

(define (cancellable c where thunk)
  (check-cancel! c where)
  (define v (thunk))
  (check-cancel! c where)
  v)
