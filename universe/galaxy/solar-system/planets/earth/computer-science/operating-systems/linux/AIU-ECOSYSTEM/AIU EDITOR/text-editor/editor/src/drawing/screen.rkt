#lang racket/base
;; One job: the screen — the text, the cursor on the point, the mode line.
;; Registered in plan/package-tree.org; lands with TODO item 21.
;;
;; A painter and nothing else: it takes the text, where the point is and what
;; the mode line says, and answers the one string the terminal prints. It
;; reads no file and asks no engine, so a paint cannot change anything.
;;
;; The paint is a full redraw: the screen is cleared and written whole. Slower
;; than changing a line, and always right.

(require racket/list
         racket/string)

;; ansi answers one escape sequence, so the paint reads as words.
(define (ansi code)
  (string-append "\u001b[" code))

;; clear-screen is the whole screen, gone, and the cursor in the corner.
(define clear-screen (ansi "2J"))

;; cursor-to answers a move to one row and one column, both 1-based.
(define (cursor-to row column)
  (ansi (format "~a;~aH" row column)))

;; point-line answers the line and column the point is on, both 1-based,
;; counted in characters.
(define (point-line text point)
  (define at (min (max point 0) (string-length text)))
  (define before (substring text 0 at))
  (define rows (string-split before "\n"))
  (if (null? rows)
      (values 1 0)
      (values (length rows) (string-length (car (reverse rows))))))

;; fit answers one line cut or padded to exactly width characters.
(define (fit line width)
  (define clean (string-replace line "\t" "    "))
  (cond
    [(>= (string-length clean) width) (substring clean 0 width)]
    [else (string-append clean (make-string (- width (string-length clean)) #\space))]))

;; paint answers the whole screen for one state: the text scrolled so the
;; point is visible, the mode line under the text, the cursor on the point.
;; The caller prints the answer; nothing here writes to the terminal.
(define (paint text point width height mode-line)
  (define rows (string-split text "\n"))
  (define-values (row column) (point-line text point))
  (define visible (max 1 (- height 2)))
  (define first-row (max 1 (- row (quotient visible 2))))
  (define start (max 0 (sub1 first-row)))
  (define shown
    (for/list ([i (in-range visible)] #:when (< (+ start i) (length rows)))
      (list-ref rows (+ start i))))
  (string-join
   (append
    (list clear-screen)
    (for/list ([line (in-list shown)] [i (in-naturals 1)])
      (string-append (fit line width) "\n"))
    (list (ansi "7m") (fit mode-line width) (ansi "27m")
          (cursor-to (- row (sub1 first-row)) (+ column 1))))
   ""))

;; The painter, for the session above it.
(provide paint
         clear-screen
         cursor-to
         point-line)
