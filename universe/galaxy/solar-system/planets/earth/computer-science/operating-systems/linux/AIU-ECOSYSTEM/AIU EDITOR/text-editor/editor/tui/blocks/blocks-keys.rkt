#lang racket/base
;; blocks-keys.rkt: One job: the keys of the move layer, as data.

;; move-keys are the keys of the move layer: h and t swap the lit block with
;; the one before or after it, and escape goes back to the visual layer.
(define move-keys
  (list (list "h" "block-move-up")
        (list "t" "block-move-down") (list "up" "block-move-up") (list "down" "block-move-down")
        (list "escape" "visual-mode")))

(provide move-keys)
