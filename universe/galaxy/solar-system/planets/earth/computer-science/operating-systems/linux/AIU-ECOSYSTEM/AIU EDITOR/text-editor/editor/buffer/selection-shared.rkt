#lang racket/base

(require racket/list
         racket/string)

(struct region (anchor point) #:transparent)

(define (start-region at)
  (region at at))

(define (grow-region the-region at)
  (region (region-anchor the-region) at))

(define (shrink-region the-region at)
  (region (region-anchor the-region) at))

(define (region-from a b)
  (if (<= a b) (region a b) (region b a)))

(define (region-text ask the-region)
  (if (not the-region)
      ""
      (let* ([ends (region-from (region-anchor the-region) (region-point the-region))])
        (ask "select" (hasheq 'from (number->string (region-anchor ends))
                              'to (number->string (region-point ends)))))))

(define (region-line the-region)
  (if (not the-region)
      "no selection"
      (format "selection: ~a to ~a" (region-anchor the-region) (region-point the-region))))

(provide region
         region-anchor
         region-point
         start-region
         grow-region
         shrink-region
         region-from
         region-text
         region-line)
