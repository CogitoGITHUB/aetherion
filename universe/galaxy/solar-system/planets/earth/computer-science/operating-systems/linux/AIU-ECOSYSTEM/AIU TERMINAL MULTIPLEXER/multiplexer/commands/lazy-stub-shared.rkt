#lang racket/base
(require "commands-shared.rkt")

(define (lazy-layer! vref file label missing names)
  (define table (make-hash))
  (define src (variable-reference->module-source vref))
  (define path
    (and (path? src)
         (let-values ([(base nm dir?) (split-path src)])
           (and (path? base) (simplify-path (build-path base file))))))
  (for ([name (in-list names)])
    (hash-set! commands name
               (lambda (session words)
                 (with-handlers ([void (lambda (e) (cons #t (format "~a failed: ~a" label (if (exn? e) (exn-message e) e))))])
                   (when path (dynamic-require path #f))
                   (let ([f (hash-ref table name #f)])
                     (if f (f session words) (cons #t missing)))))))
  table)

(provide lazy-layer!)
