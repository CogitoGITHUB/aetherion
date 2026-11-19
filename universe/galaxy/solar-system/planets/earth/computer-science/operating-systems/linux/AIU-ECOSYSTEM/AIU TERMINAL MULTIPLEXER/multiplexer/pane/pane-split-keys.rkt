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
           [(104) (quote focus-left)]
           [(115) (quote focus-right)]
           [(116) (quote focus-down)]
           [(110) (quote focus-up)]
           [(118) (quote split-right)]
           [(119) (quote split-down)]
           [(99) (quote close)] [(100) (quote close)] [(72) (quote swap-left)] [(84) (quote swap-down)] [(78) (quote swap-up)] [(83) (quote swap-right)]
           [(102) (quote float-toggle)]
           [(49) (quote float-todo)]
           [(50) (quote float-journal)]
           [(51) (quote float-notes)]
           [(101) (quote float-settings)]
           [(122) (quote float-size)]
           [(103) (quote float-grow)]
           [(107) (quote float-shrink)]
             [(109) (quote float-grow)]
             [(98) (quote float-shrink)]
           [else #f]))
       (if command (loop (+ i 1) (cons command found)) (stop))])))
