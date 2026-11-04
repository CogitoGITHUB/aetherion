#lang racket/base
(provide route-keys)
(define prefix-byte 29)
(define quit-after-prefix-byte 113)
(define (route-keys state input)
  (define out (open-output-bytes))
  (define-values (final quit?)
    (for/fold ([state state] [quit? #f]) ([byte (in-bytes input)])
      (cond
        [quit? (values state quit?)]
        [(eq? state (quote prefixed))
         (cond
           [(= byte quit-after-prefix-byte) (values (quote plain) #t)]
           [(= byte prefix-byte) (write-byte byte out) (values (quote plain) #f)]
           [else (values (quote plain) #f)])]
        [(= byte prefix-byte) (values (quote prefixed) #f)]
        [else (write-byte byte out) (values state #f)])))
  (values (get-output-bytes out) final quit?))
