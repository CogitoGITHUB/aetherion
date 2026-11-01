#lang racket/base
;; One job: the aiutd tool verbs (update, test, docs, trace), one answer each,
;; every answer framed by two empty lines and a banner drawn by the notation
;; view. Loaded on first use, never at start.
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
  (define code
    (parameterize ([current-output-port out]
                   [current-error-port out]
                   [current-directory dir]
                   [current-input-port (open-input-string "")])
      (apply system*/exit-code exe args)))
  (values code (get-output-string out)))

;; term-width answers the terminal width, at most 70, or 56 when it is unknown.
(define (term-width)
  (define sh (find-executable-path "sh"))
  (define-values (code text)
    (if sh (capture (current-directory) sh (list "-c" "stty size < /dev/tty")) (values 1 "")))
  (define parts (string-split (string-trim text)))
  (define n (and (= code 0) (= (length parts) 2) (string->number (cadr parts))))
  (if (and n (> n 20)) (min n 70) 56))

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

;; emit prints two empty lines, the banner, an empty line, the detail lines, two empty lines.
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

;; compile-files are the files raco make builds, the same list the README gave.
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

;; real-lines drops empty lines and the harmless registered twice warnings.
(define (real-lines text)
  (filter (lambda (l)
            (and (not (string=? (string-trim l) ""))
                 (not (regexp-match? #rx"registered twice" l))))
          (string-split text "\n")))

;; do-update compiles, then runs the gate from level 2, and answers 0 or 1.
(define (do-update level)
  (cond
    [(not editor-root)
     (emit (list "AIUTD UPDATE" "RED") (list "the editor folder with gate was not found"))
     1]
    [else
     (unless (getenv "PLTCOMPILEDROOTS")
       (putenv "PLTCOMPILEDROOTS"
               (path->string (build-path (find-system-path (quote home-dir)) "aiu-compiled"))))
     (define t0 (current-inexact-milliseconds))
     (define raco (raco-path))
     (define-values (c-code c-text)
       (if raco (capture editor-root raco (cons "make" compile-files)) (values 1 "raco was not found")))
     (define c-lines (real-lines c-text))
     (define c-secs (secs t0))
     (cond
       [(not (= c-code 0))
        (emit (list "AIUTD UPDATE" (format "LEVEL ~a  RED" level))
              (cons (format "compile    FAIL  ~a s" c-secs) (first-n c-lines 12)))
        1]
       [(< level 2)
        (emit (list "AIUTD UPDATE" (format "LEVEL ~a  GREEN" level))
              (list (format "compile    ok    ~a s" c-secs) "gate       skipped at level 1"))
        0]
       [else
        (define nu (find-executable-path "nu"))
        (define t1 (current-inexact-milliseconds))
        (define-values (g-code g-text)
          (if nu (capture editor-root nu (list "gate/check.nu")) (values 1 "nu was not found")))
        (define g-lines (real-lines g-text))
        (define green? (regexp-match? #rx"light gate: green" g-text))
        (define bad (filter (lambda (l) (regexp-match? #px"^(COMMENT|FAIL)|light gate: red" l)) g-lines))
        (emit (list "AIUTD UPDATE" (format "LEVEL ~a  ~a" level (if green? "GREEN" "RED")))
              (append
               (list (format "compile    ok    ~a s" c-secs)
                     (format "gate       ~a  ~a s" (if green? "green" "RED") (secs t1)))
               (if (= level 3) (list "timing     not built yet") (list))
               (if green? (list) (append (first-n bad 12) (last-n g-lines 2)))))
        (if green? 0 1)])]))

;; run answers the verb: update works, the other tool verbs say they are not built yet.
(define (run args)
  (define verb (car args))
  (exit
   (cond
     [(equal? verb "update") (do-update (level-of args))]
     [else
      (emit (list "AIUTD" (string-upcase verb)) (list "not built yet, see plan.md"))
      0])))
