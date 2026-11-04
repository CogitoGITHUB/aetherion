#lang racket/base

(define tab-keys
  (list (list "h" "tab-prev")
        (list "t" "tab-next") (list "left" "tab-prev") (list "right" "tab-next")
        (list "o" "tab-open")
        (list "a" "tab-move-left")
        (list "e" "tab-move-right")
        (list "c" "tab-close")
        (list "p" "tab-place-next")
        (list "u" "tab-top")
        (list "b" "tab-bottom")
        (list "j" "tab-join")
        (list "x" "tab-hide")
        (list "v" "tab-level-mode")
        (list "escape" "visual-mode")))

(define tab-level-keys
  (list (list "h" "tab-less")
        (list "t" "tab-more") (list "left" "tab-less") (list "right" "tab-more")
        (list "escape" "tab-mode")))

(provide tab-keys tab-level-keys)
