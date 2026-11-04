#lang racket/base

(require racket/list
         racket/string
         "checkpoint.rkt")

(define (rollback root commit)
  (cond
    [(string=? (string-trim commit) "")
     (list #f "a rollback needs the name of a checkpoint")]
    [(not (git-ok? root "cat-file" "-e" commit))
     (list #f (format "there is no checkpoint named ~a" commit))]
    [else
     (define moved (run-git root "reset" "--hard" commit))
     (if (string=? moved "")
         (list #f (format "the tree could not go back to ~a" commit))
         (list (string-trim commit) #f))]))

(provide rollback)
