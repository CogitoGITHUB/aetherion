#lang racket/base
;; One job: the routes and keys verbs of the argv dispatch, each printing what the layers and the screen answer.

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

(provide routes-walk keys-verb)

;; routes-walk runs the routing walk and prints one line per key: which
;; layer saw the key and what it meant there. The keys are the ones given
;; on the command line, or every key the editor binds when none are
;; given, plus the reserved prefix, so the walk always shows the whole
;; shape. The program-claims are the keys the focused program wants; they
;; are given as the words before the layer.
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

;; keys-verb answers what the bytes of a key are and what they mean.
;; The bytes are given as hex, because a key may be any byte at all: the
;; walk answers the name of each key, the layer that saw it, and the
;; command it runs there. The layer may be named after the bytes, and it
;; is the visual layer without one.
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
