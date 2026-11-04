#lang racket/base
(provide split-scroll-keys scroll-command-bytes)

(define (scroll-command-bytes command)
  (case command
    [(line-up) (bytes 27 91 65)]
    [(line-down) (bytes 27 91 66)]
    [(page-up) (bytes 27 91 53 126)]
    [else (bytes 27 91 54 126)]))

(define (split-scroll-keys input)
  (define size (bytes-length input))
  (let loop ([i 0] [found null])
    (define (stop) (values (subbytes input i) (reverse found)))
    (cond
      [(>= i size) (stop)]
      [else
       (define byte (bytes-ref input i))
       (cond
         [(= byte 116) (loop (+ i 1) (cons (quote line-up) found))]
         [(= byte 104) (loop (+ i 1) (cons (quote line-down) found))]
         [(= byte 84) (loop (+ i 1) (cons (quote page-up) found))]
         [(= byte 72) (loop (+ i 1) (cons (quote page-down) found))]
         [else (stop)])])))
