#lang racket/base
(require racket/string racket/list racket/file "update-table.rkt" "update-screen.rkt")

(define (module-answer modpath expr)
  (define-values (code out)
    (capture editor-root (or (find-executable-path "racket") "racket")
             (list "-l" "racket/base" "-e" (format "(require (file ~s))" modpath) "-e" "(display \"RESULT:\")" "-e" (format "(write ~a)" expr))))
  (define m (regexp-match #px"(?s:RESULT:(.*))$" out))
  (values (and (= code 0) m (string-trim (cadr m))) out))

(define (indent-cut l) (string-append "    " (if (> (string-length l) 100) (substring l 0 100) l)))

(define (run-module-test path)
  (define lines (test-lines path))
  (define (one k) (let ([v (line-values lines k)]) (if (pair? v) (car v) "")))
  (define name (let ([v (line-values lines "test")]) (if (pair? v) (car v) "unnamed")))
  (define t0 (current-inexact-milliseconds))
  (define-values (got out) (module-answer (one "module") (one "call")))
  (define seconds (secs t0))
  (define wanted (for/list ([l (in-list lines)] #:when (regexp-match? #px"^expect result equals " l)) (substring l (string-length "expect result equals "))))
  (define limit (let ([m (for/or ([l (in-list lines)]) (regexp-match #px"^expect seconds-under ([0-9.]+)$" l))]) (and m (string->number (cadr m)))))
  (define equal-ok? (and got (pair? wanted) (equal? got (car wanted))))
  (define time-ok? (or (not limit) (< seconds limit)))
  (define ok? (and equal-ok? time-ok?))
  (list name seconds ok?
        (append (list (string-append "    call " (one "call")))
                (cond [ok? (list)]
                      [got (list (string-append "    expected " (if (pair? wanted) (car wanted) "nothing")) (string-append "    got      " got))]
                      [else (cons "    the call did not answer:" (map indent-cut (last-n (string-split out "\n") 8)))])
                (if time-ok? (list) (list (format "    took ~a s, the limit is ~a s" seconds limit))))))

(define (do-record-module name modpath expr)
  (define tpath (build-path editor-root (regexp-replace #rx"[.]rkt$" modpath ".test")))
  (define (red . ls) (emit (list "AIUTD RECORD-MODULE" "RED") ls) 1)
  (cond
    [(not (regexp-match? #px"^[a-z0-9-]+$" name)) (red "the name holds only lower case letters, digits and minus signs")]
    [(file-exists? tpath) (red (format "gate/tests/mod-~a.test exists already; a recorded test is never overwritten" name))]
    [(not (file-exists? (build-path editor-root modpath))) (red (format "no such module: ~a" modpath))]
    [else
     (define-values (a out-a) (module-answer modpath expr))
     (define-values (b out-b) (module-answer modpath expr))
     (cond
       [(not a) (apply red "the call did not answer:" (map indent-cut (last-n (string-split out-a "\n") 8)))]
       [(not (equal? a b)) (red "the two runs answered differently, so the call is not a test:" (indent-cut a) (indent-cut (or b "")))]
       [(regexp-match? #rx"^#<|\n" a) (red "the answer cannot be written as a stable line:" (indent-cut a))]
       [else
        (call-with-output-file tpath #:exists (quote truncate)
          (lambda (o) (write-string (string-append "test mod-" name "\nlevel 2\nmodule " modpath "\ncall " expr "\nexpect result equals " a "\nexpect seconds-under 20\n") o)))
        (define r (run-module-test tpath))
        (cond [(caddr r)
               (emit (list "AIUTD RECORD-MODULE" "GREEN") (list (string-append "    wrote gate/tests/mod-" name ".test") (string-append "    answer " (indent-cut a))))
               0]
              [else (delete-file tpath) (apply red "the new test did not pass, so it was not kept:" (cadddr r))])])]))

(provide run-module-test do-record-module)
