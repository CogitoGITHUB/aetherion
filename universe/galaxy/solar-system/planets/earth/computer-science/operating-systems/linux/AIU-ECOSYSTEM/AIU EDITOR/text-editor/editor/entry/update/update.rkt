#lang racket/base
;; One job: the aiutd tool verbs (update, test, docs, trace). Every answer is
;; two empty lines, a banner, the details, the banner again, two empty lines.
;; The banner is drawn by the notation view. Every step is timed, logged to
;; ~/.aiu-timings.log and compared with the run before. Loaded on first use.
;;
;; Usage: aiutd update [--level N]

(require racket/system racket/string racket/list racket/file racket/path "update-table.rkt" "update-screen.rkt" "update-evidence.rkt" "update-drive.rkt" "update-build.rkt")

;; The entry for cli.rkt.
(provide run)

;; do-test runs every test file of the level or below, reports each with its time, answers 0 or 1.
(define (do-test level only repeat)
  (define dir (and editor-root (build-path editor-root "gate" "tests")))
  (define files
    (if (and dir (directory-exists? dir))
        (sort (filter (lambda (p) (regexp-match? #rx"[.]test$" (path->string p)))
                      (append (find-files (lambda (q) (regexp-match? #rx"[.]test$" (path->string q))) dir) (find-files (lambda (q) (regexp-match? #rx"[.]test$" (path->string q))) (build-path editor-root "editor"))))
              string<? #:key path->string)
        (list)))
  (define wanted (filter (lambda (p) (<= (test-level p) level)) files))
  (define t-all (current-inexact-milliseconds))
  (define picked (if only (filter (lambda (p) (regexp-match? (regexp-quote only) (car (regexp-match #rx"[^/]*$" (path->string p))))) wanted) wanted))
  (define results (let loop ([i 0] [acc (list)]) (if (or (>= i repeat) (and (> repeat 1) (ormap (lambda (r) (not (caddr r))) acc))) acc (loop (+ i 1) (append acc (run-tests-parallel picked))))))
  (define total (secs t-all))
  (define ok (and (pair? results) (andmap caddr results)))
  (for ([r (in-list results)]) (log-step! level (string-append "test:" (car r)) (cadr r)))
  (log-step! level "test-total" total)
  (emit (list "AIUTD TEST" (format "LEVEL ~a  ~a  ~a s" level (if ok "GREEN" "RED") total))
        (if (null? results)
            (list "no test files at this level in gate/tests")
            (append*
             (for/list ([r (in-list results)])
               (cons (step-line (string-append "test:" (car r)) (cadr r) (caddr r)) (cadddr r))))))
  (printf "runs ~a  failed ~a\n" (length results) (length (filter (lambda (r) (not (caddr r))) results)))
  (if ok 0 1))

;; run answers the verb: update and test work, the other tool verbs say they are not built yet.
(define (run args)
  (define verb (car args))
  (exit
   (cond
     [(equal? verb "update") (do-update (level-of args))]
     [(equal? verb "docs") (do-docs)]
       [(equal? verb "record-module") (let* ([m (member "record-module" args)] [w (if m (cdr m) args)]) (if (>= (length w) 3) (do-record-module (car w) (cadr w) (string-join (cddr w) " ")) (begin (emit (list "AIUTD RECORD-MODULE" "RED") (list "usage: aiutd record-module NAME MODULE-PATH EXPRESSION")) 1)))]
     [(equal? verb "record") (let* ([m (member "record" args)] [w (if m (cdr m) args)]) (if (>= (length w) 2) (do-record w) (begin (emit (list "AIUTD RECORD" "RED") (list "usage: aiutd record NAME KEYS")) 1)))]
     [(equal? verb "test") (do-test (level-of args) (arg-value args "--only") (max 1 (or (string->number (or (arg-value args "--repeat") "1")) 1)))]
     [else
      (emit (list "AIUTD" (string-upcase verb)) (list "not built yet, see plan.md"))
      0])))
