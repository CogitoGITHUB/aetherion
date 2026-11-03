#lang racket/base

(require "../errors/raise.rkt")

(struct cancel-token (closed? signal) #:mutable #:transparent)

(define (new-cancel-token)
  (cancel-token #f (make-semaphore)))

(define (cancelled? t)
  (cancel-token-closed? t))

(define (cancel t)
  (unless (cancelled? t)
    (set-cancel-token-closed?! t #t)
    (semaphore-post (cancel-token-signal t))))

(define (check-cancel t who what)
  (when (cancelled? t)
    (error-of 'err-cancelled who what
              "the call was cancelled before it acted"
              "the caller stopped waiting for this work")))

(define (await-cancel t)
  (sync (cancel-token-signal t)))

(provide cancel-token
         cancel-token-closed?
         cancel-token-signal
         new-cancel-token
         cancelled?
         cancel
         check-cancel
         await-cancel)
