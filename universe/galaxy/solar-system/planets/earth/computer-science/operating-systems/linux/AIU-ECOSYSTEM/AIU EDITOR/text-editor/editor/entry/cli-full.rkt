#lang racket/base

(require "dispatch/dispatch.rkt"
         "documents.rkt"
         "../devloop/start.rkt"
         "../narration/print-console.rkt")

(define (main)
  (define args (vector->list (current-command-line-arguments)))
  (cond
    [(null? args) (usage "no command was given")]
    [else
     (define verb (car args))
     (if (command-known? verb)
         (begin
           (unless (string=? verb "edit") (print-start))
           (run-verb verb (cdr args)))
         (usage (format "there is no command named ~a" verb)))]))

(define (usage why)
  (print-line (format "the editor: ~a" why))
  (print-line "usage: racket cli.rkt edit FILE | routes | tasks | task | keys | git | git-diff | git-history | bake | send | agent | permit")
  (exit exit-refusal))

(provide main)
