#lang racket/base

(require racket/list
         racket/string
         "../devloop/start-shared.rkt"
         "../tui/undo/undo-keys-shared.rkt"
         "../tui/multi/multi-keys-shared.rkt"
         "../tui/blocks/blocks-keys-shared.rkt"
         "../tui/bar/bar-keys-shared.rkt"
         "../tui/tabs/tabs-keys-shared.rkt"
         "../tui/tabs/finder-keys-shared.rkt"
         "../tui/float/pins-keys-shared.rkt"
         "../tui/split/split-keys-shared.rkt")

(define reserved-prefix "f1")

(define editor-layers '("visual" "write" "select" "move" "undo" "cursor" "bar" "bar-level" "tab" "tab-level" "find" "pin" "pane" "project" "workspace"))

(define trigger-of
  (list (cons "visual" "space")
        (cons "write" "tab")
        (cons "select" "space")
          (cons "move" "space")
          (cons "bar" "space")
          (cons "bar-level" "space")
          (cons "tab" "space")
          (cons "tab-level" "space")
          (cons "find" "space") (cons "undo" "space") (cons "cursor" "space") (cons "pin" "space") (cons "pane" "space") (cons "project" "space") (cons "workspace" "space")))

(define project-keys (list (list "h" "project-prev") (list "t" "project-next") (list "left" "project-prev") (list "right" "project-next") (list "a" "project-move-left") (list "e" "project-move-right") (list "c" "project-close") (list "o" "project-open") (list "n" "project-new") (list "r" "project-remove") (list "p" "tab-place-next") (list "u" "tab-top") (list "b" "tab-bottom") (list "j" "tab-join") (list "x" "tab-hide") (list "v" "tab-level-mode") (list "escape" "visual-mode")))

(define workspace-keys (list (list "h" "workspace-prev") (list "t" "workspace-next") (list "left" "workspace-prev") (list "right" "workspace-next") (list "a" "workspace-move-left") (list "e" "workspace-move-right") (list "c" "workspace-close") (list "o" "workspace-open") (list "n" "workspace-new") (list "r" "workspace-remove") (list "p" "tab-place-next") (list "u" "tab-top") (list "b" "tab-bottom") (list "j" "tab-join") (list "x" "tab-hide") (list "v" "tab-level-mode") (list "escape" "visual-mode")))

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
    ("space o" "pin-mode") ("space w" "pane-mode") ("space j" "project-mode") ("space l" "workspace-mode")
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
            (list "find" find-keys) (list "undo" undo-keys) (list "cursor" cursor-keys) (list "pin" pin-keys) (list "pane" split-keys) (list "project" project-keys) (list "workspace" workspace-keys))))

(define (keys-of layer)
  (define plain (keys-of-plain layer))
  (if (or (null? plain) (assoc "space space" plain))
      plain
      (append plain (list (list "space space" "menu-or-visual")))))

(define (keys-of-plain layer)
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
