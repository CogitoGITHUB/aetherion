#lang racket/base
(require "../pane/pane-grid.rkt")
(provide frame-inner-columns frame-inner-rows paint-panes-string)

(define (frame-inner-columns columns) (- columns 2))
(define (frame-inner-rows height bar-count) (- height bar-count 2))

(define (row-string cells)
  (define out (open-output-string))
  (for/fold ([style ""]) ([cell (in-vector cells)])
    (cond
      [(char=? (car cell) #\nul) style]
      [else
       (unless (string=? style (cdr cell))
         (write-string "\u001b[0m" out)
         (write-string (cdr cell) out))
       (write-char (car cell) out)
       (cdr cell)]))
  (write-string "\u001b[0m" out)
  (get-output-string out))

(define (visible-rows grid scroll-offset)
  (define rows (pane-grid-rows grid))
  (define height (pane-grid-height grid))
  (cond
    [(or (zero? scroll-offset) (pane-grid-alternate grid)) rows]
    [else
     (define newest-first (pane-grid-history grid))
     (define count (min scroll-offset (length newest-first) height))
     (define older (reverse (for/list ([row (in-list newest-first)] [i (in-range count)]) row)))
     (list->vector (for/list ([row (in-list (append older (vector->list rows)))] [i (in-range height)]) row))]))

(define (move-to row column) (format "\u001b[~a;~aH" row column))

(define (border-chars focused?)
  (if focused?
      (list #\┏ #\┓ #\┗ #\┛ #\━ #\┃)
      (list #\╭ #\╮ #\╰ #\╯ #\─ #\│)))

(define (pane-fits? grid width height)
  (and (= (pane-grid-columns grid) (- width 2)) (= (pane-grid-height grid) (- height 2))))

(define (paint-pane! out entry bar-count)
  (define-values (x y width height grid scroll focused?) (apply values entry))
  (define chars (border-chars focused?))
  (define inner-width (- width 2))
  (define inner-height (- height 2))
  (define top (+ bar-count y 1))
  (define left (+ x 1))
  (define view-rows (and (pane-fits? grid width height) (visible-rows grid scroll)))
  (define side (list-ref chars 5))
  (write-string (format "~a\u001b[0m~a~a~a" (move-to top left) (list-ref chars 0) (make-string inner-width (list-ref chars 4)) (list-ref chars 1)) out)
  (for ([r (in-range inner-height)])
    (write-string (format "~a\u001b[0m~a" (move-to (+ top 1 r) left) side) out)
    (if view-rows
        (write-string (row-string (vector-ref view-rows r)) out)
        (write-string (make-string inner-width #\space) out))
    (write-string (format "\u001b[0m~a" side) out))
  (write-string (format "~a\u001b[0m~a~a~a" (move-to (+ top height -1) left) (list-ref chars 2) (make-string inner-width (list-ref chars 4)) (list-ref chars 3)) out))

(define (paint-panes-string entries bar-rows)
  (define out (open-output-string))
  (define bar-count (length bar-rows))
  (write-string "\u001b[?2026h\u001b[?25l" out)
  (for ([row (in-list bar-rows)] [i (in-naturals 1)])
    (write-string (format "\u001b[~a;1H\u001b[2K" i) out)
    (write-string row out)
    (write-string "\u001b[0m" out))
  (write-string (format "\u001b[~a;1H\u001b[0m\u001b[J" (add1 bar-count)) out)
  (for ([entry (in-list entries)])
    (paint-pane! out entry bar-count))
  (for ([entry (in-list entries)])
    (define-values (x y width height grid scroll focused?) (apply values entry))
    (when (and focused? (pane-grid-shown grid) (zero? scroll) (pane-fits? grid width height))
      (write-string (format "\u001b[~a;~aH\u001b[?25h" (+ bar-count y 2 (pane-grid-cursor-row grid)) (+ x 2 (pane-grid-cursor-column grid))) out)))
  (write-string "\u001b[?2026l" out)
  (get-output-string out))
