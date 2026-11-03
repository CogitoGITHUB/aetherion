#lang racket/base

(require racket/string
         "../../narration/print-console.rkt"
         "../../checkpoint/checkpoint.rkt"
         "../../checkpoint/rollback.rkt"
         "../../machine/stop-switch.rkt")

(define (checkpoint-verb args)
  (define root (if (null? args) "." (car args)))
  (define why (string-join (if (null? args) '() (cdr args)) " "))
  (define made (checkpoint (path->complete-path root) why))
  (if made
      (print-line (format "checkpoint: ~a" made))
      (print-line "a checkpoint needs a why: say what the agent was about to do")))

(define (rollback-verb args)
  (define root (if (null? args) "." (car args)))
  (define commit (if (null? args) "" (cadr args)))
  (define answer (rollback (path->complete-path root) commit))
  (if (car answer)
      (print-line (format "the tree is back at ~a" (car answer)))
      (print-line (format "the rollback was refused: ~a" (cdr answer)))))

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

(provide checkpoint-verb
         rollback-verb
         stop-verb)
