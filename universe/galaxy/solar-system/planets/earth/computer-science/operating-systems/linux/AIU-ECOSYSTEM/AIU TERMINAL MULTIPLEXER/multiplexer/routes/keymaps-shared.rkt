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

(define editor-layers '("visual" "write" "select" "move" "undo" "cursor" "bar" "bar-level" "tab" "tab-level" "find" "pin" "pane" "project" "workspace" "buffer"))

(define trigger-of
  (list (cons "visual" "space")
        (cons "write" "a")
        (cons "select" "space")
          (cons "move" "space")
          (cons "bar" "space")
          (cons "bar-level" "space")
          (cons "tab" "space")
          (cons "tab-level" "space")
          (cons "find" "space") (cons "undo" "space") (cons "cursor" "space") (cons "pin" "space") (cons "pane" "space") (cons "project" "space") (cons "workspace" "space") (cons "buffer" "space")))

(define project-keys (list (list "h" "project-prev") (list "t" "project-next") (list "left" "project-prev") (list "right" "project-next") (list "a" "project-move-left") (list "e" "project-move-right") (list "c" "project-close") (list "o" "project-open") (list "n" "project-new") (list "r" "project-remove") (list "p" "tab-place-next") (list "u" "tab-top") (list "b" "tab-bottom") (list "j" "tab-join") (list "x" "tab-hide") (list "v" "tab-level-mode") (list "escape" "visual-mode")))

(define workspace-keys (list (list "h" "workspace-prev") (list "t" "workspace-next") (list "left" "workspace-prev") (list "right" "workspace-next") (list "a" "workspace-move-left") (list "e" "workspace-move-right") (list "c" "workspace-close") (list "o" "workspace-open") (list "n" "workspace-new") (list "r" "workspace-remove") (list "p" "tab-place-next") (list "u" "tab-top") (list "b" "tab-bottom") (list "j" "tab-join") (list "x" "tab-hide") (list "v" "tab-level-mode") (list "escape" "visual-mode")))

(define buffer-keys
  (quote (("h" "buffer-previous") ("t" "buffer-next") ("n" "buffer-new") ("c" "buffer-close") ("escape" "visual-mode"))))

(define normal-keys
  (quote (("i" "write-mode") ("space space" "menu-or-visual") ("space b" "buffer-layer") ("space w" "pane-layer") ("t" "scroll-up") ("h" "scroll-down") ("T" "page-up") ("H" "page-down") ("q" "quit"))))

(define insert-keys
  (quote (("a a" "visual-mode"))))

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
            (list "find" find-keys) (list "undo" undo-keys) (list "cursor" cursor-keys) (list "pin" pin-keys) (list "pane" split-keys) (list "project" project-keys) (list "workspace" workspace-keys) (list "buffer" buffer-keys))))

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
