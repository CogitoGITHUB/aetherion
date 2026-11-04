#lang racket/base
(provide decode-complete-prefix)
(define (incomplete-tail-length input)
  (define n (bytes-length input))
  (let loop ([back 1])
    (cond
      [(or (> back 3) (> back n)) 0]
      [else
       (define byte (bytes-ref input (- n back)))
       (cond
         [(< byte #x80) 0]
         [(>= byte #xC0)
          (define need (cond [(>= byte #xF0) 4] [(>= byte #xE0) 3] [else 2]))
          (if (< back need) back 0)]
         [else (loop (add1 back))])])))
(define (decode-complete-prefix input)
  (define keep (incomplete-tail-length input))
  (define cut (- (bytes-length input) keep))
  (values (bytes->string/utf-8 (subbytes input 0 cut) #\uFFFD) (subbytes input cut)))
