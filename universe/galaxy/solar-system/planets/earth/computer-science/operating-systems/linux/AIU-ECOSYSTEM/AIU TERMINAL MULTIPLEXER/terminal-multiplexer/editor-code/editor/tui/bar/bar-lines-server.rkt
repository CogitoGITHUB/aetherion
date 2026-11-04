#lang racket/base
(require racket/list racket/string "bar-rows.rkt" "bar-state.rkt")

(define (serve)
  (define line (read-line))
  (unless (eof-object? line)
    (define parts (string-split line "\t" #:trim? #f))
    (define layer (list-ref parts 0))
    (define short (list-ref parts 1))
    (define width (string->number (list-ref parts 2)))
    (define names (take bar-order (min (length bar-order) (max 0 (unbox bar-count)))))
    (for ([row (in-list (bar-rows layer short null #f width names))])
      (displayln row))
    (displayln "")
    (flush-output)
    (serve)))

(module+ main (serve))
