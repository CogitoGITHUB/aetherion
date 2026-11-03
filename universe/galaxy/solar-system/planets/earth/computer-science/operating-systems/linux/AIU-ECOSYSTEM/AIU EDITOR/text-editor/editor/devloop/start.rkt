#lang racket/base

(require racket/file
         racket/list
         racket/string
         "../machine/directories.rkt"
         "../narration/print-console.rkt")

(define started-at (current-inexact-milliseconds))

(define (start-ms)
  (inexact->exact (round (- (current-inexact-milliseconds) started-at))))

(define (mode)
  (let ([asked (getenv "AIU_EDITOR_MODE")])
    (if (and asked (string=? asked "baked")) "baked" "work")))

(define baked-file
  (build-path (state-dir) "baked" "keymaps.rkt"))

(define (baked-tables)
  (and (file-exists? baked-file)
       (with-handlers ([exn:fail? (lambda (why) #f)])
         (dynamic-require (make-resolved-module-path baked-file) 'baked-tables))))

(define (config-source)
  (if (string=? (mode) "baked")
      (path->string baked-file)
      "the source tree"))

(define (print-start)
  (print-line (format "started in ~a ms, ~a mode, the config from ~a"
                       (start-ms)
                       (mode)
                       (config-source))))

(provide started-at
         start-ms
         mode
         baked-file
         baked-tables
         config-source
         print-start)
