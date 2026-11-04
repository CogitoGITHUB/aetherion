#lang racket/base

(require racket/path racket/port
         "../machine/directories-shared.rkt"
         "../commands/commands-shared.rkt"
         "../tui/float/explorer.rkt"
         "live/live.rkt")

(define here
  (let-values ([(base name dir?)
                (split-path (variable-reference->module-source (#%variable-reference)))])
    base))

(define (stub-send session words)
  (dynamic-require (simplify-path (build-path here (quote up) "send" "send.rkt")) #f)
  (define real (hash-ref commands "send" #f))
  (if (and real (not (eq? real stub-send)))
      (real session words)
      (cons #t "the send could not be loaded")))

(hash-set! commands "send" stub-send)

(define (file-session path)
  (define file (path->complete-path path))
  (define journal (journal-path-for file))
  (ensure-dir (build-path (state-dir) "journal"))
  (live-session file journal))


(define (lean-edit args)
  (if (null? args)
      (display "aiutd needs a file: aiutd FILE\n")
      (file-session (car args))))

(provide lean-edit)
