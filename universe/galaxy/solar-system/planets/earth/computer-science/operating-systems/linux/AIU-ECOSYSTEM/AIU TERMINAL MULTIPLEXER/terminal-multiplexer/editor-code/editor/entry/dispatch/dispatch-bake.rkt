#lang racket/base

(require racket/list
         racket/path
         racket/port
         racket/string
         "../../narration/print-console.rkt"
         "../../narration/narration.rkt"
         "../../machine/directories.rkt"
         "../../commands/commands.rkt"
         "../../commands/tasks.rkt"
         "../../devloop/bake.rkt"
         "../../devloop/last-good.rkt"
         "../../routes/keyboard.rkt"
         "../../routes/keymaps.rkt"
         "../../routes/routes.rkt"
         "../../join/hot-path.rkt"
         "../../join/protocol.rkt"
         "../../bridge/document.rkt"
         "../../bridge/host.rkt")

(provide bake-verb)

(define (baked-good? path)
  (with-handlers ([exn:fail? (lambda (why) #f)])
    (define tables (dynamic-require (make-resolved-module-path path) 'baked-tables))
    (equal? tables keymaps)))

(define (bake-verb args)
  (define result (bake keymaps baked-good?))
  (define path (car result))
  (define good (cadr result))
  (define rust (caddr result))
  (print-line (format "baked: ~a" path))
  (if good
      (print-line (format "the bake is good and is now the last good: ~a" (last-good)))
      (print-line (format "the bake is NOT good; the last good stays: ~a"
                          (or (last-good) "there is none"))))
  (print-line
   (format "the hot path was built: ~a (in ~a ms; the build said what it said in ~a)"
           (if (hash-ref rust 'good #f) "yes" "NO")
           (hash-ref rust 'ms 0)
           (hash-ref rust 'log "-"))))
