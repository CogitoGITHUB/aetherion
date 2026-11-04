#lang racket/base

(require "quick.rkt")

(module compile-deps racket/base
  (require "cli-full.rkt" "lean.rkt" "../tui/float/shadow.rkt"))

(define (sibling name)
  (module-path-index-join name (variable-reference->module-path-index (#%variable-reference))))

(module+ main
  (define args (vector->list (current-command-line-arguments)))
  (define edit? (and (pair? args) (string=? (car args) "edit")))
  (define tool? (and (pair? args) (member (car args) (list "update" "test" "docs" "trace" "record" "record-module")) #t))
  (when edit?
    (quick-show (and (pair? (cdr args)) (cadr args))))
  (if tool?
      ((dynamic-require (sibling "update/update.rkt") (quote run)) args)
      (if (and edit? (terminal-port? (current-input-port)))
      ((dynamic-require (sibling "lean.rkt") (quote lean-edit)) (cdr args))
      ((dynamic-require (sibling "cli-full.rkt") (quote main))))))
