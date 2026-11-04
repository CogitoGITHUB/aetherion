#lang racket/base

(require racket/list
         racket/path
         racket/port
         racket/string
         "../../narration/print-console-shared.rkt"
         "../../narration/narration.rkt"
         "../../machine/directories-shared.rkt"
         "../../commands/commands-shared.rkt"
         "../../commands/tasks.rkt"
         "../../devloop/bake.rkt"
         "../../devloop/last-good.rkt"
         "../../routes/keyboard.rkt"
         "../../routes/keymaps-shared.rkt"
         "../../routes/routes.rkt"
         "../../join/hot-path-shared.rkt"
         "../../join/protocol-shared.rkt"
         "../../bridge/document-shared.rkt"
         "../../bridge/host-shared.rkt")

(provide routes-walk keys-verb)

(define (routes-walk args)
  (define layer (if (null? args) "visual" (car args)))
  (define claims (if (null? args) '() (cdr args)))
  (define keys (if (null? args)
                   (append (list reserved-prefix)
                           (map car (keys-of layer)))
                   (list reserved-prefix)))
  (print-line (format "layer: ~a  program claims: ~a  reserved prefix: ~a"
                       layer
                       (if (null? claims) "none" (string-join claims " "))
                       reserved-prefix))
  (for-each (lambda (answer) (print-line (route-line answer)))
            (route-walk keys claims layer)))

(define (keys-verb args)
  (define layer (if (null? args) "visual" (car args)))
  (define hexes (if (null? args) '() (cdr args)))
  (for-each
   (lambda (hex)
     (define names (key-names (hex->bytes hex)))
     (if (null? names)
         (print-line (format "~a -> no key" hex))
         (for-each
          (lambda (name)
            (define answer (route-of-key name '() layer))
            (print-line (format "~a -> ~a ~a"
                                name
                                (first answer)
                                (if (string=? (second answer) "") "-" (second answer)))))
          names)))
   hexes))
