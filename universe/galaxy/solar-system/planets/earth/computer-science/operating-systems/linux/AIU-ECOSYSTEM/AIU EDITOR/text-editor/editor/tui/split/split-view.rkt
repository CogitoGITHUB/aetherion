#lang racket/base

(require racket/list racket/string "../../notation/host.rkt" (only-in "../../machine/directories.rkt" journal-path-for))

(provide split-view-lines)

(define split-view-cache (make-hash))

(define (split-view-stamp path)
  (with-handlers ([(lambda (e) #t) (lambda (e) 0)])
    (file-or-directory-modify-seconds path)))

(define (split-view-strip text)
  (regexp-replace* #px"\u001b\\[[0-9;?]*[A-Za-z]" (string-replace text "\t" "    ") ""))

(define (split-view-text file width)
  (define path (string->path file))
  (cond
    [(regexp-match? #rx"[.]aiu$" file) (view-of path (journal-path-for path) (max 1 width))]
    [else
     (with-handlers ([(lambda (e) #t) (lambda (e) "")])
       (call-with-input-file path
         (lambda (in) (let ([text (read-string 20000 in)]) (if (eof-object? text) "" text)))))]))

(define (split-view-lines file width height)
  (define path (string->path file))
  (define stamp (list (split-view-stamp path) (split-view-stamp (journal-path-for path))))
  (define key (list file width))
  (define kept (hash-ref split-view-cache key #f))
  (define lines
    (if (and kept (equal? (car kept) stamp))
        (cdr kept)
        (let ([fresh (string-split (split-view-strip (split-view-text file width)) "\n" #:trim? #f)])
          (hash-set! split-view-cache key (cons stamp fresh))
          fresh)))
  (if (> (length lines) height) (take lines height) lines))
