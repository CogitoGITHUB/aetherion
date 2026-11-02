#lang racket/base
;; One job: the screen — the text, the cursor on the point, the mode line.
;; Registered in plan/package-tree.org; lands with TODO item 21.
;;
;; A painter and nothing else: it takes the text, where the point is, the
;; first line of the window and what the mode line says, and answers the one
;; string the terminal prints. It reads no file and asks no engine, so a paint
;; cannot change anything.
;;
;; The point is a BYTE offset (the hot path counts bytes) and the screen counts
;; characters, so the two are converted here and nowhere else. The mode line
;; sits on the LAST row of the terminal, and the text never moves on its own:
;; the caller decides the first visible line, and the cursor is always drawn on
;; the row the text of the point is on.
;;
;; The paint is a full redraw: the screen is cleared and written whole. Slower
;; than changing a line, and always right.

(require racket/list
         racket/string)

;; ansi answers one escape sequence, so the paint reads as words.
(define (ansi code)
  (string-append "\u001b[" code))

;; clear-screen is the whole screen, gone, and the cursor in the corner. The
;; HOME is part of it: a frame must start at row 1 whatever was printed over
;; the last one, or the next frame would be drawn from wherever that text left
;; the cursor and the whole screen would shift.
(define clear-screen (string-append (ansi "2J") (ansi "H")))

;; sync-begin and sync-end wrap one frame so a terminal that knows the
;; synchronized update code shows it whole; others ignore both.
(define sync-begin (ansi "?2026h"))
;; the definition below belongs to the painter of the screen.
(define sync-end (ansi "?2026l"))

;; erase-lines puts an erase of the line before every line of a frame, so
;; old text goes as the new text is written and the screen is never blanked.
(define (erase-lines text)
  (string-append (ansi "2K")
                 (regexp-replace* #rx"\n" text (string-append "\n" (ansi "2K")))))

;; cursor-to answers a move to one row and one column, both 1-based.
(define (cursor-to row column)
  (ansi (format "~a;~aH" row column)))

;; decode-prefix answers the first N bytes of a text as a string. A byte that
;; lands inside a character is rounded down to that character's first byte, so
;; a point in the middle of a character is still a point on the screen.
(define (decode-prefix bytes n)
  (let loop ([take (min (max n 0) (bytes-length bytes))])
    (cond
      [(<= take 0) ""]
      [else
       (with-handlers ([exn:fail? (lambda (e) (loop (sub1 take)))])
         (bytes->string/utf-8 (subbytes bytes 0 take)))])))

;; point-line answers the line and column the point is on, both 1-based, and
;; the column counted in characters. The point is a byte offset into the text's
;; UTF-8 bytes; a point at the start of a line is on THAT line, never on the
;; line before it.
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

;; fit answers one line cut or padded to exactly width characters.
(define (fit line width)
  (define clean (string-replace line "\t" "    "))
  (cond
    [(>= (string-length clean) width) (substring clean 0 width)]
    [else (string-append clean (make-string (- width (string-length clean)) #\space))]))

;; footer-string answers the last rows of the screen. Nothing is drawn for an empty
;; text, one line is the old mode line in reverse video, and several lines are the
;; bar box in white text with no background.
(define (footer-string mode-line width)
  (cond [(string=? mode-line "") ""]
        [(regexp-match? #rx"\n" mode-line)
         (string-append (ansi "97m")
                        (string-join (map (lambda (l) (fit l width)) (string-split mode-line "\n" #:trim? #f)) "\n")
                        (ansi "0m"))]
        [else (string-append (ansi "7m") (fit mode-line width) (ansi "27m"))]))

;; paint answers the whole screen for one state: the text from the first visible
;; line pushed down by offset rows and right by left columns, the footer rows under
;; it, the overlay drawn over it, and the cursor on the point when there is one.
;; The view layer has no cursor: it is a page being read, not a point being put
;; down, and a cursor there would claim a place the keys cannot type at.
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

;; The painter, for the session above it.
(provide paint
         clear-screen
         cursor-to
         point-line)