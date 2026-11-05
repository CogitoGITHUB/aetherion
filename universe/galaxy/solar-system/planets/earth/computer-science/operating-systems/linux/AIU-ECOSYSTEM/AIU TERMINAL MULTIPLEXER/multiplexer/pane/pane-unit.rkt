#lang racket/base
(require "pane-pty.rkt" "pane-grid.rkt")
(provide (struct-out pane-unit) pane-unit-open pane-unit-close!)

(struct pane-unit (id grid link scroll))

(define (pane-unit-open id columns rows directory)
  (define grid (make-pane-grid columns rows))
  (define shell (path->string (or (find-executable-path "nu") (error "nu not found"))))
  (define link
    (parameterize ([current-directory (if (and (string? directory) (> (string-length directory) 0) (directory-exists? directory)) directory (current-directory))])
      (pane-open shell (list) columns rows)))
  (set-pane-grid-reply!
   grid
   (lambda (answer)
     (write-bytes answer (pane-link-master-out link))
     (flush-output (pane-link-master-out link))))
  (pane-unit id grid link (box 0)))

(define (pane-unit-close! unit)
  (pane-close! (pane-unit-link unit)))
