#lang racket/base

(require racket/list
         racket/path
         racket/port
         racket/string
         "../../narration/print-console.rkt"
         "../../narration/narration.rkt"
         "../../machine/directories.rkt"
         "../../commands/commands.rkt"
         "../../checkpoint/checkpoint.rkt"
         "../../send/adapter.rkt"
         "../../send/bundle.rkt"
         "../../send/send.rkt"
         "../../send/opencode-adapter.rkt"
         "../../audit/audit.rkt"
         "../../audit/accept.rkt"
         "../../join/hot-path.rkt"
         "../../join/protocol.rkt")

(define (send-verb args)
  (define file (if (null? args) "" (car args)))
  (define rest (if (null? args) '() (cdr args)))
  (define target (if (null? rest) "opencode" (car rest)))
  (define why (if (null? rest) "" (string-join (cdr rest) " ")))
  (define path (path->complete-path (if (string=? file "") "untitled" file)))
  (define session (make-session path (journal-path-for path)))
  (define answer (send-command session (cons target (if (string=? why "") '() (list why)))))
  (print-line (cdr answer))
  (define client (client-from-environment))
  (define handle (read-handle))
  (define marks (observe-changes (tree-root path) (last-checkpoint) client handle))
  (unless (null? marks)
    (print-line "the audit:")
    (for-each (lambda (mark) (print-line (mark-line mark))) marks)))

(define (mark-line mark)
  (format "~a  who: ~a  at: ~a  checkpoint: ~a"
          (hash-ref mark 'path "?")
          (hash-ref mark 'who "?")
          (hash-ref mark 'utc "-")
          (hash-ref mark 'checkpoint "-")))

(define (last-checkpoint)
  (define all (checkpoints))
  (if (null? all) "" (car (reverse all))))

(define (audit-verb args)
  (define root (tree-root (if (null? args) (current-directory) (car args))))
  (observe-changes root (last-checkpoint) (client-from-environment) (read-handle))
  (if (null? (audit-marks))
      (print-line "the audit holds no mark: nothing changed that was seen")
      (for-each (lambda (mark) (print-line (mark-line mark))) (audit-marks))))

(define (audit-accept-verb args)
  (define path (if (null? args) "" (car args)))
  (define mark (mark-of path))
  (if (not mark)
      (print-line (format "the audit holds no mark for ~a" path))
      (begin (accept-mark mark)
             (print-line (format "the change is accepted: ~a" path)))))

(define (audit-undo-verb args)
  (define path (if (null? args) "" (car args)))
  (define mark (mark-of path))
  (if (not mark)
      (print-line (format "the audit holds no mark for ~a" path))
      (let ([answer (undo-mark (tree-root (path->complete-path path)) mark)])
        (print-line (if (car answer) (car answer) (cdr answer))))))

(define (mark-of path)
  (define wanted (path->string (simplify-path (path->complete-path path))))
  (define found
    (filter (lambda (mark)
              (string=? (hash-ref mark 'path "") wanted))
            (audit-marks)))
  (if (null? found) #f (car (reverse found))))

(define (agent-verb args)
  (define client (client-from-environment))
  (define handle (read-handle))
  (define the-pins (pins client))
  (print-line (format "agent: opencode  session: ~a" (or handle "none is open")))
  (print-line (format "pins: boundary ~a  agent ~a"
                       (hash-ref the-pins 'boundary)
                       (hash-ref the-pins 'agent)))
  (when handle
    (for-each
     (lambda (ask)
       (print-line (format "ask: ~a  action: ~a  files: ~a"
                           (hash-ref ask 'id "unknown")
                           (hash-ref ask 'action "unknown")
                           (string-join (ask-files ask) " "))))
     (client-permissions client handle))))

(define (permit-verb args)
  (define decision (if (null? args) "reject" (car args)))
  (define request-id (if (null? (cdr args)) "" (cadr args)))
  (cond
    [(not (member decision '("once" "always" "reject")))
     (print-line "the answer must be one of: once, always, reject")]
    [(string=? request-id "")
     (print-line "the answer needs the id of the ask: permit once ID")]
    [else
     (define client (client-from-environment))
     (define handle (read-handle))
     (if (not handle)
         (print-line "there is no session open: attach an agent first")
         (let-values ([(ok refusal) (answer-permission client handle request-id decision)])
           (if ok
               (print-line (format "the permission ask ~a is answered: ~a" request-id decision))
               (print-line (format "the answer was refused: ~a" (hash-ref refusal 'what "the agent refused the answer"))))))]))

(define (agent-end-verb args)
  (define client (client-from-environment))
  (define handle (read-handle))
  (if (not handle)
      (print-line "there is no session open: attach an agent first")
      (let-values ([(ok refusal) (end-session client handle)])
        (if ok
            (print-line "the session is ended")
            (print-line (format "the end was refused: ~a" (hash-ref refusal 'what "the session could not be ended")))))))

(provide send-verb
         audit-verb
         audit-accept-verb
         audit-undo-verb
         agent-verb
         permit-verb
         agent-end-verb)
