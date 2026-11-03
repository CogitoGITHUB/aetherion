#lang racket/base
;; One job: the bake verb of the argv dispatch.

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
         "../../notation/document.rkt"
         "../../notation/host.rkt")

(provide bake-verb)

;; baked-good? asks whether the baked module holds the tables it was
;; given: the bake is good when what it wrote is what it was given.
(define (baked-good? path)
  (with-handlers ([exn:fail? (lambda (why) #f)])
    (define tables (dynamic-require (make-resolved-module-path path) 'baked-tables))
    (equal? tables keymaps)))

;; bake-verb bakes the config: the tables become first-class defaults in
;; a generated module, the bake checks the result, and the last good is
;; kept only when the check says yes. A bake that is not good never
;; ships.
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
  ;; the RUST half is said too: a half that was not built is named, and
  ;; it is never silent
  (print-line
   (format "the hot path was built: ~a (in ~a ms; the build said what it said in ~a)"
           (if (hash-ref rust 'good #f) "yes" "NO")
           (hash-ref rust 'ms 0)
           (hash-ref rust 'log "-"))))
