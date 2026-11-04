#lang racket/base
;; One job: the test-beside-module check, every Racket file under editor has a .test beside it or a skip note in gate/skipped.txt.
(require racket/file racket/list racket/string racket/path racket/runtime-path)

(define-runtime-path here "..")

(define root (simplify-path (path->complete-path here)))

;; skipped-files answers the editor paths that gate/skipped.txt names on a line that says skipped.
(define (skipped-files)
  (define plan (build-path root "gate" "skipped.txt"))
  (if (file-exists? plan)
      (append* (for/list ([l (in-list (file->lines plan))] #:when (string-contains? l "/"))
                 (regexp-match* #px"(?:[.][.]/[.][.]/AIU NOTATION/notation|editor)/[^\n]+[.]rkt" l)))
      (list)))

(define (rkt-files)
  (for/list ([p (in-list (append (find-files (lambda (q) (regexp-match? #rx"[.]rkt$" (path->string q))) (build-path root "editor")) (find-files (lambda (q) (regexp-match? #rx"[.]rkt$" (path->string q))) (build-path root ".." ".." "AIU NOTATION" "notation"))))]
             #:unless (regexp-match? #rx"/compiled/" (path->string p)))
    (path->string (find-relative-path (simplify-path root) (simplify-path p)))))

;; missing answers the Racket files that have no test beside them and no skip note.
(define (missing)
  (define skipped (skipped-files))
  (for/list ([f (in-list (rkt-files))]
             #:unless (file-exists? (path-replace-extension (build-path root f) #".test"))
             #:unless (member f skipped))
    f))

;; gone holds the editor files that have no test beside them and no skip note.
(define gone (missing))
(cond
  [(null? gone) (printf "PASS test-check: every editor file has a test beside it or a skip note\n")]
  [else
   (printf "FAIL test-check: ~a files have no test beside them and no skip note in gate/skipped.txt\n" (length gone))
   (for ([f (in-list gone)]) (printf "  ~a: record one with aiutd record-module NAME ~a EXPRESSION, or add it to a line of gate/skipped.txt\n" f f))
   (exit 1)])
