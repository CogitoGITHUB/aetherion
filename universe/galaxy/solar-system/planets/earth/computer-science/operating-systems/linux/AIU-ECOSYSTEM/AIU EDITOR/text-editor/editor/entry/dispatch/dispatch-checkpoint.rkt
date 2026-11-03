#lang racket/base
;; One job: the checkpoint verbs of the argv dispatch - checkpoint, rollback
;; and stop. The table that names them stays in dispatch.rkt, which
;; requires this file.

(require racket/string
         "../../narration/print-console.rkt"
         "../../checkpoint/checkpoint.rkt"
         "../../checkpoint/rollback.rkt"
         "../../machine/stop-switch.rkt")

;; checkpoint-verb makes a checkpoint of a tree: the state the tree is put
;; back to when an agent does something the human did not want. The first
;; word is the tree, the rest is the why.
(define (checkpoint-verb args)
  (define root (if (null? args) "." (car args)))
  (define why (string-join (if (null? args) '() (cdr args)) " "))
  (define made (checkpoint (path->complete-path root) why))
  (if made
      (print-line (format "checkpoint: ~a" made))
      (print-line "a checkpoint needs a why: say what the agent was about to do")))

;; rollback-verb puts a tree back to a checkpoint.
(define (rollback-verb args)
  (define root (if (null? args) "." (car args)))
  (define commit (if (null? args) "" (cadr args)))
  (define answer (rollback (path->complete-path root) commit))
  (if (car answer)
      (print-line (format "the tree is back at ~a" (car answer)))
      (print-line (format "the rollback was refused: ~a" (cdr answer)))))

;; stop-verb throws or clears the stop switch: while it is thrown, every
;; agent session for this project stops.
(define (stop-verb args)
  (define what (if (null? args) "stop" (car args)))
  (cond
    [(string=? what "stop")
     (throw-switch)
     (print-line "the stop switch is thrown: every agent session for this project stops")]
    [(string=? what "start")
     (clear-switch)
     (print-line "the stop switch is cleared: the agent sessions may run again")]
    [else
     (print-line (format "the stop switch is ~a" (if (stopped?) "thrown" "clear")))]))

;; The checkpoint verbs, for the table in dispatch.rkt.
(provide checkpoint-verb
         rollback-verb
         stop-verb)
