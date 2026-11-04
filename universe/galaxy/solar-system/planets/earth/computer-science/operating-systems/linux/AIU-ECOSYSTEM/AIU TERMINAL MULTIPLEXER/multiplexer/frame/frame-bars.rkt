#lang racket/base
(require racket/runtime-path (for-syntax racket/base))
(provide bars-link-open bars-link-ask! bars-link-close!)

(define-runtime-path server-path "../tui/bar/bar-lines-server-shared.rkt")

(struct bars-link (process in out lock))

(define (racket-executable)
  (define exec (find-system-path (quote exec-file)))
  (or (find-executable-path exec) exec))

(define (bars-link-open)
  (define-values (process in out err)
    (subprocess #f #f (quote stdout) (racket-executable) (path->string server-path)))
  (bars-link process in out (make-semaphore 1)))

(define (bars-link-ask! link layer short width pending pinned)
  (call-with-semaphore
   (bars-link-lock link)
   (lambda ()
     (write-string (format "~a\t~a\t~a\t~a\t~a\n" layer short width pending pinned) (bars-link-out link))
     (flush-output (bars-link-out link))
     (let loop ([rows (list)])
       (define line (read-line (bars-link-in link)))
       (if (or (eof-object? line) (string=? line ""))
           (reverse rows)
           (loop (cons line rows)))))))

(define (bars-link-close! link)
  (subprocess-kill (bars-link-process link) #t))
