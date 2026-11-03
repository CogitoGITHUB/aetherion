#lang racket/base

(require racket/file
         racket/string
         "directories.rkt")

(define stop-file
  (build-path (state-dir) "stop"))

(define (stopped?)
  (file-exists? stop-file))

(define (throw-switch)
  (ensure-dir (state-dir))
  (call-with-output-file stop-file
    (lambda (port) (display "the stop switch is thrown\n" port))
    #:exists 'truncate)
  #t)

(define (clear-switch)
  (when (file-exists? stop-file)
    (delete-file stop-file))
  #f)

(provide stop-file
         stopped?
         throw-switch
         clear-switch)
