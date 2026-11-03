#lang racket/base

(require racket/list
         racket/set
         "../editor/routes/routes.rkt"
         "../editor/commands/commands.rkt"
         "../editor/tui/blocks/blocks-edit.rkt"
         "../editor/tui/blocks/blocks-move.rkt"
         "../editor/tui/blocks/blocks-text.rkt"
         "../editor/tui/tabs/tabs-commands.rkt"
         "../editor/tui/float/explorer.rkt")

(define known-commands
  (for/set ([name (in-list (hash-keys commands))]) name))

(define (unknown-command-routes)
  (for/list ([route (in-list (route-commands))]
             #:unless (set-member? known-commands (third route)))
    route))

(define (main)
  (define collisions (reserved-prefix-collisions))
  (define unknown (unknown-command-routes))
  (define route-count (length (route-commands)))
  (if (and (null? collisions) (null? unknown))
      (begin
        (printf "OK route-check — ~a routes checked, the reserved prefix is bound by no layer, every route names a command that exists\n"
                route-count)
        (exit 0))
      (begin
        (for-each (lambda (collision)
                    (printf "ROUTE — the key ~a in the layer ~a is the reserved prefix; the multiplexer keeps it and no layer may bind it\n"
                            (second collision) (first collision)))
                  collisions)
        (for-each (lambda (route)
                    (printf "ROUTE — the route ~a ~a names the command ~a, and the command table does not hold it\n"
                            (first route) (second route) (third route)))
                  unknown)
        (printf "ROUTE — ~a faults in ~a routes\n"
                (+ (length collisions) (length unknown))
                route-count)
        (exit 1))))

(module+ main
  (main))
