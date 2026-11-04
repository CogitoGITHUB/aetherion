#lang racket/base

(define pin-keys
  (list (list "a" "pin-add") (list "d" "pin-delete") (list "h" "pin-prev") (list "t" "pin-next")
        (list "u" "pin-top") (list "b" "pin-bottom") (list "n" "pin-earlier") (list "s" "pin-later")
        (list "x" "pin-hide") (list "left" "pin-prev") (list "up" "pin-prev") (list "right" "pin-next") (list "down" "pin-next") (list "f" "pin-keep") (list "escape" "visual-mode")))

(provide pin-keys)
