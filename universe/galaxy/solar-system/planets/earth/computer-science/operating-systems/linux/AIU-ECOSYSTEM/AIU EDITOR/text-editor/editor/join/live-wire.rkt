#lang racket/base
;; One job: the live wire — the hot path child kept open for one session.
;;
;; transport.rkt starts a child for every question, and that is right for a
;; scripted run and for a verb that asks one thing. A live session asks a
;; question for every key, so a child per key would be a program start per
;; key: the editor would feel the start of the hot path under every letter.
;; This wire starts the child ONCE, in its `serve` mode, and keeps it: the
;; child reads one request line and answers one line for as long as the
;; session runs.
;;
;; The streams are named pipes, not pipes: this Racket build hands a child
;; a file stream or nothing, and a named pipe is a file stream. They are
;; opened read-write on this side, which never blocks — a reader that
;; waited for a child that died would hang the editor at the first key —
;; and the child still sees the end of its input when this process goes,
;; so it exits with the editor, even when the editor is killed.
;;
;; A wire that stops answering is dropped and the next question goes over
;; the one-shot transport: the editor stays correct, only slower.

(require racket/file
         racket/path
         racket/system
         "protocol.rkt"
         "../machine/directories.rkt")

;; wire is the open wire: the port that carries a request to the child, the
;; port that carries the answer back, the directory that holds the two
;; pipes, and the child itself.
(struct wire (to-child from-child dir child) #:transparent)

;; current-wire holds the open wire, or nothing when the session has none
;; and every question goes over the one-shot transport.
(define current-wire (make-parameter #f))

;; make-fifos! names the two pipes, and answers whether it could. The call
;; is the system's own mkfifo: a named pipe cannot be made from Racket
;; alone, and a build without the program falls back to the one-shot wire.
(define (make-fifos! in-path out-path)
  (and (file-exists? "/usr/bin/mkfifo")
       (system* "/usr/bin/mkfifo" in-path out-path)))

;; wire-start starts the hot path in its serve mode over two named pipes
;; and answers the wire, or nothing when the machine cannot make one or the
;; hot path is not built. The caller that gets nothing keeps working: the
;; questions go over the one-shot transport.
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
        ;; Both ends are opened read-write, so neither open waits for the
        ;; other side: the child's own opens unblock at once, and a child
        ;; that died before opening cannot hang the editor here.
        (define-values (_unused-write to-child)
          (open-input-output-file in-path #:exists 'update))
        (define-values (from-child _unused-read)
          (open-input-output-file out-path #:exists 'update))
        (define live (wire to-child from-child dir child))
        (current-wire live)
        live])]))

;; wire-ask sends one request over the live wire and answers the response.
;; A wire that cannot carry the question is dropped, and the refusal names
;; what happened; the next question goes over the one-shot transport.
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

;; wire-stop closes the wire and takes the child with it. The child holds no
;; state of its own — the text lives in the file and the journal — so it is
;; killed rather than asked, and the two pipes are taken away.
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

;; The live wire, for the seam above it.
(provide current-wire
         wire-start
         wire-ask
         wire-stop)
