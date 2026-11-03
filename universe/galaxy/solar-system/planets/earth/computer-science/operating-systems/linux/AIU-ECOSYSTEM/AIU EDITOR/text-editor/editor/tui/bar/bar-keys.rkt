#lang racket/base
;; bar-keys.rkt: One job: the keys of the bar layer and its level adjuster, as data.

;; bar-keys are the keys of the bar layer: the places of the bar, the style, the
;; hide key and the key that enters the level adjuster.
(define bar-keys
  (list (list "p" "bar-place-next")
        (list "b" "bar-bottom")
        (list "u" "bar-top")
        (list "l" "bar-left")
        (list "r" "bar-right")
        (list "s" "bar-sides")
        (list "d" "bar-style")
        (list "x" "bar-hide") (list "left" "bar-left") (list "right" "bar-right") (list "up" "bar-top") (list "down" "bar-bottom")
        (list "v" "bar-level-mode")
        (list "escape" "visual-mode")))

;; bar-level-keys are the keys of the level adjuster: h hides one part of the bar,
;; t shows one more, and escape goes back to the bar layer.
(define bar-level-keys
  (list (list "h" "bar-less")
        (list "t" "bar-more") (list "left" "bar-less") (list "right" "bar-more")
        (list "escape" "bar-mode")))

(provide bar-keys bar-level-keys)
