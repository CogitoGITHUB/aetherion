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
  (if (or (< w 1) (<= (string-length s) w))
      (list s)
      (cons (substring s 0 w) (wrap-line (substring s w) w))))

;; emit prints two empty lines, the banner, the details, the banner again, two empty lines.
(define (emit head details)
  (newline)
  (newline)
  (write-string (banner-text head))
  (newline)
  (for ([d (in-list (table-lines details))])
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

;; fit pads or cuts a string to exactly w characters, left aligned.
(define (fit s w)
  (if (> (string-length s) w)
      (string-append (substring s 0 (max 0 (- w 1))) "…")
      (string-append s (make-string (- w (string-length s)) #\space))))

;; fit-right pads a string on the left to exactly w characters.
(define (fit-right s w)
  (define t (if (> (string-length s) w) (substring s 0 w) s))
  (string-append (make-string (- w (string-length t)) #\space) t))

;; name-width answers the width of the first table column.
(define (name-width) (max 12 (- (term-width) 31)))

;; row-line draws one table row with its four columns.
(define (row-line name status secs prev)
  (string-append "│ " (fit name (name-width)) " │ " (fit status 4) " │ " (fit-right secs 7) " │ " (fit-right prev 7) " │"))

;; border draws a horizontal rule with left, middle and right corners; cols? tells whether the column breaks show.
(define (border left mid right cols?)
  (define w (name-width))
  (define (bar n) (make-string n #\─))
  (string-append left
                 (if cols?
                     (string-append (bar (+ w 2)) mid (bar 6) mid (bar 9) mid (bar 9))
                     (bar (+ w 2 1 6 1 9 1 9)))
                 right))

;; table-lines turns the details into table lines: rows with columns, any other line in a full width box.
(define (table-lines details)
  (define inner (+ (name-width) 27))
  (define out (list))
  (define state (quote none))
  (define (add! l) (set! out (cons l out)))
  (for ([d (in-list details)])
    (cond
      [(regexp-match? #rx"^│" d)
       (cond [(eq? state (quote none))
              (add! (border "╭" "┬" "╮" #t))
              (add! (row-line "step" "stat" "secs" "prev"))
              (add! (border "├" "┼" "┤" #t))]
             [(eq? state (quote text)) (add! (border "├" "┬" "┤" #t))])
       (add! d)
       (set! state (quote cols))]
      [else
       (cond [(eq? state (quote none)) (add! (border "╭" "─" "╮" #f))]
             [(eq? state (quote cols)) (add! (border "├" "┴" "┤" #t))])
       (for ([l (in-list (wrap-line d inner))])
         (add! (string-append "│ " (fit l inner) " │")))
       (set! state (quote text))]))
  (cond [(eq? state (quote cols)) (add! (border "╰" "┴" "╯" #t))]
        [(eq? state (quote text)) (add! (border "╰" "─" "╯" #f))])
  (reverse out))

;; step-line shows a step with its seconds, the seconds of the run before, and SLOW when it grew.
(define (step-line name s ok?)
  (define prev (previous-secs name))
  (define slow? (and prev (> s 2) (> s (* 1.5 prev))))
  (row-line name (cond [(not ok?) "FAIL"] [slow? "SLOW"] [else "ok"]) (format "~a s" s) (if prev (format "~a s" prev) "")))

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
               [raco (capture editor-root raco (cons "make" compile-files))]
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
         (if nu (capture editor-root nu (append (list "gate/check.nu") (stage-args level))) (values 1 "nu was not found")))
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

;; key-bytes answers the text a terminal sends for a key name; a single character stands for itself.
(define (key-bytes k)
  (cond [(equal? k "space") " "]
        [(equal? k "escape") "\u001b"]
        [(equal? k "return") "\r"]
        [(equal? k "tab") "\t"]
        [(equal? k "backspace") "\u007f"]
        [(equal? k "up") "\u001b[A"]
        [(equal? k "down") "\u001b[B"]
        [(equal? k "right") "\u001b[C"]
        [(equal? k "left") "\u001b[D"]
        [else k]))

;; line-values answers the text after a key word on every line that starts with it.
(define (line-values lines key)
  (for/list ([l (in-list lines)] #:when (string-prefix? l (string-append key " ")))
    (string-trim (substring l (add1 (string-length key))))))

;; plain-screen strips the terminal codes of a frame; reverse video shows as brackets.
(define (plain-screen s)
  (define a (regexp-replace* #rx"\u001b\\[7m" s "["))
  (define b (regexp-replace* #rx"\u001b\\[27m" a "]"))
  (define c (regexp-replace* #px"\u001b\\[[0-9;?]*[A-Za-z]" b ""))
  (regexp-replace* #rx"\r" c ""))

;; last-frame answers the last full frame in the output, the one the editor drew last.
(define (last-frame text)
  (define parts (regexp-split (regexp-quote "\u001b[?2026h") text))
  (define frames (filter (lambda (p) (regexp-match? #rx"^\u001b\\[H" p)) parts))
  (if (null? frames) text (last frames)))

;; test-lines answers the trimmed, non-empty lines of a test file.
(define (test-lines path)
  (filter (lambda (l) (not (string=? l ""))) (map string-trim (file->lines path))))

;; test-level answers the level of a test file, 2 when it names none.
(define (test-level path)
  (define v (line-values (test-lines path) "level"))
  (or (and (pair? v) (string->number (car v))) 2))

;; judge checks one expect line against the screen, the file text and the seconds; answers (ok? text).
(define (judge l screen file-text seconds)
  (define m (regexp-match #px"^expect (screen|file) (contains|lacks) (.*)$" l))
  (define s (regexp-match #px"^expect seconds-under ([0-9.]+)$" l))
  (cond
    [m (define hay (if (equal? (cadr m) "screen") screen file-text))
       (define has? (regexp-match? (regexp (regexp-quote (cadddr m))) hay))
       (define ok? (if (equal? (caddr m) "contains") has? (not has?)))
       (list ok? (substring l 7))]
    [s (list (< seconds (string->number (cadr s))) (substring l 7))]
    [else (list #f (string-append "unknown line: " l))]))

;; visible shows every control character of a text as a caret and a letter, so an escape shows as ^[.
(define (visible s)
  (regexp-replace* (pregexp "[\u0001-\u0008\u000b-\u001f]") s
                   (lambda (m) (string-append "^" (string (integer->char (+ 64 (char->integer (string-ref m 0)))))))))

;; trace-file answers the path of the key trace log.
(define (trace-file) (build-path (find-system-path (quote home-dir)) ".aiu-trace.log"))

;; trace-size answers how many bytes the key trace log holds now, zero when it is missing.
(define (trace-size) (with-handlers ([void (lambda (e) 0)]) (file-size (trace-file))))

;; compact-trace shortens one trace line to the pending keys and the milliseconds so it fits one table row.
(define (compact-trace l)
  (define m (regexp-match #px"^[0-9.]+ act-on ([0-9]+)[0-9.]* ms pending (.*) go-on" l))
  (if m (string-append "keys " (caddr m) " " (cadr m) "ms") l))

;; trace-since answers the last 10 trace lines written after the given byte offset, marked with t.
(define (trace-since start)
  (with-handlers ([void (lambda (e) (list))])
    (let ([bs (call-with-input-file (trace-file) (lambda (i) (file-position i start) (read-bytes 100000 i)))])
      (if (bytes? bs)
          (cons "    key trace of this run, last 10 lines:"
                (map (lambda (l) (string-append "    t " (compact-trace l)))
                     (last-n (string-split (bytes->string/utf-8 bs #\?) "\n") 10)))
          (list "    key trace of this run: empty")))))

;; key-modes answers one line per fed key: the mode shown on the screen after that key.
(define (key-modes dir names)
  (for/list ([n (in-list names)] [i (in-naturals)])
    (define f (build-path dir (format "s~a.bin" i)))
    (define raw (with-handlers ([void (lambda (e) #"")]) (file->bytes f)))
    (define scr (with-handlers ([void (lambda (e) "")]) (plain-screen (last-frame (bytes->string/utf-8 raw #\?)))))
    (define m (regexp-match #px"╭─ ([a-z]+( [a-z]+)?) \\[" scr))
    (let* ([ls (string-split scr "\n" #:trim? #f)]
           [tail (let loop ([l ls]) (cond [(null? l) (list)] [(regexp-match? #rx"╭─ [a-z]+ [a-z]+ \\[|╭─ [a-z]+ \\[" (car l)) l] [else (loop (cdr l))]))])
      (string-append "    after " n " (frames " (number->string (length (regexp-match* (byte-regexp (regexp-quote (bytes-append (bytes 27) #"[?2026l"))) raw))) "): " (if m (cadr m) "no mode line") (let ([u (regexp-match #px"undo:[^│╮╯]{3,60}" scr)]) (if u (string-append " [" (car u) "]") "")) " | "
                     (let ([s (string-join (map string-trim (first-n (if (pair? tail) (cdr tail) tail) 2)) " / ")]) (if (> (string-length s) 70) (substring s 0 70) s))))))

;; live-last holds the clock of the last live line.
(define live-last (box (current-inexact-milliseconds)))

;; live prints one line with the seconds since the previous line, so a hang shows its last step.
(define (live msg) (let ([now (current-inexact-milliseconds)]) (eprintf "  live +~as ~a\n" (real->decimal-string (/ (- now (unbox live-last)) 1000.0) 1) msg) (set-box! live-last now)) (flush-output (current-error-port)))

;; drive-editor runs the editor in a pty, sends one key per finished frame, saves a snapshot after each key and the exit code.
(define (drive-editor dir copy chunks out out1 code-file)
  (define sh (find-executable-path "sh"))
  (define-values (sp so si se)
    (subprocess #f #f (quote stdout) sh "-c" (string-append "AIU_TRACE=1 exec script -qec \"aiutd " copy "\" /dev/null")))
  (define acc (open-output-bytes))
  (define marker (byte-regexp (regexp-quote (bytes-append (bytes 27) #"[?2026l"))))
  (define buf (make-bytes 4096))
  (define (trace-lines) (with-handlers ([void (lambda (e) 0)]) (length (regexp-match* (byte-regexp (bytes 10)) (file->bytes (trace-file))))))
  (define (frames) (length (regexp-match* marker (get-output-bytes acc))))
  (define (wait-frame n [tl #f])
    (define deadline (+ (current-inexact-milliseconds) 20000))
    (let loop ()
      (cond
        [(and (> (frames) n) (or (not tl) (> (trace-lines) tl))) #t]
        [else
         (define left (- deadline (current-inexact-milliseconds)))
         (cond
           [(<= left 0) #f]
           [(sync/timeout (/ left 1000.0) so)
            (define k (read-bytes-avail! buf so))
            (cond [(eof-object? k) #f]
                  [else (write-bytes buf acc 0 k) (loop)])]
           [else #f])])))
  (define (save-to path)
    (call-with-output-file path #:exists (quote truncate) (lambda (o) (write-bytes (get-output-bytes acc) o))))
  (define note
    (if (not (wait-frame 0))
        "none: no first frame in 20 s"
        (let loop ([cs chunks] [i 0])
          (cond
            [(null? cs) #f]
            [else
             (define n (frames))
             (define tl (trace-lines))
             (begin (live (format "send key ~a" i)) (write-string (car cs) si))
             (flush-output si)
             (cond
               [(wait-frame n tl)
                (begin (live (format "frame after key ~a" i)) (save-to (build-path dir (format "s~a.bin" i))))
                (loop (cdr cs) (+ i 1))]
               [else (live (format "NO FRAME after key ~a in 20 s" i)) (format "none: no frame after key ~a" i)])]))))
  (save-to out1)
  (begin (live "send q") (write-string "q" si))
  (flush-output si)
  (define done (begin (live "wait for exit, 15 s at most") (sync/timeout 15 sp)))
  (begin (live (if done "editor exited, draining output" "editor did not exit, killing it, draining output")) (unless done (subprocess-kill sp #t)))
  (let loop ()
    (when (sync/timeout 1 so)
      (define k (read-bytes-avail! buf so))
      (unless (eof-object? k)
        (write-bytes buf acc 0 k)
        (loop))))
  (begin (live "output drained, saving") (save-to out))
  (call-with-output-file code-file #:exists (quote truncate)
    (lambda (o) (write-string (or note (if done (number->string (subprocess-status sp)) "124")) o)))
  (close-output-port si)
  (close-input-port so))

;; wrap-text cuts one line into pieces of at most 90 characters.
(define (wrap-text l)
  (if (<= (string-length l) 90) (list l) (cons (substring l 0 90) (wrap-text (substring l 90)))))

;; diagnose answers the lines that explain a failed test: exit code, mid frame, last frame.
(define (diagnose code-file out out1)
  (define code (with-handlers ([void (lambda (e) "unknown")]) (string-trim (file->string code-file))))
  (define raw (with-handlers ([void (lambda (e) #"")]) (file->bytes out)))
  (define frame (with-handlers ([void (lambda (e) "")]) (plain-screen (last-frame (bytes->string/utf-8 raw #\?)))))
  (define tail (reverse (first-n (reverse (string-split frame "\n" #:trim? #f)) 10)))
  (append
   (list (string-append "    cause: exit code " code (if (equal? code "124") " = killed, the editor did not quit after q within 15 s" ""))
         (string-append "    mid frame: " (if (file-exists? out1) "saved" "MISSING, the editor produced nothing in 4 s"))
         "    last frame at the end:")
   (map (lambda (l) (string-append "    > " l)) (apply append (map wrap-text tail)))))

;; run-test runs one test file on a copy of its page in a temporary folder; answers (name seconds ok? detail-lines).
(define (run-test path)
  (define lines (test-lines path))
  (define name (let ([v (line-values lines "test")]) (if (pair? v) (car v) "unnamed")))
  (define page (let ([v (line-values lines "file")]) (if (pair? v) (car v) "test.aiu")))
  (define input
    (apply string-append
           (for/list ([l (in-list lines)])
             (cond [(string-prefix? l "keys ") (apply string-append (map key-bytes (string-split (substring l 5))))]
                   [(string-prefix? l "type ") (substring l 5)]
                   [else ""]))))
  (define dir (make-temporary-file "aiutd-test~a" (quote directory)))
  (define copy (build-path dir page))
  (copy-file (build-path editor-root page) copy)
  (define keys-file (path->string (build-path dir "keys.bin")))
  (define out (path->string (build-path dir "out.bin")))
  (define out1 (path->string (build-path dir "mid.bin")))
  (call-with-output-file keys-file #:exists (quote truncate) (lambda (o) (write-string input o)))
  (when (member "repo git" lines) (capture dir (find-executable-path "git") (list "init" "-q")))
  (define trace-start (trace-size))
  (define t0 (current-inexact-milliseconds))
  (define chunks
    (apply append
           (for/list ([l (in-list lines)])
             (cond [(string-prefix? l "keys ") (map key-bytes (string-split (substring l 5)))]
                   [(string-prefix? l "type ") (list (substring l 5))]
                   [else (list)]))))
  (define code-file (path->string (build-path dir "code.txt")))
  (drive-editor dir (path->string copy) chunks out out1 code-file)
  (define seconds (begin (live "driver returned") (secs t0)))
  (define raw (if (file-exists? out1) (file->bytes out1) #""))
  (live "plain screen")
  (define screen (plain-screen (last-frame (bytes->string/utf-8 raw #\?))))
  (define file-text (with-handlers ([void (lambda (e) "")]) (file->string copy)))
  (live "judging")
  (define verdicts
    (for/list ([l (in-list lines)] #:when (string-prefix? l "expect "))
      (judge l screen file-text seconds)))
  (define ok? (and (pair? verdicts) (andmap car verdicts)))
  (live "diagnosing")
  (define why (if ok? (list) (append (diagnose code-file out out1) (trace-since trace-start) (list "    mode after each key:") (key-modes dir (string-split (string-join (line-values lines "keys") " "))) (list "    file head, first 6 lines:") (map (lambda (l) (string-append "    f " l)) (apply append (map wrap-text (first-n (string-split (visible file-text) "\n" #:trim? #f) 6)))))))
  (with-handlers ([void void])
    (display-to-file screen (build-path (find-system-path (quote home-dir)) (string-append ".aiu-last-test-" name ".txt")) #:exists (quote truncate)))
  (live "deleting temp folder")
  (delete-directory/files dir)
  (live "building report")
  (define shown (first-n (string-split screen "\n" #:trim? #f) 24))
  (list name seconds ok?
        (append (list (string-append "    keys " (string-join (line-values lines "keys") " ")))
                (for/list ([v (in-list verdicts)])
                  (string-append "    " (if (car v) "ok   " "FAIL ") (cadr v)))
                why)))

;; run-all-tests runs every test file of the level or below and answers the list of results.
(define (run-all-tests level)
  (define dir (and editor-root (build-path editor-root "gate" "tests")))
  (define files
    (if (and dir (directory-exists? dir))
        (sort (filter (lambda (p) (regexp-match? #rx"[.]test$" (path->string p)))
                      (directory-list dir #:build? #t))
              string<? #:key path->string)
        (list)))
  (define wanted (filter (lambda (p) (<= (test-level p) level)) files))
  (for/list ([p (in-list wanted)]) (run-test p)))

;; arg-value answers the word after a flag in the arguments, or #f when the flag is missing.
(define (arg-value args flag)
  (define m (member flag args))
  (and m (pair? (cdr m)) (cadr m)))

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
     [(equal? verb "test") (do-test (level-of args) (arg-value args "--only") (max 1 (or (string->number (or (arg-value args "--repeat") "1")) 1)))]
     [else
      (emit (list "AIUTD" (string-upcase verb)) (list "not built yet, see plan.md"))
      0])))
