#lang racket/base

(require json)

(struct request (op args) #:transparent)

(struct response (ok data) #:transparent)

(define (write-request port op args)
  (write-message port (hasheq 'op op 'args args)))

(define (read-request port)
  (define line (read-line port 'any))
  (cond
    [(eof-object? line) #f]
    [else
     (define value (string->jsexpr line))
     (unless (and (hash? value) (hash-has-key? value 'op))
       (error 'protocol-refused
              "a line on the wire is not a request: ~a" line))
     (request (hash-ref value 'op) (hash-ref value 'args (hasheq)))]))

(define (write-response port ok data)
  (write-message port (hasheq 'ok (if ok #t #f) 'data data)))

(define (read-response port)
  (define line (read-line port 'any))
  (if (eof-object? line)
      #f
      (let* ([value (string->jsexpr line)]
             [ok (hash-ref value 'ok #f)])
        (response (if (eq? ok #t) #t #f) (hash-ref value 'data #f)))))

(define (write-message port value)
  (displayln (jsexpr->string value) port)
  (flush-output port))

(provide request
         response
         request-op
         request-args
         response-ok
         response-data
         write-request
         read-request
         write-response
         read-response
         write-message)
