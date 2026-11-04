#lang racket/base
(require "../pane/pane-grid.rkt")
(provide frame-inner-columns frame-inner-rows paint-screen-string)

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

(define (paint-screen-string grid bar-rows columns height)
  (define out (open-output-string))
  (define bar-count (length bar-rows))
  (define inner (frame-inner-columns columns))
  (define border-row (add1 bar-count))
  (write-string "\u001b[?2026h\u001b[?25l" out)
  (for ([row (in-list bar-rows)] [i (in-naturals 1)])
    (write-string (format "\u001b[~a;1H" i) out)
    (write-string row out)
    (write-string "\u001b[0m\u001b[K" out))
  (write-string (format "\u001b[~a;1H\u001b[0m╭~a╮" border-row (make-string inner #\─)) out)
  (for ([r (in-range (pane-grid-height grid))])
    (write-string (format "\u001b[~a;1H\u001b[0m│" (+ border-row 1 r)) out)
    (write-string (row-string (vector-ref (pane-grid-rows grid) r)) out)
    (write-string "\u001b[0m│" out))
  (write-string (format "\u001b[~a;1H\u001b[0m╰~a╯" (+ border-row 1 (pane-grid-height grid)) (make-string inner #\─)) out)
  (when (pane-grid-shown grid)
    (write-string (format "\u001b[~a;~aH\u001b[?25h"
                          (+ border-row 1 (pane-grid-cursor-row grid))
                          (+ 2 (pane-grid-cursor-column grid)))
                  out))
  (write-string "\u001b[?2026l" out)
  (get-output-string out))
