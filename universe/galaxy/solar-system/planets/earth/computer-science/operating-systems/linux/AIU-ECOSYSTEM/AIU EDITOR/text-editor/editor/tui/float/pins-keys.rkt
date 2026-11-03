#lang racket/base
;; pins-keys.rkt: One job: the keys of the pin layer, as data.

;; pin-keys are the keys of the pin layer: a adds the block at the point, d deletes the selected pin, h and t select, u and b put it on the top or bottom edge, n and s reorder, x hides, f keeps it in focus mode, escape leaves.
(define pin-keys
  (list (list "a" "pin-add") (list "d" "pin-delete") (list "h" "pin-prev") (list "t" "pin-next")
        (list "u" "pin-top") (list "b" "pin-bottom") (list "n" "pin-earlier") (list "s" "pin-later")
        (list "x" "pin-hide") (list "left" "pin-prev") (list "up" "pin-prev") (list "right" "pin-next") (list "down" "pin-next") (list "f" "pin-keep") (list "escape" "visual-mode")))

(provide pin-keys)
