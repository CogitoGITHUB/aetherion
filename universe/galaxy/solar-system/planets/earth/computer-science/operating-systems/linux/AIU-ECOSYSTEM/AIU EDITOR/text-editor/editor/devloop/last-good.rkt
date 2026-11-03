#lang racket/base

(require racket/file
         racket/string
         "../machine/directories.rkt")

(define last-good-file
  (build-path (state-dir) "last-good"))

(define (last-good)
  (if (file-exists? last-good-file)
      (let ([text (string-trim (file->string last-good-file))])
        (if (string=? text "") #f text))
      #f))

(define (keep-last-good path)
  (ensure-dir (state-dir))
  (call-with-output-file last-good-file
    (lambda (port) (display path port))
    #:exists 'truncate)
  path)

(define (good-answers? answers expected)
  (and (pair? answers) (equal? (car answers) expected)))

(provide last-good-file
         last-good
         keep-last-good
         good-answers?)
