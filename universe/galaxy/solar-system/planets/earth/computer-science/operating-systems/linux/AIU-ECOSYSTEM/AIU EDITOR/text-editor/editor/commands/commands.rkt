#lang racket/base
;; One job: the command table — one name, one function. Each function
;; takes the session and the words of the typed line, and answers whether
;; the session goes on and the line of text to print. What a typed line
;; means is the meaning side's job (rule 09); the text itself belongs to
;; the hot path, which holds the state.
;;
;; The order of this file is the order Racket reads it: every name is
;; defined before anything that uses it at load time, so the table can
;; name the handlers and the names can be sorted.

(require racket/list
         racket/path
         racket/string
         "../buffer/selection.rkt"
         "../join/protocol.rkt"
         "../join/hot-path.rkt"
         "../journal/replay.rkt"
         "../notation/document.rkt"
         "../notation/host.rkt"
         "../notation/where.rkt"
         "session.rkt"
         "multi-boxes.rkt" "sets/commands-edit.rkt" "sets/commands-layer.rkt" "sets/commands-page.rkt")

;; command-help answers the names in the table.
(define (command-help session words)
  (cons #t (string-join command-names ", ")))

;; command-quit ends the session: the answer says goodbye and the go-on
;; flag says no.
(define (command-quit session words)
  (cons #f "bye"))

;; command-send sends what is selected to the agent. The send area is ABOVE
;; this one, so this cannot call it: the send area puts its own command
;; here when it loads, and this is only the place it stands until then.
(define (command-send session words)
  (cons #t "the send action is not built yet: the agent boundary lands with the AI link"))

;; command-table is the table as data: one name and one function per
;; command.
(define command-table
  (hash "insert" command-insert-words
                           "type" command-type
                           "save" command-save
                           "journal" command-journal
                           "replay" command-replay
                           "help" command-help
                           "quit" command-quit
                           "move-up" command-move-up
                           "move-down" command-move-down
                           "move-left" command-move-left
                           "move-right" command-move-right
                           "delete" command-delete
                           "select" command-select
                           "send" command-send
                           "mode" command-mode
                           "visual-mode" command-visual-mode
                           "write-mode" command-write-mode
                           "select-mode" command-select-mode
                           "level-up" command-level-up
                           "view-up" command-view-up
                           "view-down" command-view-down
                           "blocks" command-blocks
                           "block" command-block
                           "check" command-check
                           "next-block" command-next-block
                           "block-end" command-block-end
                           "kind" command-kind))

;; commands is the table: one name, one function. The keys are compared
;; as text, so a name typed on the keyboard finds its function. The table
;; is MUTABLE: an area above this one may add its own command to it.
(define commands
  (let ([table (make-hash)])
    (for ([entry (in-list (hash->list command-table))])
      (hash-set! table (car entry) (cdr entry)))
    table))

;; command-names answers the names in the table, in a fixed order.
(define command-names
  (sort (hash-keys commands) name<?))

;; words-of splits one typed line into its words.
(define (words-of line)
  (filter (lambda (word) (not (string=? word ""))) (string-split line " ")))

;; run-command-words runs one command whose words are already split, and
;; answers whether the session goes on and the line of text to print. It
;; stands beside run-command because the live session's text is not a
;; typed line: a space the person pressed is one word that IS a space,
;; and splitting then rejoining it would turn it into nothing at all.
(define (run-command-words session name words)
  (define handler (hash-ref commands name #f))
  (if handler
      (handler session words)
      (cons #t (format "there is no command named ~a; ask for one of: ~a"
                       name (string-join command-names ", ")))))

;; run-command runs one typed line and answers whether the session goes
;; on, and the line of text to print. A line with no words says nothing
;; and changes nothing.
(define (run-command session line)
  (define words (words-of line))
  (if (null? words)
      (cons #t "")
      (run-command-words session (car words) (cdr words))))

;; The command table, for every area above this one.
(provide commands
         session
         make-session
         session-file
         session-journal
         session-point
         session-selection
         session-layer
         session-level
         the-point
         move-to
         the-selection
         select-from
         select-off
         selection-text
         the-layer
         set-layer!
         the-level
         set-level!
         the-view-top
         set-view-top!
         run-command
         run-command-words
         command-names
         answer-line
         session-text
         ask)

;; move-to is shared with the block view, which puts the point back inside a block.
(provide move-to)

;; kind-filter holds the kind of block that block-up and block-down move between: any, a block name, todo, todo open or todo done. The bar shows it.
(define kind-filter (box "any"))

;; mode-label answers the sub-mode shown in the mode line: visual selection in
;; the select layer, visual navigation when a pick other than any is active,
;; visual general otherwise, and the layer name for every other layer.
(define (mode-label layer)
  (cond [(string=? layer "select") "visual selection"]
        [(string=? layer "visual") (if (string=? (unbox kind-filter) "any") "visual general" "visual navigation")]
        [else layer]))


(provide kind-filter mode-label)
;; unsaved is true while the file has edits that are not saved; the bar and the one line show it.
(define unsaved (box #f))

(provide unsaved)

;; The editor pieces that the undo layer needs: the hot path request, the text, the layer, the point and the file.
(provide ask session-text set-layer! the-point session-file)


;; The multi-cursor state boxes live in multi-boxes.rkt; they are passed on from here.
(provide extra-cursors main-anchor multi-raw-view multi-file multi-lit-hook multi-text-hook
         multi-edit-hook multi-live? multi-raw? multi-clear! multi-drop-selections!)
