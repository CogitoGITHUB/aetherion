#lang racket/base
(provide split-pane-keys)

(define (split-pane-keys input)
  (define size (bytes-length input))
  (let loop ([i 0] [found null])
    (define (stop) (values (subbytes input i) (reverse found)))
    (cond
      [(>= i size) (stop)]
      [else
       (define command
         (case (bytes-ref input i)
           [(100) (quote focus-left)]
           [(110) (quote focus-right)]
           [(104) (quote focus-down)]
           [(116) (quote focus-up)]
           [(114) (quote split-right)]
           [(115) (quote split-down)]
           [(99) (quote close)]
           [else #f]))
       (if command (loop (+ i 1) (cons command found)) (stop))])))
