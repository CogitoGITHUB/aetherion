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
           [(102) (quote float-toggle)]
           [(49) (quote float-todo)]
           [(50) (quote float-journal)]
           [(51) (quote float-notes)]
           [(122) (quote float-size)]
           [(103) (quote float-grow)]
           [(107) (quote float-shrink)]
           [else #f]))
       (if command (loop (+ i 1) (cons command found)) (stop))])))
