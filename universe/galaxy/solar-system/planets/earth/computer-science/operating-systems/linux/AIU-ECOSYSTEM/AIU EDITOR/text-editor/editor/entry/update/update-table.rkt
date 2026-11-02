#lang racket/base
;; One job: the base of the test driver: the folders, running tools, and the text and table of its output.
(require racket/system racket/string racket/list racket/file racket/path)

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

(require "../../notation/location.rkt")

;; notation-bin answers the notation program as a string, or false.
(define (notation-bin) (notation-bin-from here-dir))

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


(provide here-dir find-up editor-root notation-bin capture width-cache term-width banner-text wrap-line emit first-n last-n level-of secs log-path previous-secs log-step! pad fit fit-right name-width row-line border table-lines step-line)