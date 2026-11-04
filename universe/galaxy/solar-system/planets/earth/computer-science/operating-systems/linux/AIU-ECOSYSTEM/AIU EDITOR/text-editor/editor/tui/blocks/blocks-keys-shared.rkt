#lang racket/base

(define move-keys
  (list (list "h" "block-move-up")
        (list "t" "block-move-down") (list "up" "block-move-up") (list "down" "block-move-down")
        (list "escape" "visual-mode")))

(provide move-keys)
