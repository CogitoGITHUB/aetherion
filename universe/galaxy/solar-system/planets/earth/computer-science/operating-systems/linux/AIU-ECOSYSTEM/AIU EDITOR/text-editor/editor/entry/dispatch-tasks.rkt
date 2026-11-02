#lang racket/base
;; One job: the task and tasks verbs of the argv dispatch.

(require racket/list
         racket/path
         racket/port
         racket/string
         "../narration/print-console.rkt"
         "../narration/narration.rkt"
         "../machine/directories.rkt"
         "../commands/commands.rkt"
         "../commands/tasks.rkt"
         "../devloop/bake.rkt"
         "../devloop/last-good.rkt"
         "../tui/dashboard.rkt"
         "../routes/keyboard.rkt"
         "../routes/keymaps.rkt"
         "../routes/routes.rkt"
         "../join/hot-path.rkt"
         "../join/protocol.rkt"
         "../notation/document.rkt"
         "../notation/host.rkt")

(provide tasks-verb task-verb)

;; tasks-verb answers the task table: one line per task, the name and
;; the doc line of the task, so the list and the help read the same way.
(define (tasks-verb args)
  (if (null? args)
      (for-each print-line (task-lines))
      (print-line "the editor: tasks takes no arguments")))

;; task-verb runs tasks against a file. The first word is the file, and
;; after it come the runs: a task name and the words that are its
;; arguments. A "--" between two runs starts the next one, so several
;; runs in one invocation are a sequence and they run in the order they
;; were given. A "--dry-run" word opens the dry-run scope, where a task
;; that acts prints what it would do and changes nothing.
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

;; split-runs splits the words of an invocation into the runs of a
;; sequence. A "--" starts the next run; the words before it are the
;; name of the first task and its arguments. The runs come back in the
;; order they were given.
(define (split-runs words)
  (let loop ([rest words] [current '()] [runs '()])
    (cond
      [(null? rest)
       (if (null? current) (reverse runs) (reverse (cons (reverse current) runs)))]
      [(string=? (car rest) "--")
       (loop (cdr rest) '() (if (null? current) runs (cons (reverse current) runs)))]
      [else (loop (cdr rest) (cons (car rest) current) runs)])))
