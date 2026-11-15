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
          (cons "tab-level" "space") (cons "tab-move" "space") (cons "buffer-move" "space") (cons "project" "space") (cons "workspace" "space") (cons "project-move" "space") (cons "workspace-move" "space")
          (cons "find" "space") (cons "undo" "space") (cons "cursor" "space") (cons "pin" "space") (cons "pane" "space") (cons "project" "space") (cons "workspace" "space") (cons "buffer" "space")))

(define project-keys (list (list "h" "project-prev") (list "t" "project-next") (list "left" "project-prev") (list "right" "project-next") (list "m" "project-move-mode") (list "H" "project-move-left") (list "T" "project-move-right") (list "c" "project-close") (list "o" "project-open") (list "n" "project-new") (list "r" "project-rename") (list "d" "project-remove") (list "p" "tab-place-next") (list "u" "tab-top") (list "b" "tab-bottom") (list "j" "tab-join") (list "x" "tab-hide") (list "v" "tab-level-mode") (list "escape" "visual-mode")))

(define workspace-keys (list (list "h" "workspace-prev") (list "t" "workspace-next") (list "left" "workspace-prev") (list "right" "workspace-next") (list "m" "workspace-move-mode") (list "H" "workspace-move-left") (list "T" "workspace-move-right") (list "c" "workspace-close") (list "o" "workspace-open") (list "n" "workspace-new") (list "r" "workspace-rename") (list "d" "workspace-remove") (list "p" "tab-place-next") (list "u" "tab-top") (list "b" "tab-bottom") (list "j" "tab-join") (list "x" "tab-hide") (list "v" "tab-level-mode") (list "escape" "visual-mode")))

(define buffer-keys
  (quote (("h" "buffer-previous") ("t" "buffer-next") ("n" "buffer-new") ("c" "buffer-close") ("d" "buffer-close") ("r" "buffer-rename") ("m" "buffer-move-mode") ("H" "buffer-move-left") ("T" "buffer-move-right") ("escape" "visual-mode"))))

(define normal-keys
  (quote (("i" "write-mode") ("space space" "menu-or-visual") ("space b" "buffer-layer") ("space w" "pane-layer") ("space e" "editor-layer") ("space s" "shell-layer") ("space p" "project-layer") ("space k" "workspace-layer") ("t" "scroll-up") ("h" "scroll-down") ("T" "page-up") ("H" "page-down") ("q" "quit"))))

(define insert-keys
  (quote (("space space" "visual-mode"))))

(define tab-move-keys (list (list "h" "tab-move-left") (list "s" "tab-move-right") (list "left" "tab-move-left") (list "right" "tab-move-right") (list "n" "tab-top") (list "up" "tab-top") (list "t" "tab-bottom") (list "down" "tab-bottom") (list "space space" "tab-move-back") (list "escape" "tab-move-back")))

(define project-move-keys (list (list "h" "project-move-left") (list "s" "project-move-right") (list "left" "project-move-left") (list "right" "project-move-right") (list "space space" "project-move-back") (list "escape" "project-move-back")))

(define workspace-move-keys (list (list "h" "workspace-move-left") (list "s" "workspace-move-right") (list "left" "workspace-move-left") (list "right" "workspace-move-right") (list "space space" "workspace-move-back") (list "escape" "workspace-move-back")))

(define buffer-move-keys (list (list "h" "buffer-move-left") (list "s" "buffer-move-right") (list "left" "buffer-move-left") (list "right" "buffer-move-right") (list "space space" "buffer-move-back") (list "escape" "buffer-move-back")))

(define mux-project-keys
  (list (list "h" "project-prev") (list "s" "project-next")
        (list "t" "project-next") (list "H" "project-move-left")
        (list "T" "project-move-right") (list "m" "project-move-mode")
        (list "n" "project-new") (list "r" "project-rename")
        (list "d" "project-remove") (list "c" "project-close")
        (list "o" "project-open") (list "escape" "visual-mode")))

(define mux-workspace-keys
  (list (list "h" "workspace-prev") (list "s" "workspace-next")
        (list "t" "workspace-next") (list "H" "workspace-move-left")
        (list "T" "workspace-move-right")
        (list "m" "workspace-move-mode")
        (list "n" "workspace-new") (list "r" "workspace-rename")
        (list "d" "workspace-remove") (list "c" "workspace-close")
        (list "o" "workspace-open") (list "escape" "visual-mode")))

(define keymaps
  (or (and (string=? (mode) "baked") (baked-tables))
      (list (list "project" mux-project-keys) (list "workspace" mux-workspace-keys) (list "visual" normal-keys)
            (list "write" insert-keys)
            (list "select" select-keys)
              (list "move" move-keys)
            (list "bar" bar-keys)
            (list "bar-level" bar-level-keys)
            (list "tab" tab-keys)
            (list "tab-level" tab-level-keys) (list "buffer-move" buffer-move-keys) (list "buffer" buffer-keys) (list "tab-move" tab-move-keys) (list "project-move" project-move-keys) (list "workspace-move" workspace-move-keys)
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
