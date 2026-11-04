#lang racket/base

(require racket/list
         racket/path
         racket/port
         racket/string
         "../../narration/print-console-shared.rkt"
         "../../narration/narration.rkt"
         "../../machine/directories-shared.rkt"
         "../../commands/commands-shared.rkt"
         "../../commands/tasks.rkt"
         "../../devloop/bake.rkt"
         "../../devloop/last-good.rkt"
         "../../routes/keyboard.rkt"
         "../../routes/keymaps-shared.rkt"
         "../../routes/routes.rkt"
         "../../join/hot-path-shared.rkt"
         "../../join/protocol-shared.rkt"
         "../../bridge/document-shared.rkt"
         "../../bridge/host-shared.rkt")

(provide tasks-verb task-verb)

(define (tasks-verb args)
  (if (null? args)
      (for-each print-line (task-lines))
      (print-line "the editor: tasks takes no arguments")))

(define (task-verb args)
  (cond
    [(null? args)
     (print-line "the editor: task needs a file")]
    [else
     (define dry (member "--dry-run" args))
     (define words (if dry (remove "--dry-run" args) args))
     (define file (path->complete-path (car words)))
     (define session (make-session file (journal-path-for file)))
     (define groups (split-runs (cdr words)))
     (define answers
       (parameterize ([dry-run? (and dry #t)])
         (run-tasks session groups)))
     (for-each print-line answers)]))

(define (split-runs words)
  (let loop ([rest words] [current '()] [runs '()])
    (cond
      [(null? rest)
       (if (null? current) (reverse runs) (reverse (cons (reverse current) runs)))]
      [(string=? (car rest) "--")
       (loop (cdr rest) '() (if (null? current) runs (cons (reverse current) runs)))]
      [else (loop (cdr rest) (cons (car rest) current) runs)])))
