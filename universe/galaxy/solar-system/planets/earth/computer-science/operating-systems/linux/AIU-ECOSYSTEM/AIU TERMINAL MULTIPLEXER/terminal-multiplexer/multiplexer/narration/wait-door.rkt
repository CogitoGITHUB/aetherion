#lang racket/base
(require "narration.rkt"
         "../errors/err.rkt"
         "../errors/raise.rkt")

(provide (struct-out wait-token)
         wait-for
         wait-done)

(struct wait-token (run label why started-ms id) #:transparent)

(define (wait-for r label #:why why #:how [how "a blocking call"])
  (unless (and (string? why) (not (blank-string? why)))
    (raise-error "a wait reason was blank"
                 "narration/wait-for"
                 label
                 "no reason was given; a wait without a reason is a wait nobody can read"
                 #:rule 'wait/why-mandatory))
  (define e (narrate r 'WAIT label #:why why #:how how))
  (wait-token r label why (mono-ms) (event-id e)))

(define (wait-done token #:result [result #f])
  (narrate (wait-token-run token)
           'WAIT-DONE
           (wait-token-label token)
           #:why (wait-token-why token)
           #:how "the block returned"
           #:result result
           #:parent (wait-token-id token)
           #:duration-ms (- (mono-ms) (wait-token-started-ms token))))
