#lang racket/base
;; One job: a run's voice — open, step, note, warn, skip, decide.

(require "events.rkt"
         "print-console.rkt")

(define (open-run who why) (say 'ev-open who why))

(define (step who why) (say 'ev-step who why))

(define (note who why) (say 'ev-note who why))

(define (warn who why) (say 'ev-warn who why))

;; skip says what was not done, and why it was not done.
(define (skip who why) (say 'ev-skip who why))

(define (decide who why) (say 'ev-decide who why))

(define (say kind who why)
  (print-event (make-event kind who why (utc-now) #f #f #f #f)))

(provide open-run
         say
         step
         note
         warn
         skip
         decide)
