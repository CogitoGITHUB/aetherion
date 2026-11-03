#lang racket/base
;; One job: the mapping tables, as data — the editor's own keys and the
;; layers they belong to. Registered in plan/package-tree.org; lands with
;; TODO item 4.
;;
;; The tables are data and not code: the routing reads them, the gate
;; checks them, and a person can read what the editor does with a key
;; without reading a function.
;;
;; THE KEYBOARD IS PLAIN. The owner asked for no modifier at all: no
;; meta, no alt, no control, and no chord. Every key the editor binds is a
;; key a person can press on its own — a letter, a digit, space, return,
;; tab, backspace, an arrow or a function key. ESCAPE is one of those plain
;; keys: pressed on its own it goes back to the visual layer, where the
;; page is read, and it never starts a chord.
;;
;; THE TRIGGER IS SPACE. A trigger starts a sequence: the trigger and the
;; key after it are the command. A trigger that is pressed twice is the
;; mode change, so the mode changes with a double space and never with a
;; modifier. The write layer is the one place the trigger is not the
;; space — there a space is a typed space — so the write layer's trigger
;; is the tab, the one plain key that is not text.
;;
;; A key may be a SEQUENCE of keys, and the names of the keys are joined
;; by a space: "space space" is the double space.

(require racket/list
         racket/string
         "../devloop/start.rkt"
         "../tui/undo/undo-keys.rkt"
         "../tui/multi/multi-keys.rkt"
         "../tui/blocks/blocks-keys.rkt"
         "../tui/bar/bar-keys.rkt"
         "../tui/tabs/tabs-keys.rkt"
         "../tui/tabs/finder-keys.rkt"
         "../tui/float/pins-keys.rkt")

;; reserved-prefix is the key the multiplexer keeps for itself. It applies
;; everywhere, so the editor never binds it: a binding that collides with
;; it is refused by the route-collision stage of the gate. It is the
;; MULTIPLEXER's key and not the editor's: the editor binds no modifier
;; and no escape at all, and it never takes this one.
(define reserved-prefix "f1")

;; editor-layers are the editor's own layers, in the order the routing
;; looks at them. The layer the editor is in answers first.
;;
;;   visual — the general mode: the trigger and the plain keys
;;   write  — the text mode: the keys are text
;;   select — the selected text is what the commands act on
(define editor-layers '("visual" "write" "select" "move" "undo" "cursor" "bar" "bar-level" "tab" "tab-level" "find" "pin"))

;; trigger-of answers the trigger of each layer: the key that starts a
;; sequence in that layer.
(define trigger-of
  (list (cons "visual" "space")
        (cons "write" "tab")
        (cons "select" "space")
          (cons "move" "space")
          (cons "bar" "space")
          (cons "bar-level" "space")
          (cons "tab" "space")
          (cons "tab-level" "space")
          (cons "find" "space") (cons "undo" "space") (cons "cursor" "space") (cons "pin" "space")))

;; normal-keys are the keys of the visual layer: the key and the command
;; it runs. The command is a name from the command table, never a
;; function, so the table can be read and checked on its own. A key that
;; moves the point names the way it moves, so the table says which arrow
;; does what.
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
    ("space o" "pin-mode")
      ("up" "block-up") ("down" "block-down") ("left" "move-left") ("right" "move-right")
    ("escape" "visual-mode")
    ("backspace" "delete")))

;; insert-keys are the keys of the write layer. Here the keys are text,
;; so the layer holds the trigger's sequences only: the tab starts them.
;; The keys that carry no text are bound too, so a person writing does not
;; have to leave the layer to move or to take a character back: the arrows
;; move the point and backspace deletes before it, and neither is typed
;; into the file as its own name.
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









;; The tables are put in with list, not with cons and not with a quote:
;; a quoted list would hold the NAMES of the tables, and a cons would be
;; written flat by the bake — the shape of the tables has to survive the
;; round trip through the baked module.
;;
;; In the work mode the tables are these ones, read from the source at
;; every start. In the baked mode they are the ones the bake made into
;; first-class defaults, and the source is not read at all.
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
            (list "find" find-keys) (list "undo" undo-keys) (list "cursor" cursor-keys) (list "pin" pin-keys))))

;; keys-of answers the keys of one layer, or nothing when the table holds
;; no layer by that name. The keys of a layer are pairs: a key and the
;; command it runs.
(define (keys-of layer)
  (define found (assoc layer keymaps))
  (if found (cadr found) '()))

;; binding-of answers the command one key runs in one layer, or nothing
;; when the layer binds no such key. A binding is a pair of a key and a
;; command, so the command is the second of the two.
(define (binding-of layer key)
  (define found (assoc key (keys-of layer)))
  (if found (cadr found) #f))

;; sequence-of answers the names of the keys of a key, whether it is one
;; key or a sequence of them: "space space" is two keys.
(define (sequence-of key)
  (filter (lambda (name) (not (string=? name ""))) (string-split key " ")))

;; prefix-of? answers whether a sequence of key names is the start of some
;; key of the layer, and is not the whole of it. A prefix waits for the next
;; key, and the next key is an action: no timer decides it.
;;
;; The comparison is between KEY NAMES, not between texts: "b" is the key
;; named b and "backspace" is a different key, so "b" is not the start of
;; "backspace". Reading the names as text is what made typing a "b" wait for
;; a key that never came.
(define (prefix-of? layer names)
  (for*/or ([binding (in-list (keys-of layer))])
    (define wanted (sequence-of (car binding)))
    (and (> (length wanted) (length names))
         (equal? (take wanted (length names)) names))))

;; The tables, for the routing above them and the gate beside them.
(provide move-keys
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
