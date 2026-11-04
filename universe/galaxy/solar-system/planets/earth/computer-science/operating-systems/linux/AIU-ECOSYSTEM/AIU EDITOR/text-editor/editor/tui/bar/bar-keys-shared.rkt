#lang racket/base

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

(define bar-level-keys
  (list (list "h" "bar-less")
        (list "t" "bar-more") (list "left" "bar-less") (list "right" "bar-more")
        (list "escape" "bar-mode")))

(provide bar-keys bar-level-keys)
