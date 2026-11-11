#lang racket/base
(require racket/system racket/string racket/list racket/file racket/path)

(define here-dir
  (let ([src (variable-reference->module-source (#%variable-reference))])
    (if (path? src) (path-only src) (current-directory))))

(define (find-up start test)
  (let loop ([d start] [n 0])
    (cond [(test d) d]
          [(> n 8) #f]
          [else (loop (simplify-path (build-path d (quote up))) (add1 n))])))

(define editor-root
  (or (find-up here-dir (lambda (d) (directory-exists? (build-path d "docs")))) here-dir))

(require "../../bridge/location.rkt")

(define (notation-bin) (notation-bin-from here-dir))

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

(define width-cache #f)

(define (term-width)
  (unless width-cache
    (define sh (find-executable-path "sh"))
    (define-values (code text)
      (if sh (capture (current-directory) sh (list "-c" "stty size < /dev/tty")) (values 1 "")))
    (define parts (string-split (string-trim text)))
    (define n (and (= code 0) (= (length parts) 2) (string->number (cadr parts))))
    (set! width-cache (if (and n (> n 20)) (min n 70) 56)))
  width-cache)

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

(define (wrap-line s w)
  (if (or (< w 1) (<= (string-length s) w))
      (list s)
      (cons (substring s 0 w) (wrap-line (substring s w) w))))

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

(define (first-n l n) (if (> (length l) n) (take l n) l))

(define (last-n l n) (if (> (length l) n) (take-right l n) l))

(define (level-of args)
  (define m (member "--level" args))
  (define n (and m (pair? (cdr m)) (string->number (cadr m))))
  (if (and n (<= 1 n 3)) n 2))

(define (secs t0)
  (/ (round (* 10 (/ (- (current-inexact-milliseconds) t0) 1000.0))) 10.0))

(define log-path (build-path (find-system-path (quote home-dir)) ".aiu-timings.log"))

(define (previous-secs name)
  (and (file-exists? log-path)
       (for/fold ([found #f]) ([l (in-list (file->lines log-path))])
         (define p (string-split l))
         (if (and (>= (length p) 4) (equal? (list-ref p 2) name))
             (string->number (list-ref p 3))
             found))))

(define (log-step! level name s)
  (with-handlers ([void void])
    (call-with-output-file log-path #:exists (quote append)
      (lambda (o) (fprintf o "~a ~a ~a ~a\n" (current-seconds) level name s)))))

(define (pad s)
  (string-append s (make-string (max 1 (- 24 (string-length s))) #\space)))

(define (fit s w)
  (if (> (string-length s) w)
      (string-append (substring s 0 (max 0 (- w 1))) "…")
      (string-append s (make-string (- w (string-length s)) #\space))))

(define (fit-right s w)
  (define t (if (> (string-length s) w) (substring s 0 w) s))
  (string-append (make-string (- w (string-length t)) #\space) t))

(define (name-width) (max 12 (- (term-width) 31)))

(define (row-line name status secs prev)
  (string-append "│ " (fit name (name-width)) " │ " (fit status 4) " │ " (fit-right secs 7) " │ " (fit-right prev 7) " │"))

(define (border left mid right cols?)
  (define w (name-width))
  (define (bar n) (make-string n #\─))
  (string-append left
                 (if cols?
                     (string-append (bar (+ w 2)) mid (bar 6) mid (bar 9) mid (bar 9))
                     (bar (+ w 2 1 6 1 9 1 9)))
                 right))

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

(define (step-line name s ok?)
  (define prev (previous-secs name))
  (define slow? (and prev (> s 2) (> s (* 1.5 prev))))
  (row-line name (cond [(not ok?) "FAIL"] [slow? "SLOW"] [else "ok"]) (format "~a s" s) (if prev (format "~a s" prev) "")))


(provide gate-root here-dir find-up editor-root notation-bin capture width-cache term-width banner-text wrap-line emit first-n last-n level-of secs log-path previous-secs log-step! pad fit fit-right name-width row-line border table-lines step-line)
(define gate-root (build-path (or (find-up here-dir (lambda (d) (directory-exists? (build-path d "gate")))) here-dir) "gate"))
