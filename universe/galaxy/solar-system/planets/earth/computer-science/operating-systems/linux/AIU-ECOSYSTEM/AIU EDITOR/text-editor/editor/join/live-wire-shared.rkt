#lang racket/base

(require racket/file
         racket/path
         racket/system
         "protocol-shared.rkt"
         "../machine/directories-shared.rkt")

(struct wire (to-child from-child dir child) #:transparent)

(define current-wire (make-parameter #f))

(define (make-fifos! in-path out-path)
  (and (file-exists? "/usr/bin/mkfifo")
       (system* "/usr/bin/mkfifo" in-path out-path)))

(define (wire-start)
  (define dir (make-temporary-directory "aiu-wire-live-~a"))
  (define in-path (path->string (build-path dir "in.fifo")))
  (define out-path (path->string (build-path dir "out.fifo")))
  (cond
    [(not (make-fifos! in-path out-path))
     (delete-directory/files dir)
     #f]
    [else
     (define child
       (with-handlers ([exn:fail? (lambda (why) #f)])
         (let-values ([(proc _out _in _voice)
                       (subprocess #f #f #f (path->string (hot-path-bin))
                                   "serve" in-path out-path)])
           proc)))
     (cond
       [(not child)
        (delete-directory/files dir)
        #f]
       [else
        (define-values (_unused-write to-child)
          (open-input-output-file in-path #:exists 'update))
        (define-values (from-child _unused-read)
          (open-input-output-file out-path #:exists 'update))
        (define live (wire to-child from-child dir child))
        (current-wire live)
        live])]))

(define (wire-ask live request)
  (define answer
    (with-handlers ([exn:fail? (lambda (why) #f)])
      (write-message (wire-to-child live) request)
      (read-response (wire-from-child live))))
  (cond
    [answer answer]
    [else
     (wire-stop)
     (response #f (hasheq 'kind "err-wire-lost"
                          'what "the hot path stopped answering on the live wire"
                          'what_to_do "start the editor again; the file and the journal are untouched"))]))

(define (wire-stop)
  (define live (current-wire))
  (current-wire #f)
  (when live
    (with-handlers ([exn:fail? void])
      (close-output-port (wire-to-child live))
      (close-input-port (wire-from-child live)))
    (with-handlers ([exn:fail? void])
      (subprocess-kill (wire-child live) #t)
      (subprocess-wait (wire-child live)))
    (with-handlers ([exn:fail? void])
      (delete-directory/files (wire-dir live))))
  (void))

(provide current-wire
         wire-start
         wire-ask
         wire-stop)
