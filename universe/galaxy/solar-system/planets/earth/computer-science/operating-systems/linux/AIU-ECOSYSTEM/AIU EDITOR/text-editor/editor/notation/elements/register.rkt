#lang racket/base
(require racket/file
         racket/runtime-path
         racket/string
         "../errors/raise.rkt")

(provide register load-blocktypes-near! known-name? element-for element-names require-known (struct-out element))

(struct element (name kind opaque?) #:transparent)

(define-runtime-path default-dir "../blocktypes")

(define active (box #f))

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

(define (elements-in dir)
  (for/list ([p (in-list (sort (directory-list dir #:build? #t) path<?))]
             #:when (regexp-match? #rx"[.]blocktype$" (path->string p)))
    (element-from p)))

(define (folder-near file)
  (let loop ([dir (let-values ([(base name must-be-dir) (split-path (path->complete-path file))]) base)])
    (cond
      [(not (path? dir)) #f]
      [(directory-exists? (build-path dir ".notation" "blocktypes"))
       (build-path dir ".notation" "blocktypes")]
      [else (let-values ([(base name must-be-dir) (split-path dir)]) (loop base))])))

(define (load-blocktypes-near! file)
  (define folder (and file (folder-near file)))
  (define found (and folder (elements-in folder)))
  (set-box! active (and found (pair? found) found))
  folder)

(define (register)
  (or (unbox active) (elements-in default-dir)))

(define (known-name? name)
  (and (memq name (map element-name (register))) #t))

(define (element-for name)
  (for/first ([e (in-list (register))] #:when (eq? (element-name e) name)) e))

(define (element-names)
  (map element-name (register)))

(define (require-known name)
  (unless (known-name? name)
    (raise-err (quote register) "register.rkt"
               (format "\"~a\" is not a registered block name; use one of ~a"
                       name (element-names)))))
