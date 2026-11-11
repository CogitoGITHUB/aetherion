#lang racket/base
(require ffi/unsafe ffi/unsafe/port)
(provide (struct-out pane-link) pane-open pane-set-size! pane-read-chunk pane-close!)

(struct pane-link (master-in master-out master-fd process))

(define terminal-library (ffi-lib "libutil" (list "1" #f)))
(define c-library (ffi-lib #f))
(define open-pseudo-terminal
  (get-ffi-obj "openpty" terminal-library (_fun _pointer _pointer _pointer _pointer _pointer -> _int)))
(define window-size-ioctl
  (get-ffi-obj "ioctl" c-library (_fun #:varargs-after 2 _int _ulong _pointer -> _int)))
(define duplicate-descriptor (get-ffi-obj "dup" c-library (_fun _int -> _int)))
(define close-descriptor (get-ffi-obj "close" c-library (_fun _int -> _int)))
(define set-window-size-request #x5414)

(define (set-descriptor-size! descriptor columns rows)
  (define size (malloc 8 (quote raw)))
  (ptr-set! size _ushort 0 rows)
  (ptr-set! size _ushort 1 columns)
  (ptr-set! size _ushort 2 0)
  (ptr-set! size _ushort 3 0)
  (window-size-ioctl descriptor set-window-size-request size)
  (free size))

(define send-signal (get-ffi-obj "kill" c-library (_fun _int _int -> _int)))
(define window-change-signal 28)

(define (pane-set-size! link columns rows)
  (set-descriptor-size! (pane-link-master-fd link) columns rows)
  (define pid (subprocess-pid (pane-link-process link)))
  (send-signal (- pid) window-change-signal)
  (send-signal pid window-change-signal))

(define (pane-open program arguments columns rows)
  (define descriptors (malloc 8 (quote raw)))
  (unless (zero? (open-pseudo-terminal descriptors (ptr-add descriptors 4) #f #f #f))
    (error "openpty failed"))
  (define master (ptr-ref descriptors _int 0))
  (define slave (ptr-ref descriptors _int 1))
  (free descriptors)
  (set-descriptor-size! master columns rows)
  (define slave-input
    (unsafe-file-descriptor->port (duplicate-descriptor slave) (quote pane-slave-input) (list (quote read))))
  (define slave-output
    (unsafe-file-descriptor->port (duplicate-descriptor slave) (quote pane-slave-output) (list (quote write))))
  (close-descriptor slave)
  (define launcher (find-executable-path "setsid"))
  (unless launcher (error "setsid not found"))
  (define environment (environment-variables-copy (current-environment-variables)))
  (environment-variables-set! environment #"TERM" #"xterm-256color")
  (define-values (process out in err)
    (parameterize ([current-environment-variables environment])
      (apply subprocess slave-output slave-input (quote stdout) launcher "-c" program arguments)))
  (close-input-port slave-input)
  (close-output-port slave-output)
  (define-values (master-in master-out)
    (unsafe-file-descriptor->port master (quote pane-master) (list (quote read) (quote write))))
  (file-stream-buffer-mode master-out (quote none))
  (pane-link master-in master-out master process))

(define (pane-read-chunk link)
  (define buffer (make-bytes 4096))
  (define amount
    (with-handlers ([exn:fail? (lambda (why) eof)])
      (read-bytes-avail! buffer (pane-link-master-in link))))
  (if (eof-object? amount) eof (subbytes buffer 0 amount)))

(define (pane-close! link)
  (subprocess-kill (pane-link-process link) #t))
