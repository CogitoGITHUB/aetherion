#lang racket/base

(require racket/list "split-paint.rkt")

(provide split-overlay-draw (all-from-out "split-paint.rkt"))

(define (split-overlay-cell row col text)
  (string-append "\u001b[" (number->string row) ";" (number->string col) "H" text))

(define (split-overlay-draw rects focus-id pane-of top left)
  (apply string-append
         (for/list ([rect (in-list rects)])
           (define id (car rect))
           (define width (cadddr rect))
           (define height (list-ref rect 4))
           (define row (+ top (caddr rect) 1))
           (define col (+ left (cadr rect) 1))
           (define focused? (equal? id focus-id))
           (define content (pane-of id focused? (max 1 (- width 2)) (max 0 (- height 2))))
           (define box (split-pane-box split-paint-fit-plain (car content) (if focused? (list) (cdr content)) width height focused?))
           (cond
             [focused?
              (define middle (if (> (length box) 2) (cadr box) ""))
              (string-append
               (split-overlay-cell row col (car box))
               (apply string-append
                      (for/list ([i (in-range 1 (sub1 height))])
                        (string-append (split-overlay-cell (+ row i) col (substring middle 0 1))
                                       (split-overlay-cell (+ row i) (+ col width -1) (substring middle (sub1 (string-length middle)))))))
               (split-overlay-cell (+ row height -1) col (last box)))]
             [else
              (apply string-append
                     (for/list ([line (in-list box)] [i (in-naturals)])
                       (split-overlay-cell (+ row i) col line)))]))))
