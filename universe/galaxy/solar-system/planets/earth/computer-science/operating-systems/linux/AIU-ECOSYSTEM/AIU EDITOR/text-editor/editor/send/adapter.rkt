#lang racket/base

(require racket/file
         racket/list
         racket/port
         racket/string
         "../machine/directories-shared.rkt"
         "../machine/stop-switch.rkt"
         "../security/redact.rkt"
         "bundle.rkt"
         "opencode-adapter.rkt")

(define session-file
  (build-path (state-dir) "agent-session"))

(define (attach client)
  (define existing (read-handle))
  (if existing
      (values existing #f)
      (let-values ([(handle refusal) (client-open client)])
        (if handle
            (begin (write-handle handle) (values handle #f))
            (values #f refusal)))))

(define (read-handle)
  (if (file-exists? session-file)
      (let ([text (call-with-input-file session-file
                                       (lambda (port) (read-line port)))] )
        (if (string=? (string-trim text) "") #f (string-trim text)))
      #f))

(define (write-handle handle)
  (ensure-dir (state-dir))
  (call-with-output-file session-file
    (lambda (port) (display handle port))
    #:exists 'truncate)
  handle)

(define (forget-handle)
  (when (file-exists? session-file)
    (delete-file session-file))
  #f)

(define (deliver client handle bundle)
  (cond
    [(stopped?)
     (values #f (refusal "the stop switch is thrown: every agent session for this project stops"))]
    [(not (bundle? bundle))
     (values #f (refusal "there is no bundle to send"))]
    [(not handle)
     (values #f (refusal "no session is open: attach an agent first"))]
    [else
     (define-values (message refusal)
       (client-deliver client handle (redact-text (bundle-text bundle))))
     (if message (values message #f) (values #f refusal))]))

(define (subscribe client)
  (client-open-feed client))

(define (events client handle feed)
  (if (not handle)
      (values '() "" (refusal "no session is open: attach an agent first"))
      (client-turn feed handle)))

(define (answer-permission client handle request-id decision)
  (cond
    [(stopped?)
     (values #f (refusal "the stop switch is thrown: every agent session for this project stops"))]
    [(not handle)
     (values #f (refusal "no session is open: attach an agent first"))]
    [else (client-reply client handle request-id decision)]))

(define (cancel client handle)
  (if (not handle)
      (values #f (refusal "no session is open: attach an agent first"))
      (client-cancel client handle)))

(define (end-session client handle)
  (if (not handle)
      (values #f (refusal "no session is open: attach an agent first"))
      (let-values ([(ok refusal) (client-end client handle)])
        (forget-handle)
        (if ok (values #t #f) (values #f refusal)))))

(define (pins client)
  (hash 'boundary boundary-version
        'agent (client-version client)))

(define (refusal what)
  (hash 'kind "err-no-agent"
        'who "opencode"
        'what what
        'what_to_do "attach an agent first: the agent boundary is the one way to reach one"))

(provide attach
         read-handle
         write-handle
         forget-handle
         deliver
         subscribe
         events
         answer-permission
         cancel
         end-session
         pins
         refusal)
