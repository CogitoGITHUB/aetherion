#lang racket/base
;; One job: the state of the bar: where it stands, its style, how many parts show and whether focus mode hides it.

;; bar-place holds where the bar stands: bottom, top, left, right, sides or hidden.
(define bar-place (box "bottom"))

;; bar-saved holds the place the bar had before it was hidden.
(define bar-saved (box "bottom"))

;; bar-style holds docked or floating, for the side places.
(define bar-style (box "docked"))

;; bar-count holds how many parts show, from 0 to 5.
(define bar-count (box 5))

;; focus-on holds whether focus mode hides the bar, the tabs and the one line.
(define focus-on (box #f))

;; bar-order are the parts in the order the level adds them.
(define bar-order (list "mode" "keys" "time" "save" "date"))

;; bar-places are the places the place key goes through.
(define bar-places (list "bottom" "top" "left" "right" "sides"))

;; bar-kname answers the name of a key as shown: the space key is SPC.
(define (bar-kname s) (if (string=? s "space") "SPC" s))


(provide bar-place bar-saved bar-style bar-count focus-on bar-order bar-places bar-kname)
