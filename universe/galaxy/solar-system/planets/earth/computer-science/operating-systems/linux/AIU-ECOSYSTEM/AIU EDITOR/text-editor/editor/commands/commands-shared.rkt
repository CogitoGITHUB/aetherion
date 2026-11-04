#lang racket/base

(require racket/list
         racket/path
         racket/string
         "../buffer/selection-shared.rkt"
         "../join/protocol-shared.rkt"
         "../join/hot-path-shared.rkt"
         "../journal/replay-shared.rkt"
         "../bridge/document-shared.rkt"
         "../bridge/host-shared.rkt"
         "../bridge/where-shared.rkt"
         "session-shared.rkt"
         "multi-boxes-shared.rkt" "sets/commands-edit-shared.rkt" "sets/commands-layer-shared.rkt" "sets/commands-page-shared.rkt")

(define (command-help session words)
  (cons #t (string-join command-names ", ")))

(define (command-quit session words)
  (cons #f "bye"))

(define (command-send session words)
  (cons #t "the send action is not built yet: the agent boundary lands with the AI link"))

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

(define commands
  (let ([table (make-hash)])
    (for ([entry (in-list (hash->list command-table))])
      (hash-set! table (car entry) (cdr entry)))
    table))

(define command-names
  (sort (hash-keys commands) name<?))

(define (words-of line)
  (filter (lambda (word) (not (string=? word ""))) (string-split line " ")))

(define (run-command-words session name words)
  (define handler (hash-ref commands name #f))
  (if handler
      (handler session words)
      (cons #t (format "there is no command named ~a; ask for one of: ~a"
                       name (string-join command-names ", ")))))

(define (run-command session line)
  (define words (words-of line))
  (if (null? words)
      (cons #t "")
      (run-command-words session (car words) (cdr words))))

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

(provide move-to)

(define kind-filter (box "any"))

(define (mode-label layer)
  (cond [(string=? layer "select") "visual selection"]
        [(string=? layer "visual") (if (string=? (unbox kind-filter) "any") "visual general" "visual navigation")]
        [else layer]))


(provide kind-filter mode-label)
(define unsaved (box #f))

(provide unsaved)

(provide ask session-text set-layer! the-point session-file)


(provide extra-cursors main-anchor multi-raw-view multi-file multi-lit-hook multi-text-hook
         multi-edit-hook multi-live? multi-raw? multi-clear! multi-drop-selections!)
