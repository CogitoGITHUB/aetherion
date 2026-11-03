#lang racket/base
;; multi-keys.rkt: One job: the keys of the select and cursor layers, as data.

;; select-keys are the keys of the select layer: the trigger's sequences,
;; and the selected text is what they act on.
(define select-keys
  (list (list "space space" "mode") (list "space v" "sel-cancel")
        (list "n" "sel-left") (list "s" "sel-right") (list "left" "sel-left") (list "right" "sel-right")
        (list "up" "sel-up") (list "down" "sel-down") (list "w" "sel-word") (list "b" "sel-word-back")
        (list "h" "sel-block-back") (list "t" "sel-block-forward")
        (list "a" "kind-any") (list "p" "kind-paragraph") (list "e" "kind-section") (list "c" "kind-code")
        (list "k" "kind-comment") (list "l" "kind-title") (list "x" "kind-todo") (list "o" "kind-todo-open")
        (list "d" "kind-todo-done")
        (list "y" "copy") (list "space y" "copy") (list "space d" "cut") (list "space p" "paste") (list "j" "sel-next-match") (list "v" "sel-all-matches") (list "r" "sel-drop")
        (list "escape" "sel-cancel")))

;; cursor-keys are the keys of the cursor layer: t and h add a cursor on the next or previous block of the picked
;; kind, the arrows add one on the line below or above, j adds the next match, v every match, r drops the last
;; cursor, z clears them, f opens the write layer for all of them, s starts the selections, escape goes back.
(define cursor-keys
  (list (list "t" "cur-next-block") (list "h" "cur-prev-block")
        (list "down" "cur-below") (list "up" "cur-above") (list "left" "move-left") (list "right" "move-right")
        (list "j" "cur-next-match") (list "v" "cur-all-matches") (list "r" "cur-drop") (list "z" "cur-clear")
        (list "f" "write-mode") (list "s" "select-mode")
        (list "a" "kind-any") (list "p" "kind-paragraph") (list "e" "kind-section") (list "c" "kind-code")
        (list "k" "kind-comment") (list "l" "kind-title") (list "x" "kind-todo") (list "o" "kind-todo-open")
        (list "d" "kind-todo-done")
        (list "escape" "cur-leave")))

(provide select-keys cursor-keys)
