#lang racket/base
;; One job: the aiutd update verb - compile the editor in one call, run the gate, run the tests and report.

(require racket/system racket/string racket/list racket/file racket/path "update-table.rkt" "update-screen.rkt" "update-evidence.rkt" "update-drive.rkt" "update-gate.rkt")

(provide do-update)

;; compile-files are the files raco make builds in ONE call: one call per file cost 32 s each, five calls 172 s, one call 34 s.
(define compile-files
  (list "editor/entry/cli.rkt" "editor/tui/undo/undo.rkt"
        "editor/tui/multi/multi.rkt" "editor/tui/text/clip.rkt"
        "editor/entry/update/update.rkt"))

;; raco-path answers the raco next to the running racket, or the one on the path.
(define (raco-path)
  (define e (find-system-path (quote exec-file)))
  (define exe (if (absolute-path? e) e (find-executable-path e)))
  (define near (and exe (build-path (path-only exe) "raco")))
  (if (and near (file-exists? near)) near (find-executable-path "raco")))

;; stamp-path is the file whose time says when the last good compile ended.
(define stamp-path (build-path (find-system-path (quote home-dir)) ".aiu-build-stamp"))

;; sources-newer? says whether any .rkt file under editor is newer than the stamp, or the stamp is missing.
(define (sources-newer?)
  (define stamp (and (file-exists? stamp-path) (file-or-directory-modify-seconds stamp-path)))
  (or (not stamp)
      (for/or ([p (in-directory (build-path editor-root "editor"))])
        (and (regexp-match? #rx"[.]rkt$" (path->string p))
             (> (file-or-directory-modify-seconds p) stamp)))))

;; touch-stamp! writes the stamp file now.
(define (touch-stamp!)
  (call-with-output-file stamp-path #:exists (quote truncate) (lambda (o) (write-string "ok" o))))

;; real-lines drops empty lines and the harmless registered twice warnings.
(define (real-lines text)
  (filter (lambda (l)
            (and (not (string=? (string-trim l) ""))
                 (not (regexp-match? #rx"registered twice" l))))
          (string-split text "\n")))

;; do-update compiles each file, then runs the gate from level 2, times all of it, and answers 0 or 1.
(define (do-update level)
  (cond
    [(not editor-root)
     (emit (list "AIUTD UPDATE" "RED") (list "the editor folder with gate was not found"))
     1]
    [else
     (unless (getenv "PLTCOMPILEDROOTS")
       (putenv "PLTCOMPILEDROOTS"
               (path->string (build-path (find-system-path (quote home-dir)) "aiu-compiled"))))
     (define t-all (current-inexact-milliseconds))
     (define raco (raco-path))
     (define records (list))
     (define fail-lines (list))
     (define stage-times (list))
     (define ok #t)
     (let ()
       (define t (current-inexact-milliseconds))
       (define stale? (sources-newer?))
       (define-values (code text)
         (cond [(not stale?) (values 0 "")]
               [raco (begin (live "compile start") (let-values ([(c t) (capture editor-root raco (append (list "make" "-j" (number->string ((dynamic-require (quote racket/future) (quote processor-count))))) compile-files))]) (live (format "compile done code ~a" c)) (values c t)))]
               [else (values 1 "raco was not found")]))
       (when (and stale? (= code 0)) (touch-stamp!))
       (set! records (append records (list (list "compile" (secs t) (= code 0)))))
       (unless (= code 0)
         (set! ok #f)
         (set! fail-lines (first-n (real-lines text) 12))))
     (when (and ok (>= level 1))
       (define t1 (current-inexact-milliseconds))
       (define nu (find-executable-path "nu"))
       (define-values (g-code g-text)
         (if nu (gate-run nu level) (values 1 "nu was not found")))
       (define g-lines (real-lines g-text))
       (with-handlers ([void void])
         (display-to-file g-text (build-path (find-system-path (quote home-dir)) ".aiu-last-gate.txt") #:exists (quote truncate)))
       (define green? (regexp-match? #rx"light gate: green" g-text))
       (define bad (filter (lambda (l) (regexp-match? #px"^(COMMENT|FAIL)|light gate: red" l)) g-lines))
       (set! records (append records (list (list "gate" (secs t1) green?))))
       (set! stage-times (parse-stages g-text))
       (unless green?
         (set! ok #f)
         (set! fail-lines (if (null? stage-times) (first-n g-lines 12) (list)))))
     (define total (secs t-all))
     (define test-results (if (and ok (>= level 1)) (run-all-tests level) (list)))
     (when (not (andmap caddr test-results)) (set! ok #f))
     (for ([r (in-list test-results)]) (log-step! level (string-append "test:" (car r)) (cadr r)))
     (define test-block
       (append* (for/list ([r (in-list test-results)])
                  (cons (step-line (string-append "test:" (car r)) (cadr r) (caddr r)) (cadddr r)))))
     (define total2 (secs t-all))
     (define all (append records (list (list "total" total2 ok))))
     (define lines (for/list ([r (in-list all)]) (step-line (car r) (cadr r) (caddr r))))
     (define slowest
       (append*
       (for/list ([t (in-list stage-times)])
         (cons (step-line (string-append "gate:" (car t)) (cadr t) (= (caddr t) 0)) (if (= (caddr t) 0) (list) (map (lambda (l) (string-append "    | " l)) (first-n (cadddr t) 15)))))))
     (for ([r (in-list all)]) (unless (and (equal? (car r) "compile") (< (cadr r) 1)) (log-step! level (car r) (cadr r))))
     (for ([t (in-list stage-times)]) (log-step! level (string-append "gate:" (car t)) (cadr t)))
     (define notes
       (append (list (format "stages                  ~a" (stage-label level)))
               (if (= level 3) (list "timing                  not built yet") (list))))
     (emit (list "AIUTD UPDATE" (format "LEVEL ~a  ~a  ~a s" level (if ok "GREEN" "RED") total2))
           (append (drop-right lines 1) slowest test-block (list (last lines)) notes fail-lines))
     (if ok 0 1)]))
