#lang racket/base

(require "transport-shared.rkt"
         "live-wire-shared.rkt"
         "../machine/directories-shared.rkt")

(define first-call-ms (box #f))

(define (ask-hot-raw op args)
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

(define edit-ops (list "type" "delete" "delete-at" "insert-at"))

(define dirty-hook (box void))

(define edit-hook (box void))

(define read-ops (list "notation" "show" "notation-render" "notation-view"))

(define kept-answers (make-hash))

(define (ask-hot op args)
  (cond
    [(member op read-ops)
     (let* ([key (cons op args)] [hit (hash-ref kept-answers key #f)])
       (or hit (let ([got (ask-hot-raw op args)]) (hash-set! kept-answers key got) got)))]
    [else
     (hash-clear! kept-answers)
     (let ([got (ask-hot-raw op args)]) (when (member op edit-ops) ((unbox dirty-hook))) (hash-clear! kept-answers) got)]))

(define (hot-path-start-ms)
  (unbox first-call-ms))

(provide edit-hook dirty-hook ask-hot
         hot-path-start-ms)
