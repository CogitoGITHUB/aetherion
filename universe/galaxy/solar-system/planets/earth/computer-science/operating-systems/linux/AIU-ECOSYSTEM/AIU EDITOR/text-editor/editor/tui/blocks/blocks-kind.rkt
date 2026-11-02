#lang racket/base
;; One job: the kind-* keys that pick which kind of block the block keys move between.
(require "../../commands/commands.rkt")

;; blockview-kind-setter answers a command that picks one kind and says which.
(define (blockview-kind-setter want)
  (lambda (session words)
    (set-box! kind-filter want)
    (cons #t (format "kind: ~a" want))))

(for-each
 (lambda (pair) (hash-set! commands (car pair) (blockview-kind-setter (cdr pair))))
 (list (cons "kind-any" "any")
       (cons "kind-paragraph" "paragraph")
       (cons "kind-section" "section")
       (cons "kind-code" "code")
       (cons "kind-comment" "comment")
       (cons "kind-title" "title")
       (cons "kind-todo" "todo")
       (cons "kind-todo-open" "todo open")
       (cons "kind-todo-done" "todo done")))
