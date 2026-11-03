#lang racket/base

(require racket/date
         racket/string
         "../errors/raise.rkt")

;;               ev-skip, ev-decide, ev-wait, ev-wait-done
(struct event (kind who why started ended duration-ms data redacted) #:transparent)

(define (make-event kind who why started ended duration-ms data redacted)
  (if (or (not (string? why)) (string=? (string-trim why) ""))
      (error-of 'err-blank-why who "the event record"
                "an event was made with no reason"
                "say why the event happened, at intent level")
      (event kind who why started ended duration-ms data redacted)))

(define (utc-now)
  (define d (seconds->date (current-seconds) #t))
  (format "~a-~a-~aT~a:~a:~aZ"
          (date-year d) (two-digits (date-month d)) (two-digits (date-day d))
          (two-digits (date-hour d)) (two-digits (date-minute d)) (two-digits (date-second d))))

(define (two-digits n)
  (if (< n 10) (format "0~a" n) (format "~a" n)))

(define (monotonic-ms)
  (inexact->exact (round (current-inexact-milliseconds))))

(provide event
         make-event
         utc-now
         monotonic-ms
         event-kind
         event-who
         event-why
         event-started
         event-ended
         event-duration-ms
         event-data
         event-redacted)
