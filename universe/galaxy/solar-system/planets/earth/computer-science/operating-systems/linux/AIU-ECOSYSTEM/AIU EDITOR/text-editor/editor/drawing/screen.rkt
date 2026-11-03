#lang racket/base

(require racket/list
         racket/string)

(define (ansi code)
  (string-append "\u001b[" code))

(define clear-screen (string-append (ansi "2J") (ansi "H")))

(define sync-begin (ansi "?2026h"))
(define sync-end (ansi "?2026l"))

(define (erase-lines text)
  (string-append (ansi "2K")
                 (regexp-replace* #rx"\n" text (string-append "\n" (ansi "2K")))))

(define (cursor-to row column)
  (ansi (format "~a;~aH" row column)))

(define (decode-prefix bytes n)
  (let loop ([take (min (max n 0) (bytes-length bytes))])
    (cond
      [(<= take 0) ""]
      [else
       (with-handlers ([exn:fail? (lambda (e) (loop (sub1 take)))])
         (bytes->string/utf-8 (subbytes bytes 0 take)))])))

(define (point-line text point)
  (define bytes (string->bytes/utf-8 text))
  (define before (decode-prefix bytes point))
  (define newlines
    (for/sum ([ch (in-string before)]) (if (char=? ch #\newline) 1 0)))
  (define last-start
    (for/fold ([start 0])
              ([ch (in-string before)]
               [i (in-naturals)])
      (if (char=? ch #\newline) (add1 i) start)))
  (values (add1 newlines) (- (string-length before) last-start)))

(define (fit line width)
  (define clean (string-replace line "\t" "    "))
  (cond
    [(>= (string-length clean) width) (substring clean 0 width)]
    [else (string-append clean (make-string (- width (string-length clean)) #\space))]))

(define (footer-string mode-line width)
  (cond [(string=? mode-line "") ""]
        [(regexp-match? #rx"\n" mode-line)
         (string-append (ansi "97m")
                        (string-join (map (lambda (l) (fit l width)) (string-split mode-line "\n" #:trim? #f)) "\n")
                        (ansi "0m"))]
        [else (string-append (ansi "7m") (fit mode-line width) (ansi "27m"))]))

(define (paint text point width height top mode-line cursor? preformatted?
               #:offset [offset 0] #:left [left 0] #:full [full width] #:overlay [overlay ""])
  (define rows (string-split text "\n" #:trim? #f))
  (define visible (max 1 (- height 1)))
  (define top-line (max 1 (min top (max 1 (length rows)))))
  (define-values (row column) (point-line text point))
  (define cursor-row (max top-line (min row (+ top-line (sub1 visible)))))
  (define shown
    (for/list ([i (in-range visible)])
      (define number (+ top-line i))
      (if (<= number (length rows)) (list-ref rows (sub1 number)) "")))
  (define pad (make-string left #\space))
  (define body
    (string-join
     (for/list ([line (in-list shown)])
       (string-append pad (if preformatted? line (fit line width))))
     "\n"))
  (define foot (footer-string mode-line full))
  (string-append sync-begin (ansi "H") (erase-lines (string-append (make-string offset #\newline) body (if (string=? foot "") "" (string-append "\n" foot))))
                 overlay
                 (if cursor?
                     (string-append (ansi "?25h")
                                    (cursor-to (+ offset (- cursor-row top-line -1)) (+ left column 1)))
                     (ansi "?25l")) sync-end))

(provide paint
         clear-screen
         cursor-to
         point-line)