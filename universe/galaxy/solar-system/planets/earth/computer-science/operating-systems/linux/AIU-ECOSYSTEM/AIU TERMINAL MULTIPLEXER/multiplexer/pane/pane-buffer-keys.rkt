#lang racket/base
(provide split-buffer-keys)

(define (split-buffer-keys input)
  (define size (bytes-length input))
  (let loop ([i 0] [found null])
    (define (stop) (values (subbytes input i) (reverse found)))
    (cond
      [(>= i size) (stop)]
      [else
       (define byte (bytes-ref input i))
       (cond
         [(= byte 104) (loop (+ i 1) (cons (quote previous) found))]
         [(= byte 116) (loop (+ i 1) (cons (quote next) found))]
         [(= byte 110) (loop (+ i 1) (cons (quote new) found))]
         [(= byte 99) (loop (+ i 1) (cons (quote close) found))]
         [else (stop)])])))
