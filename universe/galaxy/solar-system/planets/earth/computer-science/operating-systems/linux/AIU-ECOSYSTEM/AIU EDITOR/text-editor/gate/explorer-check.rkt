#lang racket/base

(require racket/list
         racket/set
         racket/string
         "../editor/commands/commands.rkt"
         "../editor/tui/blocks/blocks-edit.rkt"
         "../editor/tui/blocks/blocks-move.rkt"
         "../editor/tui/blocks/blocks-text.rkt"
         "../editor/tui/tabs/tabs-commands.rkt"
         "../editor/tui/float/explorer.rkt"
         "../editor/routes/keymaps.rkt")

(define panel-commands
  (for/set ([line (in-list (explorer-lines))]
             #:when (regexp-match #rx"-> +([^ ]+)$" line))
    (cadr (regexp-match #rx"-> +([^ ]+)$" line))))

(define typed-commands
  (for/set ([line (in-list (explorer-lines))]
             #:when (and (not (regexp-match #rx"-> " line))
                         (regexp-match #rx"^ +[^ ]+$" line)))
    (string-trim (cadr (regexp-match #rx"^ +([^ ]+)$" line)))))

(define table-commands
  (sort (hash-keys commands) string<?))

(define missing-commands
  (for/list ([name (in-list table-commands)]
             #:unless (or (set-member? panel-commands name)
                          (set-member? typed-commands name)))
    name))

(define unknown-key-commands
  (append*
   (for/list ([layer (in-list editor-layers)])
     (for/list ([binding (in-list (keys-of layer))]
                #:unless (member (cadr binding) table-commands))
       (list layer (car binding) (cadr binding))))))

(define (run-check)
  (define missing missing-commands)
  (define unknown unknown-key-commands)
  (if (and (null? missing) (null? unknown))
      (begin
        (printf "OK explorer-check — ~a commands in the table, every one of them is in the panel, and every key names a command that exists\n"
                (length table-commands))
        (exit 0))
      (begin
        (for ([name (in-list missing)])
          (printf "EXPLORER — the command ~a is in the table and not in the panel\n" name))
        (for ([entry (in-list unknown)])
          (printf "EXPLORER — the key ~a in the layer ~a names the command ~a, and the command table does not hold it\n"
                  (second entry) (first entry) (third entry)))
        (exit 1))))

(module+ main
  (run-check))
