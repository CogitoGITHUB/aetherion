#lang racket/base

(define split-keys
  (list (list "h" "pane-focus-left")
        (list "s" "pane-focus-right")
        (list "t" "pane-focus-down")
        (list "n" "pane-focus-up")
        (list "v" "pane-split-right")
        (list "w" "pane-split-down")
        (list "c" "pane-close") (list "d" "pane-close") (list "H" "pane-swap-left") (list "T" "pane-swap-down") (list "N" "pane-swap-up") (list "S" "pane-swap-right")
        (list "f" "float-toggle")
        (list "1" "float-todo")
        (list "2" "float-journal")
        (list "3" "float-notes")
        (list "e" "float-settings")
        (list "z" "float-size")
        (list "g" "float-grow")
        (list "k" "float-shrink")
        (list "escape" "visual-mode")))

(provide split-keys)