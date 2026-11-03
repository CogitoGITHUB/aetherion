#lang racket/base
;; One job: the screen text and the judging of the test driver: key bytes, plain screen, last frame, expect lines and the key trace.
(require racket/system racket/string racket/list racket/file racket/path "update-table.rkt")

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
;; colour-rx answers the regexp of the escape code for grey or white text.
(define (colour-rx c) (regexp (if (equal? c "grey") "\u001b\\[90m" "\u001b\\[97m")))

;; judge checks one expect line, colour lines against the raw last frame.
(define (judge l screen file-text seconds [rawf ""])
  (define m (regexp-match #px"^expect (screen|file) (contains|lacks) (.*)$" l))
  (define s (regexp-match #px"^expect seconds-under ([0-9.]+)$" l))
  (cond
    [m (define hay (if (equal? (cadr m) "screen") screen file-text))
       (define has? (regexp-match? (regexp (regexp-quote (cadddr m))) hay))
       (define ok? (if (equal? (caddr m) "contains") has? (not has?)))
       (list ok? (substring l 7))]
    [(regexp-match? #px"^expect colour (grey|white)$" l) (list (regexp-match? (colour-rx (cadr (regexp-match #px"^expect colour (grey|white)$" l))) rawf) (substring l 7))]
    [s (list (< seconds (string->number (cadr s))) (substring l 7))]
    [else (list #f (string-append "unknown line: " l))]))

;; visible shows every control character of a text as a caret and a letter, so an escape shows as ^[.
(define (visible s)
  (regexp-replace* (pregexp "[\u0001-\u0008\u000b-\u001f]") s
                   (lambda (m) (string-append "^" (string (integer->char (+ 64 (char->integer (string-ref m 0)))))))))

;; trace-file answers the path of the key trace log.
(define (trace-file) (or (current-trace-file) (build-path (find-system-path (quote home-dir)) ".aiu-trace.log")))

;; current-trace-file holds the trace log of the test running in this thread, so tests side by side each read their own; false means the shared log.
(define current-trace-file (make-parameter #f))

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


(provide key-bytes line-values plain-screen last-frame test-lines test-level colour-rx judge visible trace-file current-trace-file trace-size compact-trace trace-since key-modes)
