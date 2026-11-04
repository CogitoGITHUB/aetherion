#lang racket/base

(define undo-keys
  (list (list "h" "undo-back") (list "t" "undo-forward")
        (list "n" "undo-up") (list "s" "undo-down")
        (list "a" "undo-branch-back") (list "w" "undo-branch-forward") (list "e" "undo-tip")
        (list "m" "undo-mark") (list "u" "undo-unmark") (list "d" "undo-diff")
        (list "l" "undo-live") (list "k" "undo-keep") (list "return" "undo-keep") (list "y" "copy")
        (list "up" "move-up") (list "down" "move-down") (list "left" "move-left") (list "right" "move-right")
        (list "escape" "undo-cancel")))

(provide undo-keys)
