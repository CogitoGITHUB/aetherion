#lang racket/base

(require racket/list
         racket/string
         "events.rkt"
         "../errors/render.rkt")

(define output-format (make-parameter 'sexp))

(define (print-line text)
  (displayln text)
  (flush-output (current-output-port)))

(define (print-event e)
  (print-line (event->string e (output-format))))

(define (print-error e)
  (print-line (err-line e)))

(define (event->string e fmt)
  (if (eq? fmt 'json) (event->json e) (event->sexp e)))

(define (event->sexp e)
  (format "~a" (list (event-kind e) (event-who e) (event-why e)
                     (event-started e) (event-ended e) (event-duration-ms e)
                     (event-data e) (event-redacted e))))

(define (event->json e)
  (object->json (list (cons 'kind (symbol->string (event-kind e)))
                       (cons 'who (event-who e))
                       (cons 'why (event-why e))
                       (cons 'started (event-started e))
                       (cons 'ended (or (event-ended e) ""))
                       (cons 'duration_ms (or (event-duration-ms e) 0))
                       (cons 'data (event-data e))
                       (cons 'redacted (event-redacted e)))))

(define (value->json v)
  (cond
    [(eq? v #f) "null"]
    [(eq? v #t) "true"]
    [(string? v) (json-string v)]
    [(number? v) (number->string v)]
    [(and (list? v) (not (null? v)) (andmap pair? v)) (object->json v)]
    [(list? v) (array->json v)]
    [else (json-string (format "~a" v))]))

(define (object->json pairs)
  (define parts
    (map (lambda (p)
           (format "~a:~a" (json-string (symbol->string (car p))) (value->json (cdr p))))
         pairs))
  (format "{~a}" (string-join parts ",")))

(define (array->json vs)
  (format "[~a]" (string-join (map value->json vs) ",")))

(define (json-string s)
  (define out (open-output-string))
  (for ([c (in-string s)])
    (cond
      [(char=? c #\") (display "\\\"" out)]
      [(char=? c #\\) (display "\\\\" out)]
      [(char=? c #\newline) (display "\\n" out)]
      [(char=? c #\tab) (display "\\t" out)]
      [(char=? c #\return) (display "\\r" out)]
      [else (write-char c out)]))
  (format "\"~a\"" (get-output-string out)))

(provide output-format
         print-line
         print-event
         print-error
         event->string)
