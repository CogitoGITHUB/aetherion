#lang racket/base
(require racket/system racket/string racket/list racket/file racket/path "update-table.rkt" "update-screen.rkt" "update-evidence.rkt" "update-drive-live.rkt" "update-drive-pty.rkt" "update-drive-why.rkt" "update-drive-run.rkt" "update-drive-record.rkt" "update-drive-docs.rkt" "update-module.rkt")

(define (run-all-tests level)
  (define dir (and editor-root (build-path editor-root "gate" "tests")))
  (define files
    (if (and dir (directory-exists? dir))
        (sort (filter (lambda (p) (regexp-match? #rx"[.]test$" (path->string p)))
                      (append (find-files (lambda (q) (regexp-match? #rx"[.]test$" (path->string q))) dir) (find-files (lambda (q) (regexp-match? #rx"[.]test$" (path->string q))) (build-path editor-root "editor"))))
              string<? #:key path->string)
        (list)))
  (define only (getenv "AIU_ONLY"))
  (define wanted (filter (lambda (p) (and (<= (test-level p) level) (or (not only) (regexp-match? (regexp-quote only) (path->string p))))) files))
  (run-tests-parallel wanted))

(define (arg-value args flag)
  (define m (member flag args))
  (and m (pair? (cdr m)) (cadr m)))


(provide (all-from-out "update-drive-live.rkt") (all-from-out "update-drive-pty.rkt") (all-from-out "update-drive-why.rkt") (all-from-out "update-drive-run.rkt") (all-from-out "update-drive-record.rkt") (all-from-out "update-drive-docs.rkt") (all-from-out "update-module.rkt") run-all-tests arg-value)
