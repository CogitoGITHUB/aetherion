#lang racket/base
;; One job: the agent verbs of the argv dispatch - send, audit, audit-accept,
;; audit-undo, agent, permit and agent-end. The table that names them stays
;; in dispatch.rkt, which requires this file.

(require racket/list
         racket/path
         racket/port
         racket/string
         "../narration/print-console.rkt"
         "../narration/narration.rkt"
         "../machine/directories.rkt"
         "../commands/commands.rkt"
         "../checkpoint/checkpoint.rkt"
         "../send/adapter.rkt"
         "../send/bundle.rkt"
         "../send/send.rkt"
         "../send/opencode-adapter.rkt"
         "../audit/audit.rkt"
         "../audit/accept.rkt"
         "../join/hot-path.rkt"
         "../join/protocol.rkt")

;; send-verb sends what is selected to the named agent: it makes the
;; checkpoint, delivers the bundle and answers the whole truth of the
;; send. The file is the one being edited, the target is the named
;; agent, and the why is the rest of the words. A send without a why is
;; refused.
(define (send-verb args)
  (define file (if (null? args) "" (car args)))
  (define rest (if (null? args) '() (cdr args)))
  (define target (if (null? rest) "opencode" (car rest)))
  (define why (if (null? rest) "" (string-join (cdr rest) " ")))
  (define path (path->complete-path (if (string=? file "") "untitled" file)))
  (define session (make-session path (journal-path-for path)))
  ;; the verb runs the ONE command, so the verb and the key do the same
  ;; thing: the same bundle, the same checkpoint, the same refusal
  (define answer (send-command session (cons target (if (string=? why "") '() (list why)))))
  (print-line (cdr answer))
  ;; the audit runs after the send: the change the agent made appears as
  ;; a mark, and a change nobody reported is marked external
  (define client (client-from-environment))
  (define handle (read-handle))
  (define marks (observe-changes (tree-root path) (last-checkpoint) client handle))
  (unless (null? marks)
    (print-line "the audit:")
    (for-each (lambda (mark) (print-line (mark-line mark))) marks)))

;; mark-line answers one mark as one line of text: what changed, who
;; changed it, when, and the checkpoint it is judged against.
(define (mark-line mark)
  (format "~a  who: ~a  at: ~a  checkpoint: ~a"
          (hash-ref mark 'path "?")
          (hash-ref mark 'who "?")
          (hash-ref mark 'utc "-")
          (hash-ref mark 'checkpoint "-")))

;; last-checkpoint answers the newest checkpoint the tree has, or
;; nothing when there is none.
(define (last-checkpoint)
  (define all (checkpoints))
  (if (null? all) "" (car (reverse all))))

;; audit-verb answers the audit: the marks, one per line. Reading the
;; state is free (rule 07).
(define (audit-verb args)
  ;; the audit looks at the tree FIRST: the question is what changed
  ;; since the last checkpoint, and the marks are the answer
  (define root (tree-root (if (null? args) (current-directory) (car args))))
  (observe-changes root (last-checkpoint) (client-from-environment) (read-handle))
  (if (null? (audit-marks))
      (print-line "the audit holds no mark: nothing changed that was seen")
      (for-each (lambda (mark) (print-line (mark-line mark))) (audit-marks))))

;; audit-accept-verb accepts a change: the human wanted it, and the
;; acceptance is recorded beside the mark.
(define (audit-accept-verb args)
  (define path (if (null? args) "" (car args)))
  (define mark (mark-of path))
  (if (not mark)
      (print-line (format "the audit holds no mark for ~a" path))
      (begin (accept-mark mark)
             (print-line (format "the change is accepted: ~a" path)))))

;; audit-undo-verb undoes a change: the file goes back to the state the
;; checkpoint had. The undo refuses by name when the file changed again
;; since the mark.
(define (audit-undo-verb args)
  (define path (if (null? args) "" (car args)))
  (define mark (mark-of path))
  (if (not mark)
      (print-line (format "the audit holds no mark for ~a" path))
      (let ([answer (undo-mark (tree-root (path->complete-path path)) mark)])
        (print-line (if (car answer) (car answer) (cdr answer))))))

;; mark-of answers the newest mark of a path, or nothing when the audit
;; holds no mark of it.
(define (mark-of path)
  ;; the mark holds the whole path, and the human may give it in any
  ;; way: both are made whole before they are compared
  (define wanted (path->string (simplify-path (path->complete-path path))))
  (define found
    (filter (lambda (mark)
              (string=? (hash-ref mark 'path "") wanted))
            (audit-marks)))
  (if (null? found) #f (car (reverse found))))

;; agent-verb answers the agent's state: the two pins, the session that
;; is open, and the permission asks that wait for the human. The state
;; is read, and reading is free (rule 07).
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

;; permit-verb answers one permission ask the way the human said: once,
;; always or reject. The approval is never inferred, and the request id
;; is the id the ask was named with.
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

;; agent-end-verb ends the session with the agent and forgets the
;; handle: the session outlives the caller's screen, and this is how it
;; is closed.
(define (agent-end-verb args)
  (define client (client-from-environment))
  (define handle (read-handle))
  (if (not handle)
      (print-line "there is no session open: attach an agent first")
      (let-values ([(ok refusal) (end-session client handle)])
        (if ok
            (print-line "the session is ended")
            (print-line (format "the end was refused: ~a" (hash-ref refusal 'what "the session could not be ended")))))))

;; The agent verbs, for the table in dispatch.rkt.
(provide send-verb
         audit-verb
         audit-accept-verb
         audit-undo-verb
         agent-verb
         permit-verb
         agent-end-verb)
