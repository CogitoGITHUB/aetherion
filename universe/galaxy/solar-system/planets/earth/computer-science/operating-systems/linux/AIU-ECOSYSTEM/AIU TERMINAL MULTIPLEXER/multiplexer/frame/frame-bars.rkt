#lang racket/base
(require racket/runtime-path racket/string (for-syntax racket/base))
(provide bars-link-open bars-link-ask! bars-link-close! shell-cwd-of)

(define-runtime-path server-path "../tui/bar/bar-lines-server-shared.rkt")

(struct bars-link (process in out lock))

(define (process-parent-of id)
  (with-handlers ([void (lambda (why) #f)])
    (define line (call-with-input-file (build-path "/proc" id "stat") read-line))
    (define found (regexp-match #rx"^[0-9]+ \\(.*\\) [A-Za-z] ([0-9]+)" line))
    (and found (string->number (cadr found)))))

(define (shell-cwd-of pid)
  (define children (make-hash))
  (for ([entry (in-list (directory-list "/proc"))])
    (define id (path->string entry))
    (when (regexp-match? #rx"^[0-9]+$" id)
      (define parent (process-parent-of id))
      (when parent
        (hash-update! children parent (lambda (known) (cons (string->number id) known)) null))))
  (define deepest
    (let loop ([at pid])
      (define kids (hash-ref children at null))
      (if (null? kids) at (loop (apply max kids)))))
  (with-handlers ([void (lambda (why) "")])
    (path->string (resolve-path (build-path "/proc" (number->string deepest) "cwd")))))

(define (racket-executable)
  (define exec (path->string (build-path (find-system-path (quote home-dir)) "opt" "racket-full" "bin" "racket")))
  exec)

(define (bars-link-open)
  (putenv "LC_ALL" "C.utf8")
  (define-values (process in out err)
    (subprocess #f #f (quote stdout) (racket-executable) server-path))
  (bars-link process in out (make-semaphore 1)))

(define (bars-link-ask! link layer short width pending pinned buffer-names buffer-current cwd)
  (call-with-semaphore
   (bars-link-lock link)
   (lambda ()
     (write-string (format "~a\t~a\t~a\t~a\t~a\t~a\t~a\t~a\n" layer short width pending pinned (string-join buffer-names "\u001f") buffer-current cwd) (bars-link-out link))
     (flush-output (bars-link-out link))
     (let loop ([rows (list)])
       (define line (read-line (bars-link-in link)))
       (if (or (eof-object? line) (string=? line ""))
           (reverse rows)
           (loop (cons line rows)))))))

(define (bars-link-close! link)
  (subprocess-kill (bars-link-process link) #t))
