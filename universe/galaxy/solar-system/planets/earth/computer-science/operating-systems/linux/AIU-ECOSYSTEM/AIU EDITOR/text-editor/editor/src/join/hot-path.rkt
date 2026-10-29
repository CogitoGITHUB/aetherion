#lang racket/base
;; One job: the call that asks the hot path — the Rust side of the seam.
;; The hot path is the binary that holds the text state and the journal.
;; It is asked over the same file wire the meaning side uses: one request
;; file, one answer file, one child. The child holds no session of its
;; own, so every question starts it and ends it; the state lives in the
;; file and in the journal.

(require "transport.rkt"
         "live-wire.rkt"
         "../machine/directories.rkt")

;; first-call-ms holds how long the first call to the hot path took.
;; The hot path is a child: every question starts it and ends it, so its
;; start is the time its first question took.
(define first-call-ms (box #f))

;; ask-hot sends one request to the hot path and answers its response.
;; The arguments are names and values, all strings: the hot path's reader
;; stays small and never guesses. The first call is measured, because
;; that is the hot path's start.
;;
;; When the live session has a wire open, the question goes over it: the
;; child is already running, so a key pays no program start. Every other
;; caller — a scripted session, a verb, a gate stage — has no wire, and
;; the question starts the child once, as it always did.
(define (ask-hot op args)
  (define started (current-inexact-milliseconds))
  (define request (hasheq 'op op 'args args))
  (define live (current-wire))
  (define answer
    (if live
        (wire-ask live request)
        (call-over-wire (hot-path-bin) '() request)))
  (when (not (unbox first-call-ms))
    (set-box! first-call-ms
              (inexact->exact (round (- (current-inexact-milliseconds) started)))))
  answer)

;; hot-path-start-ms answers the hot path's measured start, or nothing
;; when the hot path has not been called yet.
(define (hot-path-start-ms)
  (unbox first-call-ms))

;; The call that asks the hot path.
(provide ask-hot
         hot-path-start-ms)
