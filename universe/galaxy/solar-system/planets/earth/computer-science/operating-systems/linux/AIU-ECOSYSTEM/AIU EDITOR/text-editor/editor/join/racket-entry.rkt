#lang racket/base

(require "protocol-shared.rkt"
         "../errors/err-shared.rkt"
         "../errors/raise-shared.rkt"
         "../narration/narration.rkt")

(define wire-in (current-input-port))

(define wire-out (current-output-port))

(define (answer-ping args)
  (hasheq 'pong #t 'who "the meaning side"))

(define (answer-echo args)
  (hasheq 'echo args))

(define operations
  (hash "ping" answer-ping
        "echo" answer-echo))

(define (answer-op op args)
  (define handler (hash-ref operations op #f))
  (if handler
      (handler args)
      (error-of 'err-unknown-op "the meaning side" op
                (format "there is no operation named ~a" op)
                "ask for one of: ping, echo")))

(define (serve)
  (define asked (read-request wire-in))
  (cond
    [(not asked) #f]
    [else
     (define answered
       (with-handlers
           ([exn:fail?
             (lambda (e)
               (define record (if (exn:fail:editor? e) (exn:fail:editor-err e) #f))
               (if record
                   (response #f (hasheq 'kind (symbol->string (err-kind record))
                                        'what (err-what record)
                                        'what_to_do (err-what-to-do record)))
                   (response #f (hasheq 'kind "err-unexpected"
                                        'what (exn-message e)
                                        'what_to_do "read the stderr of the meaning side"))))])
         (response #t (answer-op (request-op asked) (request-args asked)))))
     (write-response wire-out (response-ok answered) (response-data answered))
     answered]))

(define (main)
  (parameterize ([current-output-port (current-error-port)])
    (note "the meaning side"
          "waiting for a request on the wire; it ends on the answer")
    (serve)
    (void)))

(module+ main
  (main))

(provide serve
         answer-op
         operations)
