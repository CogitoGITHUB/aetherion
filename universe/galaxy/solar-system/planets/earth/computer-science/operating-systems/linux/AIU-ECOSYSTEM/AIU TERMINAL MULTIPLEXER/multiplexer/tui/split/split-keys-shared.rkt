#lang racket/base

(define split-keys
  (list (list "d" "pane-focus-left")
        (list "n" "pane-focus-right")
        (list "h" "pane-focus-down")
        (list "t" "pane-focus-up")
        (list "r" "pane-split-right")
        (list "s" "pane-split-down")
        (list "c" "pane-close")
        (list "f" "float-toggle")
        (list "1" "float-todo")
        (list "2" "float-journal")
        (list "3" "float-notes")
        (list "z" "float-size")
        (list "g" "float-grow")
        (list "k" "float-shrink")
        (list "escape" "visual-mode")))

(provide split-keys)