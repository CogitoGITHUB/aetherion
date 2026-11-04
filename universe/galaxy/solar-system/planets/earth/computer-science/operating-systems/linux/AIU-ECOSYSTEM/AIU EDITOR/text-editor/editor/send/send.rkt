#lang racket/base

(require racket/file
         racket/list
         racket/path
         racket/string
         "../checkpoint/checkpoint.rkt"
         "../commands/commands-shared.rkt"
         "../security/security.rkt"
         "adapter.rkt"
         "bundle.rkt"
         "opencode-adapter.rkt")

(define (send-command session words)
  (define target (if (null? words) "opencode" (car words)))
  (define why (if (null? words) "" (string-join (cdr words) " ")))
  (cond
    [(not (agent-known? target))
     (cons #t (format "the send was refused: there is no adapter for the agent named ~a — the only adapter is opencode" target))]
    [else
     (define the-bundle
       (make-bundle "aiu-editor" "aiu-ecosystem" target
                    (selection-text session)
                    (path->string (session-file session))
                    (the-point session)
                    #f
                    why))
     (if (not the-bundle)
         (cons #t "a send needs a why: say what the sender was doing")
         (send-bundle session the-bundle))]))

(define (agent-known? target)
  (string=? target "opencode"))

(define (send-bundle session the-bundle)
  (define tree (tree-root (session-file session)))
  (define made (if (checkpoint-needed? "send")
                   (checkpoint tree (bundle-why the-bundle))
                   #f))
  (define client (client-from-environment))
  (define-values (handle attach-refusal) (attach client))
  (define feed (subscribe client))
  (if (not made)
      (cons #t "the send was refused: the tree could not be checkpointed, so nothing was sent")
      (if (not handle)
          (cons #t (format "the send was refused: ~a" (refusal-text attach-refusal)))
          (if (not feed)
              (cons #t "the send was refused: the event feed did not open, so nothing was sent")
              (let-values ([(message refusal) (deliver client handle the-bundle)])
                (if (not message)
                    (cons #t (format "the send was refused: ~a" (refusal-text refusal)))
                    (cons #t (string-join (send-answer client handle feed the-bundle made) "\n"))))))))

(define (send-answer client handle feed the-bundle made)
  (define-values (the-events the-text refusal) (events client handle feed))
  (append
   (list (format "sent to ~a (the checkpoint is ~a)" (bundle-target the-bundle) made))
   (list "the bundle:")
   (bundle-lines the-bundle)
   (if (string=? the-text "")
       '()
       (list "the agent said:" the-text))
   (for/list ([event (in-list the-events)])
     (format "event: ~a" (hash-ref event 'type "unknown")))
   (let ([asks (client-permissions client handle)])
     (if (null? asks)
         '()
         (append
          (list "the agent asks for a permission:")
          (for/list ([ask (in-list asks)])
            (format "ask: ~a  action: ~a  files: ~a  answer with: permit once|always|reject ~a"
                    (hash-ref ask 'id "unknown")
                    (hash-ref ask 'action "unknown")
                    (string-join (ask-files ask) " ")
                    (hash-ref ask 'id "unknown"))))))))

(define (refusal-text refusal)
  (if (hash? refusal)
      (format "~a — ~a" (hash-ref refusal 'what "the agent refused the call")
              (hash-ref refusal 'what_to_do "the agent boundary is the one way to reach one"))
      "the agent refused the call"))

(hash-set! commands "send" send-command)

(provide send-command
         agent-known?)
