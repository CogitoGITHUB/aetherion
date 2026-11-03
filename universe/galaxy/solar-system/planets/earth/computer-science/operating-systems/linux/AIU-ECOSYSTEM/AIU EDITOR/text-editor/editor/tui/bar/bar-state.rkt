#lang racket/base

(define bar-place (box "bottom"))

(define bar-saved (box "bottom"))

(define bar-style (box "docked"))

(define bar-count (box 5))

(define focus-on (box #f))

(define bar-order (list "mode" "keys" "time" "save" "date"))

(define bar-places (list "bottom" "top" "left" "right" "sides"))

(define (bar-kname s) (if (string=? s "space") "SPC" s))


(provide bar-place bar-saved bar-style bar-count focus-on bar-order bar-places bar-kname)
