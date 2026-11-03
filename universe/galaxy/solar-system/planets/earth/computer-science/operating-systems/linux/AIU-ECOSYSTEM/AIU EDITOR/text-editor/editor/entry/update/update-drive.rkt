#lang racket/base
;; One job: the door of the drive modules: running every test of a level, and the one provide that gives every part to the rest of the editor.
(require racket/system racket/string racket/list racket/file racket/path "update-table.rkt" "update-screen.rkt" "update-evidence.rkt" "update-drive-live.rkt" "update-drive-pty.rkt" "update-drive-why.rkt" "update-drive-run.rkt" "update-drive-record.rkt" "update-drive-docs.rkt" "update-module.rkt")

;; run-all-tests runs every test file of the level or below and answers the list of results.
(define (run-all-tests level)
  (define dir (and editor-root (build-path editor-root "gate" "tests")))
  (define files
    (if (and dir (directory-exists? dir))
        (sort (filter (lambda (p) (regexp-match? #rx"[.]test$" (path->string p)))
                      (find-files (lambda (q) (regexp-match? #rx"[.]test$" (path->string q))) dir))
              string<? #:key path->string)
        (list)))
  (define wanted (filter (lambda (p) (<= (test-level p) level)) files))
  (for/list ([p (in-list wanted)]) (live (format "test ~a start" (file-name-from-path p))) (let ([r (run-test p)]) (live (format "test ~a done" (car r))) r)))

;; arg-value answers the word after a flag in the arguments, or #f when the flag is missing.
(define (arg-value args flag)
  (define m (member flag args))
  (and m (pair? (cdr m)) (cadr m)))


(provide (all-from-out "update-drive-live.rkt") (all-from-out "update-drive-pty.rkt") (all-from-out "update-drive-why.rkt") (all-from-out "update-drive-run.rkt") (all-from-out "update-drive-record.rkt") (all-from-out "update-drive-docs.rkt") (all-from-out "update-module.rkt") run-all-tests arg-value)
