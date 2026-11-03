#lang racket/base

(require racket/runtime-path
         "protocol.rkt"
         "transport.rkt"
         "../machine/directories.rkt")

(define entry-name "racket-entry.rkt")

(define-runtime-path join-dir ".")

(define (ask op args)
  (call-over-wire (racket-bin) (list entry-name)
                  (hasheq 'op op 'args args) join-dir))

(provide ask
         entry-name
         join-dir)
