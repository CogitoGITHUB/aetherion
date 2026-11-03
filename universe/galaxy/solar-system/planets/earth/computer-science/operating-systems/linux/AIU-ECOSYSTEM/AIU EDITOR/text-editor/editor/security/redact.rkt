#lang racket/base

(require racket/string)

(define (redact-text text)
  (define secret-words
    '("api_key" "api-key" "apikey" "password" "passwd" "secret" "token"
      "authorization" "sk-" "bearer " "-----begin"))

  (define (names-a-credential? line)
    (for/or ([word (in-list secret-words)])
      (string-contains? (string-downcase line) (string-downcase word))))

  (define (separator-at line)
    (define colon (index-of line ":"))
    (define equals (index-of line "="))
    (cond
      [(and (not colon) (not equals)) #f]
      [(and colon (not equals)) colon]
      [(and (not colon) equals) equals]
      [else (min colon equals)]))

  (define (index-of line piece)
    (let loop ([at 0])
      (cond
        [(> (+ at (string-length piece)) (string-length line)) #f]
        [(string=? (substring line at (+ at (string-length piece))) piece) at]
        [else (loop (add1 at))])))


  (define (hide-value line)
    (define at (separator-at line))
    (if at
        (string-append (substring line 0 at) "[redacted]")
        "[redacted]"))

  (string-join (for/list ([line (in-list (string-split text "\n"))])
                 (if (names-a-credential? line) (hide-value line) line))
               "\n"))

(provide redact-text)
