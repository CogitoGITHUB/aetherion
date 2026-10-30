#lang racket/base
;; One job: argv to a command, fast. The quick screen is drawn first from a
;; module that needs only racket/base. An edit on a terminal then loads the
;; lean edit; every other call loads the full program in cli-full.rkt, where
;; the parser is. Nothing is loaded that the call does not need.
;;
;; Usage: racket cli.rkt edit FILE

(require "quick.rkt")

;; compile-deps holds the two programs as dependencies only, so raco make
;; builds them; they are never loaded from here.
(module compile-deps racket/base
  (require "cli-full.rkt" "lean.rkt"))

;; sibling answers the module path of a file next to this one.
(define (sibling name)
  (module-path-index-join name (variable-reference->module-path-index (#%variable-reference))))

;; The parser, for the outside world: the edit verb paints at once, then the
;; lean edit runs on a terminal and the full program runs everywhere else.
(module+ main
  (define args (vector->list (current-command-line-arguments)))
  (define edit? (and (pair? args) (string=? (car args) "edit")))
  (when edit?
    (quick-show (and (pair? (cdr args)) (cadr args))))
  (if (and edit? (terminal-port? (current-input-port)))
      ((dynamic-require (sibling "lean.rkt") (quote lean-edit)) (cdr args))
      ((dynamic-require (sibling "cli-full.rkt") (quote main)))))
