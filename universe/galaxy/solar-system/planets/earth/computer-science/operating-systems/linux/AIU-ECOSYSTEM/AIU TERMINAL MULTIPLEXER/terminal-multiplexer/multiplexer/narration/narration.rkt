#lang racket/base
(require "events.rkt"
         "print-console.rkt"
         "../errors/err.rkt"
         "../errors/raise.rkt")

(provide (struct-out run)
         open-run
         narrate
         narrate-step
         narrate-note
         narrate-warn
         narrate-skip
         narrate-decide
         narrate-end
         mono-ms
         event-id)

(struct run (name id seq started-ms) #:mutable)

(define (two-digit n)
  (if (< n 10) (format "0~a" n) (format "~a" n)))

(define (utc-stamp)
  (define d (seconds->date (current-seconds)))
  (format "~a:~a:~aZ"
          (two-digit (date-hour d))
          (two-digit (date-minute d))
          (two-digit (date-second d))))

(define (mono-ms)
  (current-inexact-monotonic-milliseconds))

(define (next-seq r)
  (define n (add1 (run-seq r)))
  (set-run-seq! r n)
  n)

(define (why-required? kind)
  (if (memq kind '(STEP DECIDE SKIP FAIL WAIT WAIT-DONE)) #t #f))

(define (require-why kind why where)
  (when (why-required? kind)
    (unless (and (string? why) (not (blank-string? why)))
      (raise-error "a narration reason was blank"
                   "narration/narrate"
                   where
                   "no reason was given; why is mandatory on step, decide, skip, fail and wait"
                   #:rule 'narration/why-mandatory))))

(define (event-id e)
  (format "~a#~a" (event-run-id e) (event-seq e)))

(define (narrate r kind what
                 #:who [who (run-name r)]
                 #:why [why #f]
                 #:how [how #f]
                 #:result [result #f]
                 #:depth [depth 0]
                 #:parent [parent #f]
                 #:duration-ms [duration-ms 0])
  (require-why kind why what)
  (define e (event (format "~a#~a" (run-name r) (run-id r))
                   (next-seq r)
                   parent
                   kind
                   depth
                   who
                   what
                   why
                   how
                   #f
                   #f
                   result
                   (utc-stamp)
                   (- (mono-ms) (run-started-ms r))
                   duration-ms))
  (print-event e)
  e)

(define (open-run name)
  (define r (run name (random 1000000) 0 (mono-ms)))
  (narrate r 'START name #:why "the run was asked to start" #:how "open-run")
  r)

(define (narrate-step r what #:why why #:how [how #f] #:depth [depth 0])
  (narrate r 'STEP what #:why why #:how how #:depth depth))

(define (narrate-note r what #:why [why #f])
  (narrate r 'INFO what #:why why))

(define (narrate-warn r what #:why [why #f])
  (narrate r 'WARN what #:why why))

(define (narrate-skip r what #:why why)
  (narrate r 'SKIP what #:why why))

(define (narrate-decide r what #:why why #:result [result #f])
  (narrate r 'DECIDE what #:why why #:result result))

(define (narrate-end r #:result [result #f])
  (narrate r 'END "the run ends" #:why "the work finished" #:result result))
