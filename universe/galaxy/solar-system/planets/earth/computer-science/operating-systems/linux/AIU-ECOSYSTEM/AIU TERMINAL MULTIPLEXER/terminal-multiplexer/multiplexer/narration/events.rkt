#lang racket/base

(provide (struct-out event)
         event-kinds
         event-kind?
         event-fields)

(struct event (run-id seq parent-id kind depth who what why how
                    inputs outputs result utc mono-ms duration-ms)
  #:transparent)

(define event-kinds
  '(START STEP INFO DECIDE SKIP PROGRESS END FAIL WARN WAIT WAIT-DONE))

(define (event-kind? k)
  (if (memq k event-kinds) #t #f))

(define event-fields
  '(run-id seq parent-id kind depth who what why how
    inputs outputs result utc mono-ms duration-ms))
