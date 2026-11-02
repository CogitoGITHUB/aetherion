#lang racket/base
;; One job: the aiutd tool verbs (update, test, docs, trace). Every answer is
;; two empty lines, a banner, the details, the banner again, two empty lines.
;; The banner is drawn by the notation view. Every step is timed, logged to
;; ~/.aiu-timings.log and compared with the run before. Loaded on first use.
;;
;; Usage: aiutd update [--level N]

(require racket/system racket/string racket/list racket/file racket/path "update-table.rkt" "update-screen.rkt" "update-evidence.rkt" "update-drive.rkt")

;; The entry for cli.rkt.
(provide run)

;; compile-files are the files raco make builds in ONE call: one call per file cost 32 s each, five calls 172 s, one call 34 s.
(define compile-files
  (list "editor/entry/cli.rkt" "editor/tui/undo.rkt"
        "editor/tui/multi.rkt" "editor/tui/clip.rkt"
        "editor/entry/update.rkt"))

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

;; parse-times reads the TIME lines of the gate and answers a list of (stage seconds).
(define (parse-times text)
  (for/list ([l (in-list (string-split text "\n"))]
             #:when (regexp-match? #px"^TIME \\S+ [0-9]+$" (string-trim l)))
    (define p (string-split (string-trim l)))
    (list (cadr p) (/ (round (/ (string->number (caddr p)) 100.0)) 10.0))))

;; level-1-stages are the quick gate stages, about 20 s together.
(define level-1-stages "naming,one-way,language-split,comment-lint,notation-check,dashboard-check,secret-check,git-check")

;; level-2-stages add the medium stages, about 60 s more.
(define level-2-stages (string-append level-1-stages ",paren-check,plugin-check,send-check,route-check,explorer-check,security-gate"))

;; stage-args answers the arguments that pick the gate stages of a level; level 3 runs all.
(define (stage-args level)
  (cond [(= level 1) (list "--only" level-1-stages)] [(= level 2) (list "--only" level-2-stages)] [else (list)]))

;; stage-label names the stage set of a level for the report.
(define (stage-label level)
  (cond [(= level 1) "quick stages"] [(= level 2) "quick and medium stages"] [else "all 17 stages"]))

;; parse-stages reads the gate output and answers one list per stage: name, seconds, exit code, output lines.
(define (parse-stages text)
  (define tail-rx #px"^(stages that checked nothing|NOTHING-TO-CHECK above|light gate:)")
  (define blocks
    (let loop ([ls (string-split text "\n")] [cur #f] [acc (list)])
      (cond
        [(null? ls) (reverse (if cur (cons (reverse cur) acc) acc))]
        [(regexp-match? #rx"^--- " (car ls))
         (loop (cdr ls) (list (car ls)) (if cur (cons (reverse cur) acc) acc))]
        [cur (loop (cdr ls) (cons (car ls) cur) acc)]
        [else (loop (cdr ls) cur acc)])))
  (for/list ([b (in-list blocks)])
    (define (field tag)
      (for/or ([l (in-list (cdr b))])
        (define m (regexp-match (pregexp (string-append "^" tag " [^ ]+ ([0-9]+)$")) (string-trim l)))
        (and m (string->number (cadr m)))))
    (define ms (or (field "TIME") 0))
    (define code (or (field "CODE") 1))
    (define body
      (filter (lambda (l)
                (and (not (string=? (string-trim l) ""))
                     (not (regexp-match? #px"^(TIME|CODE) " (string-trim l)))
                     (not (regexp-match? tail-rx l))))
              (cdr b)))
    (list (substring (car b) 4) (/ (round (/ ms 100.0)) 10.0) code body)))

;; gate-run runs the gate with one nu call per stage for levels 1 and 2, a live line before and after each, and answers code and output.
(define (gate-run nu level)
  (define stages (cond [(= level 1) (string-split level-1-stages ",")] [(= level 2) (string-split level-2-stages ",")] [else #f]))
  (cond
    [(not stages)
     (live "gate all stages start")
     (let-values ([(c t) (capture editor-root nu (append (list "gate/check.nu") (stage-args level)))])
       (live (format "gate all stages done code ~a" c))
       (values c t))]
    [else
     (define results
       (for/list ([s (in-list stages)])
         (live (string-append "gate " s " start"))
         (let-values ([(c t) (capture editor-root nu (list "gate/check.nu" "--only" s))])
           (live (format "gate ~a done code ~a" s c))
           (cons c t))))
     (define all-ok
       (andmap (lambda (r) (and (= (car r) 0) (not (regexp-match? #px"(?m:^CODE [^ ]+ [1-9][0-9]*$)" (cdr r))))) results))
     (values (if all-ok 0 1)
             (string-append (apply string-append (map (lambda (r) (string-append (cdr r) "\n")) results))
                            (if all-ok "light gate: green\n" "light gate: red\n")))]))

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
               [raco (begin (live "compile start") (let-values ([(c t) (capture editor-root raco (cons "make" compile-files))]) (live (format "compile done code ~a" c)) (values c t)))]
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

;; do-test runs every test file of the level or below, reports each with its time, answers 0 or 1.
(define (do-test level only repeat)
  (define dir (and editor-root (build-path editor-root "gate" "tests")))
  (define files
    (if (and dir (directory-exists? dir))
        (sort (filter (lambda (p) (regexp-match? #rx"[.]test$" (path->string p)))
                      (directory-list dir #:build? #t))
              string<? #:key path->string)
        (list)))
  (define wanted (filter (lambda (p) (<= (test-level p) level)) files))
  (define t-all (current-inexact-milliseconds))
  (define picked (if only (filter (lambda (p) (regexp-match? (regexp-quote only) (car (regexp-match #rx"[^/]*$" (path->string p))))) wanted) wanted))
  (define results (let loop ([i 0] [acc (list)]) (if (or (>= i repeat) (and (> repeat 1) (ormap (lambda (r) (not (caddr r))) acc))) acc (loop (+ i 1) (append acc (for/list ([p (in-list picked)]) (run-test p)))))))
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
     [(equal? verb "record") (let* ([m (member "record" args)] [w (if m (cdr m) args)]) (if (>= (length w) 2) (do-record w) (begin (emit (list "AIUTD RECORD" "RED") (list "usage: aiutd record NAME KEYS")) 1)))]
     [(equal? verb "test") (do-test (level-of args) (arg-value args "--only") (max 1 (or (string->number (or (arg-value args "--repeat") "1")) 1)))]
     [else
      (emit (list "AIUTD" (string-upcase verb)) (list "not built yet, see plan.md"))
      0])))
