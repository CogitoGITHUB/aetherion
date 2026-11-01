#lang racket/base
;; One job: the aiutd tool verbs (update, test, docs, trace). Every answer is
;; two empty lines, a banner, the details, the banner again, two empty lines.
;; The banner is drawn by the notation view. Every step is timed, logged to
;; ~/.aiu-timings.log and compared with the run before. Loaded on first use.
;;
;; Usage: aiutd update [--level N]

(require racket/system racket/string racket/list racket/file racket/path)

;; The entry for cli.rkt.
(provide run)

;; here-dir is the folder that holds this file.
(define here-dir
  (let ([src (variable-reference->module-source (#%variable-reference))])
    (if (path? src) (path-only src) (current-directory))))

;; find-up walks from a folder toward the root and answers the first folder
;; where the test holds, or false after eight steps.
(define (find-up start test)
  (let loop ([d start] [n 0])
    (cond [(test d) d]
          [(> n 8) #f]
          [else (loop (simplify-path (build-path d (quote up))) (add1 n))])))

;; editor-root is the text-editor folder, the one that holds gate.
(define editor-root
  (find-up here-dir (lambda (d) (directory-exists? (build-path d "gate")))))

;; notation-bin answers the notation program as a string, or false.
(define (notation-bin)
  (define named (getenv "AIU_NOTATION_BIN"))
  (define tail (list "AIU NOTATION" "notation system" "notation" "target" "debug" "notation"))
  (cond
    [(and named (not (string=? named "")) (file-exists? named)) named]
    [else
     (define d (find-up here-dir (lambda (d) (file-exists? (apply build-path d tail)))))
     (and d (path->string (apply build-path d tail)))]))

;; capture runs a program in a folder and answers its exit code and all its output.
(define (capture dir exe args)
  (define out (open-output-string))
  (putenv "PWD" (regexp-replace #rx"(.)/+$" (path->string (path->complete-path dir)) "\\1"))
  (define code
    (parameterize ([current-output-port out]
                   [current-error-port out]
                   [current-directory dir]
                   [current-input-port (open-input-string "")])
      (apply system*/exit-code (find-executable-path "sh") "-c" "cd \"$1\" && shift && exec \"$@\"" "sh" (path->string (path->complete-path dir)) (if (path? exe) (path->string exe) exe) args)))
  (values code (get-output-string out)))

;; width-cache keeps the terminal width after the first question.
(define width-cache #f)

;; term-width answers the terminal width, at most 70, or 56 when it is unknown.
(define (term-width)
  (unless width-cache
    (define sh (find-executable-path "sh"))
    (define-values (code text)
      (if sh (capture (current-directory) sh (list "-c" "stty size < /dev/tty")) (values 1 "")))
    (define parts (string-split (string-trim text)))
    (define n (and (= code 0) (= (length parts) 2) (string->number (cadr parts))))
    (set! width-cache (if (and n (> n 20)) (min n 70) 56)))
  width-cache)

;; banner-text draws the lines as a title block with the notation view, or as
;; plain lines when the notation program is missing or refuses.
(define (banner-text lines)
  (define nb (notation-bin))
  (define plain (string-append (string-join lines "\n") "\n"))
  (cond
    [(not nb) plain]
    [else
     (define tmp (make-temporary-file "aiutd-banner~a.aiu"))
     (call-with-output-file tmp #:exists (quote truncate)
       (lambda (o)
         (write-string (string-append "title start\n" (string-join lines "\n") "\ntitle end\n") o)))
     (define-values (code text)
       (capture (current-directory) nb
                (list "view" (path->string tmp) "--width" (number->string (term-width)))))
     (delete-file tmp)
     (if (and (= code 0) (not (string=? (string-trim text) ""))) text plain)]))

;; wrap-line cuts a line into pieces of at most w characters.
(define (wrap-line s w)
  (if (<= (string-length s) w)
      (list s)
      (cons (substring s 0 w) (wrap-line (substring s w) w))))

;; emit prints two empty lines, the banner, the details, the banner again, two empty lines.
(define (emit head details)
  (newline)
  (newline)
  (write-string (banner-text head))
  (newline)
  (for ([d (in-list details)])
    (for ([l (in-list (wrap-line d (term-width)))])
      (write-string l)
      (newline)))
  (newline)
  (write-string (banner-text head))
  (newline)
  (newline))

;; first-n keeps at most n items from the start of a list.
(define (first-n l n) (if (> (length l) n) (take l n) l))

;; last-n keeps at most n items from the end of a list.
(define (last-n l n) (if (> (length l) n) (take-right l n) l))

;; level-of reads --level N from the arguments; the default is 2.
(define (level-of args)
  (define m (member "--level" args))
  (define n (and m (pair? (cdr m)) (string->number (cadr m))))
  (if (and n (<= 1 n 3)) n 2))

;; secs answers the seconds since a start time, with one decimal.
(define (secs t0)
  (/ (round (* 10 (/ (- (current-inexact-milliseconds) t0) 1000.0))) 10.0))

;; log-path is the file that keeps every timing of every run.
(define log-path (build-path (find-system-path (quote home-dir)) ".aiu-timings.log"))

;; previous-secs answers the last logged seconds of a step, or false.
(define (previous-secs name)
  (and (file-exists? log-path)
       (for/fold ([found #f]) ([l (in-list (file->lines log-path))])
         (define p (string-split l))
         (if (and (>= (length p) 4) (equal? (list-ref p 2) name))
             (string->number (list-ref p 3))
             found))))

;; log-step! appends one line: the clock, the level, the step name, the seconds.
(define (log-step! level name s)
  (with-handlers ([void void])
    (call-with-output-file log-path #:exists (quote append)
      (lambda (o) (fprintf o "~a ~a ~a ~a\n" (current-seconds) level name s)))))

;; pad fills a name with spaces to a column.
(define (pad s)
  (string-append s (make-string (max 1 (- 24 (string-length s))) #\space)))

;; step-line shows a step with its seconds, the seconds of the run before, and SLOW when it grew.
(define (step-line name s ok?)
  (define prev (previous-secs name))
  (define slow? (and prev (> s 2) (> s (* 1.5 prev))))
  (format "~a~a ~a s~a~a" (pad name) (if ok? "ok  " "FAIL") s
          (if prev (format "   prev ~a s" prev) "")
          (if slow? "   SLOW" "")))

;; compile-files are the files raco make builds in ONE call: one call per file cost 32 s each, five calls 172 s, one call 34 s.
(define compile-files
  (list "editor/src/entry/cli.rkt" "editor/src/dashboard/undo.rkt"
        "editor/src/dashboard/multi.rkt" "editor/src/dashboard/clip.rkt"
        "editor/src/entry/update.rkt"))

;; raco-path answers the raco next to the running racket, or the one on the path.
(define (raco-path)
  (define e (find-system-path (quote exec-file)))
  (define exe (if (absolute-path? e) e (find-executable-path e)))
  (define near (and exe (build-path (path-only exe) "raco")))
  (if (and near (file-exists? near)) near (find-executable-path "raco")))

;; stamp-path is the file whose time says when the last good compile ended.
(define stamp-path (build-path (find-system-path (quote home-dir)) ".aiu-build-stamp"))

;; sources-newer? says whether any .rkt file under editor/src is newer than the stamp, or the stamp is missing.
(define (sources-newer?)
  (define stamp (and (file-exists? stamp-path) (file-or-directory-modify-seconds stamp-path)))
  (or (not stamp)
      (for/or ([p (in-directory (build-path editor-root "editor" "src"))])
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
     (define ok #t)
     (let ()
       (define t (current-inexact-milliseconds))
       (define stale? (sources-newer?))
       (define-values (code text)
         (cond [(not stale?) (values 0 "")]
               [raco (capture editor-root raco (cons "make" compile-files))]
               [else (values 1 "raco was not found")]))
       (when (and stale? (= code 0)) (touch-stamp!))
       (set! records (append records (list (list "compile" (secs t) (= code 0)))))
       (unless (= code 0)
         (set! ok #f)
         (set! fail-lines (first-n (real-lines text) 12))))
     (when (and ok (>= level 2))
       (define t1 (current-inexact-milliseconds))
       (define nu (find-executable-path "nu"))
       (define-values (g-code g-text)
         (if nu (capture editor-root nu (list "gate/check.nu")) (values 1 "nu was not found")))
       (define g-lines (real-lines g-text))
       (define green? (regexp-match? #rx"light gate: green" g-text))
       (define bad (filter (lambda (l) (regexp-match? #px"^(COMMENT|FAIL)|light gate: red" l)) g-lines))
       (set! records (append records (list (list "gate" (secs t1) green?))))
       (unless green?
         (set! ok #f)
         (set! fail-lines (append (first-n bad 12) (if (null? bad) (first-n g-lines 8) (last-n g-lines 2))))))
     (define total (secs t-all))
     (define all (append records (list (list "total" total ok))))
     (define lines (for/list ([r (in-list all)]) (step-line (car r) (cadr r) (caddr r))))
     (for ([r (in-list all)]) (log-step! level (car r) (cadr r)))
     (define notes
       (append (if (< level 2) (list "gate                    skipped at level 1") (list))
               (if (= level 3) (list "timing                  not built yet") (list))))
     (emit (list "AIUTD UPDATE" (format "LEVEL ~a  ~a  ~a s" level (if ok "GREEN" "RED") total))
           (append lines notes fail-lines))
     (if ok 0 1)]))

;; run answers the verb: update works, the other tool verbs say they are not built yet.
(define (run args)
  (define verb (car args))
  (exit
   (cond
     [(equal? verb "update") (do-update (level-of args))]
     [else
      (emit (list "AIUTD" (string-upcase verb)) (list "not built yet, see plan.md"))
      0])))
