#lang racket/base

(require racket/list
         racket/string
         "../join/protocol.rkt"
         "../join/hot-path.rkt")

(define (replay-state file journal)
  (ask-hot "replay" (hasheq 'file (path->string file)
                            'journal (path->string journal))))

(define (key<? a b)
  (string<? (if (symbol? a) (symbol->string a) a)
            (if (symbol? b) (symbol->string b) b)))

(define (replay-report answer)
  (define data (response-data answer))
  (define pairs
    (for/list ([key (sort (hash-keys data) key<?)]
               #:unless (eq? key 'text))
      (format "~a=~a" key (hash-ref data key))))
  (if (response-ok answer)
      (string-join pairs " ")
      (string-append "FAIL " (string-join pairs " "))))

(provide replay-state
         replay-report)
