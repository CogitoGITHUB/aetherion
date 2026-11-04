#lang racket/base

(define split-keys
  (list (list "n" "pane-focus-left")
        (list "s" "pane-focus-right")
        (list "h" "pane-focus-up")
        (list "t" "pane-focus-down")
        (list "left" "pane-swap-left")
        (list "right" "pane-swap-right")
        (list "up" "pane-swap-up")
        (list "down" "pane-swap-down")
        (list "r" "pane-split-right")
        (list "d" "pane-split-down")
        (list "c" "pane-close")
        (list "g" "pane-grow-width")
        (list "l" "pane-shrink-width")
        (list "k" "pane-grow-height")
        (list "j" "pane-shrink-height")
        (list "f" "pane-flip")
        (list "u" "pane-turn")
        (list "e" "pane-equalise")
        (list "escape" "visual-mode")))

(provide split-keys)
