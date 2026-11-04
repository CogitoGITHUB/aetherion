#lang racket/base
(require "../../commands/commands-shared.rkt")

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
