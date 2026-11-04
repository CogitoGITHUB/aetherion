#lang racket/base

(require racket/string
         "../join/hot-path-shared.rkt"
         "../join/protocol-shared.rkt"
         "keymaps-shared.rkt")

(define (key-names bytes)
  (define runs (key-runs bytes))
  (map car runs))

(define (key-runs bytes)
  (define answer (ask-hot "keys" (hasheq 'bytes (bytes->hex bytes))))
  (if (response-ok answer)
      (let ([data (response-data answer)])
        (runs-of (hash-ref data 'names "") (hash-ref data 'lengths "")))
      '()))

(define (runs-of names lengths)
  (if (string=? names "")
      '()
      (for/list ([name (in-list (string-split names " "))]
                 [length (in-list (string-split lengths ","))])
        (cons name (string->number length)))))

(define (bytes->hex bytes)
  (string-join
   (for/list ([b (in-list bytes)])
     (format "~a~a" (if (< b 16) "0" "") (number->string b 16)))
   ""))

(define (route-of-key key program-claims layer)
  (define bound (binding-of layer key))
  (cond
    [bound (list layer bound)]
    [(and (string=? layer "write") (text-key? key)) (list layer key)]
    [else (list "unclaimed" "")]))

(define (text-key? key)
  (and (= (string-length key) 1)
       (not (string-prefix? key "C-"))
       (not (string-prefix? key "M-"))
       (not (string-prefix? key "S-"))))

(define (key-bytes name)
  (define answer (ask-hot "key-bytes" (hasheq 'name name)))
  (if (response-ok answer)
      (hash-ref (response-data answer) 'bytes "")
      ""))

(define (hex->bytes hex)
  (define digits (filter (lambda (c) (char-hex-digit? c)) (string->list hex)))
  (let loop ([at 0] [bytes '()])
    (if (>= (+ at 1) (length digits))
        (reverse bytes)
        (loop (+ at 2)
              (cons (string->number (substring hex at (+ at 2)) 16) bytes)))))

(define (char-hex-digit? c)
  (or (char-numeric? c) (char<=? #\a c) (char<=? c #\f) (char<=? #\A c) (char<=? c #\F)))

(provide key-names
         key-runs
         key-bytes
         bytes->hex
         hex->bytes
         route-of-key
         text-key?)
