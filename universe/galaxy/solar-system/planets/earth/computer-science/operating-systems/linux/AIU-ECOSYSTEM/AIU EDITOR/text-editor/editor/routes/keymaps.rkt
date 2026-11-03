#lang racket/base

(require racket/list
         racket/string
         "../devloop/start.rkt"
         "../tui/undo/undo-keys.rkt"
         "../tui/multi/multi-keys.rkt"
         "../tui/blocks/blocks-keys.rkt"
         "../tui/bar/bar-keys.rkt"
         "../tui/tabs/tabs-keys.rkt"
         "../tui/tabs/finder-keys.rkt"
         "../tui/float/pins-keys.rkt"
         "../tui/split/split-keys.rkt")

(define reserved-prefix "f1")

(define editor-layers '("visual" "write" "select" "move" "undo" "cursor" "bar" "bar-level" "tab" "tab-level" "find" "pin" "pane"))

(define trigger-of
  (list (cons "visual" "space")
        (cons "write" "tab")
        (cons "select" "space")
          (cons "move" "space")
          (cons "bar" "space")
          (cons "bar-level" "space")
          (cons "tab" "space")
          (cons "tab-level" "space")
          (cons "find" "space") (cons "undo" "space") (cons "cursor" "space") (cons "pin" "space") (cons "pane" "space")))

(define normal-keys
  '(("w" "block-edit")
    ("h" "block-up")
    ("t" "block-down")
    ("n" "move-left")
    ("s" "move-right")
    ("m" "block-move-mode")
    ("a" "kind-any")
    ("p" "kind-paragraph")
    ("e" "kind-section")
    ("c" "kind-code")
    ("k" "kind-comment")
    ("l" "kind-title")
    ("x" "kind-todo")
    ("o" "kind-todo-open")
    ("d" "kind-todo-done")
    ("i" "block-text")
    ("g" "view-up")
    ("r" "view-down")
    
    ("space v" "select-mode")
    ("space c" "cursor-mode")
    ("space y" "copy")
    ("space p" "paste")
    ("space d" "cut")
    ("space s" "save")
    ("space q" "quit") ("q" "quit")
    ("space u" "undo-mode")
    ("space ?" "explorer")
    ("space g" "send")
    ("space b" "bar-mode")
    ("space t" "tab-mode")
    ("space z" "focus-toggle")
    ("space /" "find-mode")
    ("space k" "check")
    ("space n" "next-block")
    ("space e" "block-end")
    ("space o" "pin-mode") ("space w" "pane-mode")
      ("up" "block-up") ("down" "block-down") ("left" "move-left") ("right" "move-right")
    ("escape" "visual-mode")
    ("backspace" "delete")))

(define insert-keys
  '(("tab tab" "mode")
    ("tab s" "save")
    ("tab p" "paste")
    ("tab b" "blocks")
    ("escape" "leave-write")
    ("up" "move-up")
    ("down" "move-down")
    ("left" "move-left")
    ("right" "move-right")
    ("backspace" "delete")))









(define keymaps
  (or (and (string=? (mode) "baked") (baked-tables))
      (list (list "visual" normal-keys)
            (list "write" insert-keys)
            (list "select" select-keys)
              (list "move" move-keys)
            (list "bar" bar-keys)
            (list "bar-level" bar-level-keys)
            (list "tab" tab-keys)
            (list "tab-level" tab-level-keys)
            (list "find" find-keys) (list "undo" undo-keys) (list "cursor" cursor-keys) (list "pin" pin-keys) (list "pane" split-keys))))

(define (keys-of layer)
  (define found (assoc layer keymaps))
  (if found (cadr found) '()))

(define (binding-of layer key)
  (define found (assoc key (keys-of layer)))
  (if found (cadr found) #f))

(define (sequence-of key)
  (filter (lambda (name) (not (string=? name ""))) (string-split key " ")))

(define (prefix-of? layer names)
  (for*/or ([binding (in-list (keys-of layer))])
    (define wanted (sequence-of (car binding)))
    (and (> (length wanted) (length names))
         (equal? (take wanted (length names)) names))))

(provide split-keys move-keys
         bar-keys
         bar-level-keys
         tab-keys
         tab-level-keys
         find-keys
         reserved-prefix
         editor-layers
         trigger-of
         normal-keys
         insert-keys
         select-keys
         keymaps
         keys-of
         binding-of
         sequence-of
         prefix-of?)

(provide undo-keys)

(provide cursor-keys)
