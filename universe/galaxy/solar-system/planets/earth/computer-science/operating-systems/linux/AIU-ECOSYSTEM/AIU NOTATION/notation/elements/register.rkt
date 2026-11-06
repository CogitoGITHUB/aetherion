#lang racket/base
(require racket/file
         racket/runtime-path
         racket/string
         "../errors/raise.rkt")

(provide register known-name? element-for element-names require-known (struct-out element))

(struct element (name kind opaque?) #:transparent)

(define-runtime-path types-dir "../blocktypes")

(define (fields-of path)
  (for/hash ([line (in-list (file->lines path))]
             #:when (regexp-match? #rx"^[a-z-]+:" line))
    (define m (regexp-match #rx"^([a-z-]+): *(.*)$" line))
    (values (cadr m) (string-trim (caddr m)))))

(define (element-from path)
  (define f (fields-of path))
  (element (string->symbol (hash-ref f "name"))
           (hash-ref f "kind" "")
           (equal? (hash-ref f "opaque" "no") "yes")))

(define register
  (for/list ([p (in-list (sort (directory-list types-dir #:build? #t) path<?))]
             #:when (regexp-match? #rx"[.]blocktype$" (path->string p)))
    (element-from p)))

(define (known-name? name)
  (and (memq name (map element-name register)) #t))

(define (element-for name)
  (for/first ([e (in-list register)] #:when (eq? (element-name e) name)) e))

(define (element-names)
  (map element-name register))

(define (require-known name)
  (unless (known-name? name)
    (raise-err (quote register) "register.rkt"
               (format "\"~a\" is not a registered block name; use one of ~a"
                       name (element-names)))))
